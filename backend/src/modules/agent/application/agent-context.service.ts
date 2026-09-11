import { randomUUID } from 'node:crypto';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
import { AgentContextRepository, type SubmissionContextRow, type SubmissionMediaRow } from '../infrastructure/agent-context.repository.js';
import { AgentContextSchema, type AgentContext } from '../domain/agent.schemas.js';
import { resolvePolicyBounds, type PolicyLimits } from '../domain/verification-policy.js';

const ACCEPTED_MEDIA = ['image', 'video', 'mixed'] as const;

@Injectable()
export class AgentContextService {
  constructor(
    private readonly repository: AgentContextRepository,
    private readonly config: ConfigService<Environment, true>,
  ) {}

  async forSubmissionVerification(submissionId: string): Promise<AgentContext | null> {
    const row = await this.repository.findSubmissionContext(submissionId);
    if (!row) return null;
    return AgentContextSchema.parse(this.toContext(row));
  }

  mediaForSubmission(submissionId: string): Promise<readonly SubmissionMediaRow[]> {
    return this.repository.findSubmissionMedia(submissionId);
  }

  phoneNumberForUser(userId: string): Promise<string | null> {
    return this.repository.findUserPhoneNumber(userId);
  }

  private toContext(row: SubmissionContextRow): AgentContext {
    const bounds = resolvePolicyBounds({ baseXp: row.base_xp, defaultDurationHours: row.default_duration_hours }, this.policyLimits());
    const requirements = this.parseRequirements(row.verification_requirements);
    const destination =
      row.place_id !== null && row.latitude !== null && row.longitude !== null
        ? {
            placeId: row.place_id,
            countryCode: row.country_code ?? 'XX',
            coordinates: { latitude: row.latitude, longitude: row.longitude },
            radiusMeters: row.radius_m ?? 250,
            requiresVerification: row.requires_verification ?? true,
          }
        : undefined;

    return {
      runId: randomUUID(),
      task: 'submission_verification',
      user: { id: row.user_id },
      quest: {
        id: row.quest_id,
        title: row.title,
        description: row.description,
        category: row.category,
        difficulty: row.difficulty,
        baseXp: row.base_xp,
        defaultDurationHours: row.default_duration_hours,
        stageCount: 1,
        verification: {
          verifiability: row.verifiability,
          evidenceRubric: row.evidence_rubric,
          mayAutoApprove: row.may_auto_approve,
          mayAutoReject: row.may_auto_reject,
        },
        ...(requirements ? { requirements } : {}),
        ...(destination ? { destination } : {}),
      },
      assignment: {
        userQuestId: row.user_quest_id,
        assignedAt: row.assigned_at.toISOString(),
        expiresAt: row.expires_at.toISOString(),
        ...(row.submitted_at ? { submittedAt: row.submitted_at.toISOString() } : {}),
      },
      submission: {
        id: row.submission_id,
        mediaType: row.media_type as 'image' | 'video' | 'mixed',
        mediaCount: Math.min(Math.max(row.media_count, 1), 10),
        caption: row.caption,
      },
      collaboration: {
        mode: row.collab_mode === 'with' || row.collab_mode === 'versus' ? row.collab_mode : 'solo',
        participantCount: Math.max(1, row.participant_count),
      },
      policy: bounds,
    };
  }

  /// Defensive parsing: quests.verification_requirements is hand-authored
  /// admin content, not DTO-validated on write (#48 gives staff a proper
  /// editor later). Anything malformed here degrades to "no requirement",
  /// never throws and never blocks the run.
  private parseRequirements(raw: Record<string, unknown> | null): AgentContext['quest']['requirements'] {
    if (!raw) return undefined;
    const strings = (value: unknown): string[] => (Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string') : []);
    const acceptedMedia = strings(raw.acceptedMedia).filter((value): value is (typeof ACCEPTED_MEDIA)[number] =>
      (ACCEPTED_MEDIA as readonly string[]).includes(value),
    );
    return {
      actions: strings(raw.actions),
      objects: strings(raw.objects),
      requiredItems: strings(raw.requiredItems),
      requiredPeople: typeof raw.requiredPeople === 'number' && raw.requiredPeople > 0 ? Math.floor(raw.requiredPeople) : 1,
      acceptedMedia: acceptedMedia.length > 0 ? acceptedMedia : [...ACCEPTED_MEDIA],
    };
  }

  policyLimits(): PolicyLimits {
    return {
      globalMinDurationMinutes: this.config.get('AGENT_QUEST_TIME_MIN_MINUTES', { infer: true }),
      globalMaxDurationMinutes: this.config.get('AGENT_QUEST_TIME_MAX_MINUTES', { infer: true }),
      globalMinXp: this.config.get('AGENT_XP_MIN', { infer: true }),
      globalMaxXp: this.config.get('AGENT_XP_MAX', { infer: true }),
      approveThreshold: this.config.get('AGENT_APPROVE_CONFIDENCE_THRESHOLD', { infer: true }),
      rejectThreshold: this.config.get('AGENT_REJECT_CONFIDENCE_THRESHOLD', { infer: true }),
    };
  }
}
