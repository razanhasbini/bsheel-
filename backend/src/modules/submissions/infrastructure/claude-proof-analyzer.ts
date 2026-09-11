import Anthropic from '@anthropic-ai/sdk';
import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
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

/// Vision analysis via Anthropic's Messages API (#47).
///
/// The second implementation of `ProofAnalyzer`, kept so the eval can score
/// both providers over the same labelled history and pick on measured
/// accuracy rather than on preference. It draws its judging policy and its
/// verdict schema from `domain/proof-prompt.ts`, the same source the OpenAI
/// adapter uses — if each carried its own prompt, the eval would be comparing
/// prompts as much as providers.
///
/// Provider-specific choices here: `strict: true` tool use to constrain the
/// verdict shape, adaptive thinking with effort rising per rung, and
/// `cache_control` on the system prompt, which is byte-identical across calls
/// for a given verifiability and tier.
@Injectable()
export class ClaudeProofAnalyzer implements ProofAnalyzer {
  readonly provider = 'anthropic' as const;
  private readonly logger = new Logger(ClaudeProofAnalyzer.name);
  private readonly client?: Anthropic;
  private readonly models: Record<ProofTier, string>;

  constructor(private readonly config: ConfigService<Environment, true>) {
    this.models = {
      triage: config.get('AI_VERIFICATION_MODEL_TRIAGE_ANTHROPIC', { infer: true }),
      deep: config.get('AI_VERIFICATION_MODEL_DEEP_ANTHROPIC', { infer: true }),
      reject_review: config.get('AI_VERIFICATION_MODEL_REJECT_ANTHROPIC', { infer: true }),
    };
    const apiKey = config.get('ANTHROPIC_API_KEY', { infer: true });
    if (
      config.get('AI_VERIFICATION_ENABLED', { infer: true })
      && config.get('AI_VERIFICATION_PROVIDER', { infer: true }) === 'anthropic'
      && apiKey
    ) {
      this.client = new Anthropic({
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
        message: 'AI proof verification is not configured for Anthropic',
      });
    }

    const model = this.models[tier];
    const response = await client.messages.create({
      model,
      max_tokens: 2048,
      // Haiku takes a token budget; the 5-series models take adaptive
      // thinking and are tuned with `effort` instead.
      ...(model.startsWith('claude-haiku')
        ? { thinking: { type: 'enabled' as const, budget_tokens: 1024 } }
        : { thinking: { type: 'adaptive' as const } }),
      output_config: {
        effort: tier === 'triage' ? 'low' : tier === 'deep' ? 'medium' : 'high',
      },
      system: [
        {
          type: 'text',
          text: buildJudgingPrompt(request.verifiability, tier),
          cache_control: { type: 'ephemeral' },
        },
      ],
      tools: [
        {
          name: 'record_verdict',
          description: 'Record the verdict for this proof. Call exactly once.',
          strict: true,
          input_schema: verdictJsonSchema,
        },
      ],
      messages: [
        {
          role: 'user',
          content: [
            ...request.images.map((image) => ({
              type: 'image' as const,
              source: { type: 'base64' as const, media_type: image.mediaType, data: image.base64 },
            })),
            { type: 'text' as const, text: describeSubmission(request) },
          ],
        },
      ],
    });

    const usage = {
      inputTokens: response.usage.input_tokens,
      outputTokens: response.usage.output_tokens,
    };

    // A safety decline is not a verdict about the proof.
    if (response.stop_reason === 'refusal') {
      this.logger.warn(
        { model, tier, category: response.stop_details?.category ?? null },
        'Proof analysis declined by safety classifier',
      );
      return escalatedAnalysis({
        tier,
        model,
        ...usage,
        reason: 'The agent declined to analyse this proof. A human decision is required.',
      });
    }

    const call = response.content.find(
      (block) => block.type === 'tool_use' && block.name === 'record_verdict',
    );
    if (!call || call.type !== 'tool_use') {
      this.logger.warn({ model, tier, stopReason: response.stop_reason }, 'Proof analysis returned no verdict');
      return escalatedAnalysis({
        tier,
        model,
        ...usage,
        reason: 'The agent returned no verdict. A human decision is required.',
      });
    }

    // Same clamping and truncation as the OpenAI adapter, from the same
    // function, so a per-provider accuracy difference in the eval is a
    // difference in judgement and not in post-processing.
    return parseVerdictPayload(call.input as VerdictPayload, tier, model, usage);
  }
}
