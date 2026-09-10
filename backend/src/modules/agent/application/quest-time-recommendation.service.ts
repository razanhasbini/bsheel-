import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
import { OpenAiAgentRunner } from '../infrastructure/openai/openai-agent.runner.js';
import { buildQuestTimeAgent } from '../infrastructure/openai/quest-time.agent.js';
import { QuestTimeRecommendationSchema, type QuestTimeRecommendation } from '../domain/agent.schemas.js';
import { clampDurationMinutes, type PolicyBounds } from '../domain/verification-policy.js';
import type { AssignmentContextRow } from '../infrastructure/agent-context.repository.js';

export interface AssignmentTimeRequest {
  readonly assignment: AssignmentContextRow;
  readonly distanceMeters: number | null;
  readonly bounds: PolicyBounds;
  /** The rule-based answer; the anchor the model is asked to reason around. */
  readonly deterministicMinutes: number;
}

/**
 * How long this particular user gets for this particular quest. The
 * deterministic curve in verification-policy.ts always produces an answer;
 * the model only ever adjusts around it, and whatever it returns is
 * clamped back into the 4-hour / 2-week policy range before it is used.
 */
@Injectable()
export class QuestTimeRecommendationService {
  private readonly logger = new Logger(QuestTimeRecommendationService.name);

  constructor(
    private readonly config: ConfigService<Environment, true>,
    private readonly runner: OpenAiAgentRunner,
  ) {}

  async recommendForAssignment(request: AssignmentTimeRequest): Promise<QuestTimeRecommendation> {
    const fallback: QuestTimeRecommendation = {
      recommendedMinutes: request.deterministicMinutes,
      confidence: 0,
      factors: [],
      assumptions: ['Rule-based timer; the AI agent is disabled or unavailable.'],
    };
    if (!this.runner.isEnabled()) return fallback;

    const model = this.config.get('OPENAI_AGENT_MODEL', { infer: true });
    if (!model) return fallback;

    try {
      const agent = buildQuestTimeAgent({ model });
      const raw = await this.runner.run<unknown>(agent, JSON.stringify(this.prompt(request)));
      const parsed = QuestTimeRecommendationSchema.safeParse(raw);
      if (!parsed.success) {
        this.logger.warn({ issues: parsed.error.issues }, 'Quest-time model output failed schema validation');
        return fallback;
      }
      return {
        ...parsed.data,
        recommendedMinutes: clampDurationMinutes(parsed.data.recommendedMinutes, request.bounds),
      };
    } catch (error) {
      this.logger.warn({ errorName: error instanceof Error ? error.name : 'UnknownError' }, 'Quest-time recommendation failed; using the rule-based timer');
      return fallback;
    }
  }

  /// Deliberately carries no phone number or other identifier — just the
  /// quest, the measured distance, and the range the answer must land in.
  private prompt(request: AssignmentTimeRequest): Record<string, unknown> {
    const { assignment } = request;
    return {
      quest: {
        title: assignment.title,
        description: assignment.description,
        category: assignment.category,
        difficulty: assignment.difficulty,
        hasDestination: assignment.place_id !== null,
        destinationCountry: assignment.country_code,
        adminDefaultDurationHours: assignment.default_duration_hours,
      },
      user: {
        distanceToDestinationMeters: request.distanceMeters,
        distanceKnown: request.distanceMeters !== null,
      },
      policy: {
        minMinutes: request.bounds.minDurationMinutes,
        maxMinutes: request.bounds.maxDurationMinutes,
        ruleBasedMinutes: request.deterministicMinutes,
      },
    };
  }
}
