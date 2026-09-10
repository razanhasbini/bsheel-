import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
import { OpenAiAgentRunner } from '../infrastructure/openai/openai-agent.runner.js';
import { buildXpRecommendationAgent } from '../infrastructure/openai/xp-recommendation.agent.js';
import { XpRecommendationSchema, type AgentContext, type XpRecommendation } from '../domain/agent.schemas.js';
import { clampXp, deterministicXp, type PolicyBounds, type RewardShapeInputs } from '../domain/verification-policy.js';

export interface XpRequest {
  readonly context: AgentContext;
  /** Measured at assignment time (user_quests.assignment_distance_meters); null when unknown. */
  readonly distanceMeters: number | null;
  readonly bounds: PolicyBounds;
}

/**
 * How much XP this particular completion is worth to this particular
 * user. Keyed off how far they actually had to travel, so two people who
 * complete the same quest can be rewarded differently. The deterministic
 * curve always produces an answer; the model adjusts around it and the
 * result is clamped to the 5–100 policy range before anything is stored.
 */
@Injectable()
export class XpRecommendationService {
  private readonly logger = new Logger(XpRecommendationService.name);

  constructor(
    private readonly config: ConfigService<Environment, true>,
    private readonly runner: OpenAiAgentRunner,
  ) {}

  async recommend(request: XpRequest): Promise<XpRecommendation> {
    const shape: RewardShapeInputs = {
      distanceMeters: request.distanceMeters,
      hasDestination: Boolean(request.context.quest.destination),
      category: request.context.quest.category,
      difficulty: request.context.quest.difficulty,
      participantCount: request.context.collaboration.participantCount,
    };
    const ruleBasedXp = deterministicXp(shape, request.bounds);
    const fallback: XpRecommendation = {
      recommendedXp: ruleBasedXp,
      confidence: 0,
      factors: [],
      assumptions: ['Rule-based XP; the AI agent is disabled or unavailable.'],
    };
    if (!this.runner.isEnabled()) return fallback;

    const model = this.config.get('OPENAI_AGENT_MODEL', { infer: true });
    if (!model) return fallback;

    try {
      const agent = buildXpRecommendationAgent({ model });
      const raw = await this.runner.run<unknown>(
        agent,
        JSON.stringify({
          quest: {
            title: request.context.quest.title,
            description: request.context.quest.description,
            category: request.context.quest.category,
            difficulty: request.context.quest.difficulty,
            hasDestination: Boolean(request.context.quest.destination),
            destinationCountry: request.context.quest.destination?.countryCode ?? null,
            adminBaseXp: request.context.quest.baseXp,
          },
          user: {
            distanceToDestinationMeters: request.distanceMeters,
            distanceKnown: request.distanceMeters !== null,
            collaborationMode: request.context.collaboration.mode,
            participantCount: request.context.collaboration.participantCount,
          },
          policy: {
            minXp: request.bounds.minXp,
            maxXp: request.bounds.maxXp,
            ruleBasedXp,
          },
        }),
      );
      const parsed = XpRecommendationSchema.safeParse(raw);
      if (!parsed.success) {
        this.logger.warn({ issues: parsed.error.issues }, 'XP model output failed schema validation');
        return fallback;
      }
      return { ...parsed.data, recommendedXp: clampXp(parsed.data.recommendedXp, request.bounds) };
    } catch (error) {
      this.logger.warn({ errorName: error instanceof Error ? error.name : 'UnknownError' }, 'XP recommendation failed; using the rule-based value');
      return fallback;
    }
  }
}
