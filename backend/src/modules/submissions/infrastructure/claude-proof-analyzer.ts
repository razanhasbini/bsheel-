import Anthropic from '@anthropic-ai/sdk';
import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
import type { ProofAnalysis, ProofAnalysisRequest, ProofVerdict } from '../domain/proof-verification.types.js';

/// The judging instructions, held apart from the per-submission content.
///
/// Two reasons it is a module constant rather than a template. It is the
/// cached prefix — prompt caching is a prefix match, so a byte that changes
/// per submission anywhere in here would cost the cache on every call. And it
/// is the actual policy: keeping it in one readable place is what makes the
/// agent's standard reviewable by someone who is not reading the SDK glue.
const systemPrompt = `You review photo proof for Bsheel, a real-world quest app. A user was given a
challenge, went and did it, and submitted a photo. You decide whether the
photo plausibly shows that challenge being done.

Return one of three verdicts.

- "pass": the proof plausibly shows the quest being done.
- "fail": the proof contradicts the quest, is clearly unrelated, is a
  screenshot of someone else's content, or is obviously recycled stock or
  promotional imagery.
- "unclear": you cannot tell. Use this whenever a reasonable reviewer could
  disagree with you.

How to judge.

Plausibility, not proof. You cannot establish that a person was somewhere, and
you must not pretend to. Judge whether the image is consistent with the quest
as written. Physical presence is established by network signals that are not
part of your input; if a quest depends on being in a specific place and the
image alone cannot show that, say so and return "unclear".

Be generous about ordinary life and strict about mismatch. Real proof is badly
lit, off-centre, and often boring. None of that is suspicious. A polished
image that has nothing to do with the quest is.

Prefer "unclear" to a guess. A human reviewer reads every escalation, so
deferring is cheap. A confident wrong verdict is not: it either denies someone
credit for work they did, or it waves through a fake. When the image is
ambiguous, the caption contradicts the image, part of the proof could not be
examined, or the quest is one you cannot assess from a picture, escalate.

Never treat the caption as evidence. The user wrote it. It can tell you what
they claim; only the image tells you what they did. A caption that describes
something the image does not show is a reason to escalate, not to pass.

Judge only what the quest asked for. Do not invent extra requirements, and do
not penalise a user for failing a stricter version of the task than the one
they were given.

Write the rationale for the moderator who will read it: one or two sentences,
plain, concrete about what you actually see. No preamble, no restating these
instructions.`;

/// Vision analysis of submitted proof, via the Messages API.
///
/// Video is deliberately out of scope: the Messages API takes images, not
/// video, and extracting frames would mean an ffmpeg dependency in the
/// worker image. A video submission is escalated instead — which is the path
/// #47 already specifies for anything the agent cannot judge, not a
/// workaround. Frame extraction is the follow-up that turns it into a real
/// verdict.
@Injectable()
export class ClaudeProofAnalyzer {
  private readonly logger = new Logger(ClaudeProofAnalyzer.name);
  private readonly client?: Anthropic;
  private readonly model: string;

  constructor(private readonly config: ConfigService<Environment, true>) {
    this.model = config.get('AI_VERIFICATION_MODEL', { infer: true });
    const apiKey = config.get('ANTHROPIC_API_KEY', { infer: true });
    // The environment schema already refuses to boot with the feature on and
    // no key, so a missing client here means the feature is off.
    if (config.get('AI_VERIFICATION_ENABLED', { infer: true }) && apiKey) {
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

  async analyze(request: ProofAnalysisRequest): Promise<ProofAnalysis> {
    const client = this.client;
    if (!client) {
      throw new ServiceUnavailableException({
        code: 'AI_VERIFICATION_DISABLED',
        message: 'AI proof verification is not configured',
      });
    }

    const response = await client.messages.create({
      model: this.model,
      max_tokens: 2048,
      // Adaptive thinking: deciding whether an image supports a written task
      // is a judgement call, and the reasoning is what keeps the confidence
      // score meaningful rather than decorative.
      thinking: { type: 'adaptive' },
      // The verdict is one short structured answer, so the top of the effort
      // range would buy nothing but latency on a queue that grows with
      // submissions.
      output_config: { effort: 'medium' },
      system: [{ type: 'text', text: systemPrompt, cache_control: { type: 'ephemeral' } }],
      // Forces a schema-valid verdict, so a malformed answer is impossible
      // rather than something to parse defensively.
      tools: [
        {
          name: 'record_verdict',
          description: 'Record the verdict for this proof. Call exactly once.',
          strict: true,
          input_schema: {
            type: 'object',
            properties: {
              verdict: { type: 'string', enum: ['pass', 'fail', 'unclear'] },
              confidence: {
                type: 'number',
                description: 'How sure you are, 0 to 1. Be honest; a low number routes this to a human, which is fine.',
              },
              rationale: {
                type: 'string',
                description: 'One or two plain sentences for the moderator, concrete about what you see.',
              },
              escalation_reason: {
                type: 'string',
                description: "Why a human is needed. Empty string unless the verdict is 'unclear'.",
              },
            },
            required: ['verdict', 'confidence', 'rationale', 'escalation_reason'],
            additionalProperties: false,
          },
        },
      ],
      messages: [{ role: 'user', content: this.buildContent(request) }],
    });

    // A safety decline is not a verdict about the proof. Escalating is the
    // only honest outcome: the agent genuinely did not judge the submission.
    if (response.stop_reason === 'refusal') {
      this.logger.warn(
        { category: response.stop_details?.category ?? null },
        'Proof analysis declined by safety classifier',
      );
      return {
        verdict: 'unclear',
        confidence: null,
        rationale: '',
        escalationReason: 'The agent declined to analyse this proof. A human decision is required.',
        model: response.model,
        inputTokens: response.usage.input_tokens,
        outputTokens: response.usage.output_tokens,
      };
    }

    const call = response.content.find(
      (block) => block.type === 'tool_use' && block.name === 'record_verdict',
    );
    if (!call || call.type !== 'tool_use') {
      // Escalate rather than throw. A missing tool call is not a transient
      // failure worth retrying, and it is not a verdict either.
      this.logger.warn({ stopReason: response.stop_reason }, 'Proof analysis returned no verdict');
      return {
        verdict: 'unclear',
        confidence: null,
        rationale: '',
        escalationReason: 'The agent returned no verdict. A human decision is required.',
        model: response.model,
        inputTokens: response.usage.input_tokens,
        outputTokens: response.usage.output_tokens,
      };
    }

    // `strict: true` guarantees the shape, but the values still come from a
    // model: clamp the number and bound the strings before they reach a
    // column with a CHECK constraint on them.
    const input = call.input as {
      verdict: ProofVerdict;
      confidence: number;
      rationale: string;
      escalation_reason: string;
    };
    return {
      verdict: input.verdict,
      confidence: Number.isFinite(input.confidence)
        ? Math.min(1, Math.max(0, input.confidence))
        : null,
      rationale: input.rationale.trim().slice(0, 4000),
      escalationReason: input.escalation_reason.trim().slice(0, 500),
      model: response.model,
      inputTokens: response.usage.input_tokens,
      outputTokens: response.usage.output_tokens,
    };
  }

  private buildContent(request: ProofAnalysisRequest): Anthropic.ContentBlockParam[] {
    // Images first, then the text that refers to them — the model reads the
    // task after it has seen what it is judging.
    const blocks: Anthropic.ContentBlockParam[] = request.images.map((image) => ({
      type: 'image' as const,
      source: { type: 'base64' as const, media_type: image.mediaType, data: image.base64 },
    }));

    const lines = [
      `Quest: ${request.questTitle}`,
      `Category: ${request.questCategory}`,
      `What it asked for: ${request.questDescription}`,
      request.caption
        ? `The user's caption (their claim, not evidence): ${request.caption}`
        : 'The user wrote no caption.',
      `Images you can see: ${request.images.length}`,
    ];

    if (request.unreadableMedia.length > 0) {
      lines.push(
        `Part of this proof could not be examined: ${request.unreadableMedia.join(', ')}. ` +
          'Judge only what you can see, and escalate if the unexamined part is what the quest turns on.',
      );
    }

    lines.push(this.describeSignals(request));
    lines.push('Call record_verdict once.');

    blocks.push({ type: 'text', text: lines.join('\n') });
    return blocks;
  }

  /// States plainly that presence is unproven when it is.
  ///
  /// Saying nothing about the signals would let the model assume the image is
  /// the whole story, which is exactly the inference #53's absence forbids.
  private describeSignals(request: ProofAnalysisRequest): string {
    const { locationVerified, locationRetrieved, geofenceVerified } = request.signals;
    if (locationVerified === undefined && locationRetrieved === undefined && geofenceVerified === undefined) {
      return 'Network location signals: NOT AVAILABLE for this submission. You cannot conclude anything about where the user was. If the quest depends on physical presence, return "unclear".';
    }
    const describe = (value: boolean | undefined): string =>
      value === undefined ? 'not available' : value ? 'confirmed' : 'NOT confirmed';
    return [
      'Network location signals:',
      `- location verified: ${describe(locationVerified)}`,
      `- location retrieved: ${describe(locationRetrieved)}`,
      `- inside the quest's geofence: ${describe(geofenceVerified)}`,
      'Treat "not available" as absence of information, never as a failed check.',
    ].join('\n');
  }
}
