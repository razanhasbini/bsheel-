import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';

export interface SubmissionContextRow {
  readonly submission_id: string;
  readonly user_id: string;
  readonly media_type: string;
  readonly media_count: number;
  readonly caption: string | null;
  readonly user_quest_id: string;
  readonly assigned_at: Date;
  readonly expires_at: Date;
  readonly submitted_at: Date | null;
  readonly quest_id: string;
  readonly title: string;
  readonly description: string;
  readonly category: string;
  readonly difficulty: string;
  readonly base_xp: number;
  readonly default_duration_hours: number;
  readonly verification_requirements: Record<string, unknown> | null;
  readonly verifiability: 'content' | 'provenance_only' | 'none';
  readonly evidence_rubric: string;
  readonly may_auto_approve: boolean;
  readonly may_auto_reject: boolean;
  readonly place_id: string | null;
  readonly requires_verification: boolean | null;
  readonly country_code: string | null;
  readonly latitude: number | null;
  readonly longitude: number | null;
  readonly radius_m: number | null;
  readonly collab_mode: string | null;
  readonly participant_count: number;
}

export interface SubmissionMediaRow {
  readonly media_object_id: string;
  readonly object_key: string;
  readonly content_type: string;
}

export interface AssignmentContextRow {
  readonly user_quest_id: string;
  readonly user_id: string;
  readonly assigned_at: Date;
  readonly expires_at: Date;
  readonly assignment_distance_meters: number | null;
  readonly quest_id: string;
  readonly title: string;
  readonly description: string;
  readonly category: string;
  readonly difficulty: string;
  readonly base_xp: number;
  readonly default_duration_hours: number;
  readonly verification_requirements: Record<string, unknown> | null;
  readonly verifiability: 'content' | 'provenance_only' | 'none';
  readonly evidence_rubric: string;
  readonly may_auto_approve: boolean;
  readonly may_auto_reject: boolean;
  readonly place_id: string | null;
  readonly requires_verification: boolean | null;
  readonly country_code: string | null;
  readonly latitude: number | null;
  readonly longitude: number | null;
  readonly radius_m: number | null;
  readonly phone_number: string | null;
}

/**
 * Read-only joins across submissions/quests/map/collab for the agent's own
 * use. Deliberately a fresh query here rather than reaching into another
 * domain's repository (repositories never call another domain's
 * repository) — this mirrors how submissions.repository.ts already joins
 * quests/profiles/collab directly for its own read paths.
 */
@Injectable()
export class AgentContextRepository {
  constructor(private readonly database: DatabaseService) {}

  async findSubmissionContext(submissionId: string): Promise<SubmissionContextRow | null> {
    const result = await this.database.query<SubmissionContextRow>(
      `SELECT
         s.id AS submission_id, s.user_id, s.media_type::text, s.caption,
         COALESCE((SELECT count(*) FROM media_submission_links l WHERE l.submission_id = s.id), 1)::int AS media_count,
         uq.id AS user_quest_id, uq.assigned_at, uq.expires_at, s.submitted_at,
         q.id AS quest_id, q.title, q.description, q.category, q.difficulty,
         q.xp_reward AS base_xp, q.duration_hours AS default_duration_hours,
         q.verification_requirements,
         vc.verifiability, vc.evidence_rubric, vc.may_auto_approve, vc.may_auto_reject,
         qd.place_id, qd.requires_verification,
         mp.country_code, mp.latitude, mp.longitude, mp.radius_m,
         g.mode::text AS collab_mode,
         COALESCE(member_count.count, 1)::int AS participant_count
       FROM submissions s
       JOIN user_quests uq ON uq.id = s.user_quest_id
       JOIN quests q ON q.id = uq.quest_id
       -- The one resolved answer to "what can proof establish here, and what
       -- may the agent do about it" (#47, migration 0034). Read through the
       -- view so this worker cannot disagree with the vision cascade or the
       -- admin surface about a quest's contract. An inner join is safe: the
       -- view has a row per quest and COALESCEs an unknown category down to
       -- none/no-authority rather than dropping it.
       JOIN quest_verification_contract vc ON vc.quest_id = q.id
       LEFT JOIN quest_destinations qd ON qd.quest_id = q.id
       LEFT JOIN map_places mp ON mp.id = qd.place_id
       LEFT JOIN collab_group_members gm ON gm.user_quest_id = uq.id
       LEFT JOIN collab_groups g ON g.id = gm.group_id
       LEFT JOIN LATERAL (
         SELECT count(*) AS count FROM collab_group_members member WHERE member.group_id = gm.group_id
       ) member_count ON gm.group_id IS NOT NULL
       WHERE s.id = $1
         AND s.status = 'pending'
         AND s.appealed = false
         AND s.visibility <> 'deleted'
         AND s.deleted_at IS NULL`,
      [submissionId],
    );
    return result.rows[0] ?? null;
  }

  /// Everything the post-assignment work needs: the quest, its destination
  /// (if any), the assignment window, and the user's verified phone number.
  /// Only returns rows still in 'assigned' state — a quest already
  /// submitted, expired or rerolled must not have its timer moved.
  async findAssignmentContext(userQuestId: string): Promise<AssignmentContextRow | null> {
    const result = await this.database.query<AssignmentContextRow>(
      `SELECT uq.id AS user_quest_id, uq.user_id, uq.assigned_at, uq.expires_at,
              uq.assignment_distance_meters,
              q.id AS quest_id, q.title, q.description, q.category, q.difficulty,
              q.xp_reward AS base_xp, q.duration_hours AS default_duration_hours,
              q.verification_requirements,
              vc.verifiability, vc.evidence_rubric, vc.may_auto_approve, vc.may_auto_reject,
              qd.place_id, qd.requires_verification,
              mp.country_code, mp.latitude, mp.longitude, mp.radius_m,
              u.phone_number
       FROM user_quests uq
       JOIN quests q ON q.id = uq.quest_id
       JOIN quest_verification_contract vc ON vc.quest_id = q.id
       JOIN users u ON u.id = uq.user_id
       LEFT JOIN quest_destinations qd ON qd.quest_id = q.id
       LEFT JOIN map_places mp ON mp.id = qd.place_id
       WHERE uq.id = $1 AND uq.status = 'assigned'`,
      [userQuestId],
    );
    return result.rows[0] ?? null;
  }

  /// Moves the timer, but only while the quest is still running and
  /// untouched — never retroactively on something already submitted,
  /// expired or rerolled.
  async applyRecommendedExpiry(userQuestId: string, expiresAt: Date): Promise<boolean> {
    const result = await this.database.query(
      `UPDATE user_quests SET expires_at = $2, version = version + 1
       WHERE id = $1 AND status = 'assigned'`,
      [userQuestId, expiresAt],
    );
    return (result.rowCount ?? 0) > 0;
  }

  /// Reads the distance measured at assignment time, whatever state the
  /// assignment has moved to since (findAssignmentContext deliberately
  /// only returns rows still running).
  async findAssignmentDistance(userQuestId: string): Promise<number | null> {
    const result = await this.database.query<{ assignment_distance_meters: number | null }>(
      'SELECT assignment_distance_meters FROM user_quests WHERE id = $1',
      [userQuestId],
    );
    return result.rows[0]?.assignment_distance_meters ?? null;
  }

  async storeAssignmentDistance(userQuestId: string, distanceMeters: number): Promise<void> {
    await this.database.query(
      'UPDATE user_quests SET assignment_distance_meters = $2 WHERE id = $1',
      [userQuestId, distanceMeters],
    );
  }

  async storeRecommendedXp(submissionId: string, recommendedXp: number): Promise<void> {
    await this.database.query(
      'UPDATE submissions SET recommended_xp = $2 WHERE id = $1',
      [submissionId, recommendedXp],
    );
  }

  /** E.164 or null — the CAMARA-verified device identifier (issue #1). */
  async findUserPhoneNumber(userId: string): Promise<string | null> {
    const result = await this.database.query<{ phone_number: string | null }>(
      'SELECT phone_number FROM users WHERE id = $1',
      [userId],
    );
    return result.rows[0]?.phone_number ?? null;
  }

  async findSubmissionMedia(submissionId: string): Promise<readonly SubmissionMediaRow[]> {
    const result = await this.database.query<SubmissionMediaRow>(
      `SELECT mo.id AS media_object_id, mo.object_key, mo.content_type
       FROM media_submission_links l JOIN media_objects mo ON mo.id = l.media_object_id
       WHERE l.submission_id = $1 ORDER BY mo.id`,
      [submissionId],
    );
    return result.rows;
  }
}
