import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import OpenAI from 'openai';
import type { Environment } from '../../../config/environment.js';
import {
  buildJudgingPrompt,
  describeSubmission,
  parseVerdictPayload,
  verdictJsonSchema,
  type VerdictPayload,
} from '../domain/proof-prompt.js';
import {
  escalatedAnalysis,
  type ProofAnalysis,
  type ProofAnalysisRequest,
  type ProofAnalyzer,
  type ProofTier,
} from '../domain/proof-verification.types.js';

/// Vision analysis via OpenAI's Responses API (#47).
///
/// Three things here are provider-specific and were chosen from the current
/// documentation rather than from habit:
///
///   * The **Responses API**, which is the current surface for image input.
///   * **Strict `json_schema` structured output**, which is grammar-
///     constrained — the model cannot emit a response that violates the
///     schema, so there is no defensive parsing and no malformed-verdict path.
///   * **`detail` per tier.** A low-detail image costs roughly an order of
///     magnitude fewer tokens than a high-detail one, which is what makes a
///     cheap triage rung worth having. Reading text in a frame needs `high`;
///     deciding whether a photo is broadly of a sunrise does not.
///
/// The model comes from the tier, and the tiers differ ~50x in price, so the
/// cascade is the dominant cost lever rather than a stylistic preference.
@Injectable()
export class OpenAiProofAnalyzer implements ProofAnalyzer {
  readonly provider = 'openai' as const;
  private readonly logger = new Logger(OpenAiProofAnalyzer.name);
  private readonly client?: OpenAI;
  private readonly models: Record<ProofTier, string>;

  constructor(private readonly config: ConfigService<Environment, true>) {
    this.models = {
      triage: config.get('AI_VERIFICATION_MODEL_TRIAGE', { infer: true }),
      deep: config.get('AI_VERIFICATION_MODEL_DEEP', { infer: true }),
      reject_review: config.get('AI_VERIFICATION_MODEL_REJECT', { infer: true }),
    };
    const apiKey = config.get('OPENAI_API_KEY', { infer: true });
    // The environment schema refuses to boot with the feature on, this
    // provider selected, and no key — so a missing client means it is off.
    if (
      config.get('AI_VERIFICATION_ENABLED', { infer: true })
      && config.get('AI_VERIFICATION_PROVIDER', { infer: true }) === 'openai'
      && apiKey
    ) {
      this.client = new OpenAI({
        apiKey,
        timeout: config.get('AI_VERIFICATION_TIMEOUT_MS', { infer: true }),
        maxRetries: 2,
      });
    }
  }

  get enabled(): boolean {
    return this.client !== undefined;
  }

  async analyze(request: ProofAnalysisRequest, tier: ProofTier): Promise<ProofAnalysis> {
    const client = this.client;
    if (!client) {
      throw new ServiceUnavailableException({
        code: 'AI_VERIFICATION_DISABLED',
        message: 'AI proof verification is not configured for OpenAI',
      });
    }

    const model = this.models[tier];
    // Triage only has to separate "obviously fine" from "look closer", and
    // low detail is roughly an order of magnitude cheaper per image. The
    // upper rungs are where the frame is actually read.
    const detail: OpenAI.Responses.ImageDetail = tier === 'triage' ? 'low' : 'high';

    const response = await client.responses.create({
      model,
      // Effort rises with the rung. The top rung is the only one permitted to
      // conclude that proof is fake, so it is the one worth thinking hard.
      reasoning: { effort: tier === 'triage' ? 'low' : tier === 'deep' ? 'medium' : 'high' },
      instructions: buildJudgingPrompt(request.verifiability, tier),
      input: [
        {
          role: 'user' as const,
          content: [
            ...request.images.map((image) => ({
              type: 'input_image' as const,
              image_url: `data:${image.mediaType};base64,${image.base64}`,
              detail,
            })),
            { type: 'input_text' as const, text: describeSubmission(request) },
          ],
        },
      ],
      text: {
        format: {
          type: 'json_schema',
          name: 'proof_verdict',
          strict: true,
          schema: verdictJsonSchema,
        },
      },
    });

    return this.toAnalysis(response, tier, model);
  }

  private toAnalysis(
    response: OpenAI.Responses.Response,
    tier: ProofTier,
    model: string,
  ): ProofAnalysis {
    const usage = {
      inputTokens: response.usage?.input_tokens ?? null,
      outputTokens: response.usage?.output_tokens ?? null,
    };

    // An incomplete response is not an opinion about the proof. Escalating is
    // the only honest outcome — the agent genuinely did not finish judging.
    if (response.status === 'incomplete' || !response.output_text) {
      this.logger.warn(
        { model, tier, status: response.status, reason: response.incomplete_details?.reason },
        'Proof analysis did not complete',
      );
      return escalatedAnalysis({
        tier,
        model,
        ...usage,
        reason: 'The agent did not finish analysing this proof. A human decision is required.',
      });
    }

    let parsed: VerdictPayload;
    try {
      parsed = JSON.parse(response.output_text) as VerdictPayload;
    } catch {
      // Should be unreachable under strict schema, which is grammar-
      // constrained. Handled anyway rather than trusted, because the failure
      // mode of trusting it is an exception in a queue worker.
      this.logger.error({ model, tier }, 'Structured output was not valid JSON');
      return escalatedAnalysis({
        tier,
        model,
        ...usage,
        reason: 'The agent returned an unreadable verdict. A human decision is required.',
      });
    }

    // The schema guarantees the shape; the values still come from a model, so
    // the shared parser clamps and bounds them before they reach columns with
    // CHECK constraints — and clamps them identically for both providers, so
    // the eval compares judgement rather than post-processing.
    return parseVerdictPayload(parsed, tier, model, usage);
  }
}
