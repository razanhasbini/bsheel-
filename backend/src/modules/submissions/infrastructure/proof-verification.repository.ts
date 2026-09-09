import { Injectable } from '@nestjs/common';
import { DatabaseService, type DatabaseTransaction } from '../../../infrastructure/database/database.service.js';
import type { LocationSignals, ProofAnalysis } from '../domain/proof-verification.types.js';

/// What the analyzer needs to judge one submission, gathered in a single read.
export interface VerificationSubject {
  readonly submission_id: string;
  readonly user_id: string;
  readonly caption: string | null;
  readonly media_url: string;
  readonly quest_title: string;
  readonly quest_description: string;
  readonly quest_category: string;
  readonly attempts: number;
  /// Current review state. A submission a moderator already decided is not
  /// worth spending a vision call on.
  readonly status: string;
}

@Injectable()
export class ProofVerificationRepository {
  constructor(private readonly database: DatabaseService) {}

  /// Records that a submission is awaiting analysis.
  ///
  /// `ON CONFLICT DO NOTHING` makes this safe to call from an at-least-once
  /// consumer: a redelivered `submission.created` must not reset a verdict
  /// that has already been produced.
  async enqueue(submissionId: string, transaction?: DatabaseTransaction): Promise<void> {
    await this.database.query(
      `INSERT INTO submission_verifications (submission_id) VALUES ($1)
       ON CONFLICT (submission_id) DO NOTHING`,
      [submissionId],
      transaction,
    );
  }

  /// Claims one submission for analysis, or returns null.
  ///
  /// The claim is the `attempts` increment, committed before the vision call
  /// is made rather than after. That ordering is deliberate: a submission
  /// whose analysis crashes the worker every time must eventually stop being
  /// retried, and an attempt counter that only advances on a clean finish
  /// would loop forever.
  async claim(submissionId: string, maxAttempts: number): Promise<VerificationSubject | null> {
    const result = await this.database.query<VerificationSubject>(
      `WITH claimed AS (
         UPDATE submission_verifications v
         SET attempts = v.attempts + 1, state = 'queued'
         WHERE v.submission_id = $1
           AND v.state IN ('queued', 'failed')
           AND v.attempts < $2
         RETURNING v.submission_id, v.attempts
       )
       SELECT c.submission_id, c.attempts, s.user_id, s.caption, s.media_url,
              s.status::text AS status,
              q.title AS quest_title, q.description AS quest_description,
              q.category::text AS quest_category
       FROM claimed c
       JOIN submissions s ON s.id = c.submission_id
       JOIN user_quests uq ON uq.id = s.user_quest_id
       JOIN quests q ON q.id = uq.quest_id`,
      [submissionId, maxAttempts],
    );
    return result.rows[0] ?? null;
  }

  /// Stores a verdict and, when it is an escalation, alerts the committee.
  ///
  /// The notification and its outbox row are inserted in the same transaction
  /// as the verdict, so an escalation cannot be recorded without the alert
  /// that makes anyone look at it — the invariant CLAUDE.md states for every
  /// state change that emits an event.
  async complete(
    submissionId: string,
    analysis: ProofAnalysis,
    signals: LocationSignals,
    durationMs: number,
  ): Promise<void> {
    await this.database.transaction(async (transaction) => {
      await transaction.query(
        `UPDATE submission_verifications
         SET state = 'complete', verdict = $2::proof_verdict, confidence = $3,
             rationale = $4, escalation_reason = $5, model = $6,
             location_verified = $7, location_retrieved = $8, geofence_verified = $9,
             input_tokens = $10, output_tokens = $11, duration_ms = $12,
             last_error = NULL, completed_at = now()
         WHERE submission_id = $1`,
        [
          submissionId,
          analysis.verdict,
          analysis.confidence,
          analysis.rationale,
          analysis.escalationReason,
          analysis.model,
          signals.locationVerified ?? null,
          signals.locationRetrieved ?? null,
          signals.geofenceVerified ?? null,
          analysis.inputTokens,
          analysis.outputTokens,
          durationMs,
        ],
      );
      if (analysis.verdict === 'unclear') {
        await this.alertCommittee(submissionId, analysis.escalationReason, transaction);
      }
    });
  }

  /// Marks an attempt as failed so the sweep can retry it.
  ///
  /// Kept out of the verdict path: a provider timeout is not an opinion about
  /// the proof, and must never be stored as one.
  async fail(submissionId: string, error: string): Promise<void> {
    await this.database.query(
      `UPDATE submission_verifications
       SET state = 'failed', last_error = $2, completed_at = NULL
       WHERE submission_id = $1`,
      [submissionId, error.slice(0, 2000)],
    );
  }

  /// Records that the submission was never analysed, and why.
  ///
  /// 'skipped' is distinct from 'failed' because it is terminal — the feature
  /// is off, or the moderator already decided. Retrying either is pointless.
  async skip(submissionId: string, reason: string): Promise<void> {
    await this.database.query(
      `UPDATE submission_verifications
       SET state = 'skipped', last_error = $2, completed_at = now()
       WHERE submission_id = $1`,
      [submissionId, reason.slice(0, 2000)],
    );
  }

  /// Submissions the agent has not finished with, oldest first.
  ///
  /// Only those still awaiting a moderator: once a human has decided, an
  /// unanalysed submission needs no catch-up. Backed by
  /// submission_verifications_pending_idx.
  async pending(limit: number, maxAttempts: number): Promise<readonly string[]> {
    const result = await this.database.query<{ submission_id: string }>(
      `SELECT v.submission_id FROM submission_verifications v
       JOIN submissions s ON s.id = v.submission_id
       WHERE v.state IN ('queued', 'failed') AND v.attempts < $2
         AND s.status = 'pending' AND s.deleted_at IS NULL
       ORDER BY v.queued_at
       LIMIT $1`,
      [limit, maxAttempts],
    );
    return result.rows.map((row) => row.submission_id);
  }

  /// The committee's "unclear" section (#47).
  ///
  /// Unresolved escalations on submissions still awaiting review, oldest
  /// first — the same ordering as the main review queue, so a moderator
  /// working both sees a consistent sense of what is oldest. Carries enough
  /// context to trade off which to open first without a second request.
  /// Backed by submission_verifications_unclear_idx.
  async unclearQueue(limit: number, offset: number): Promise<readonly Record<string, unknown>[]> {
    const result = await this.database.query(
      `SELECT v.submission_id, v.escalation_reason, v.rationale, v.confidence,
              v.model, v.queued_at, v.completed_at,
              v.location_verified, v.location_retrieved, v.geofence_verified,
              s.user_id, s.media_type::text AS media_type, s.caption,
              s.submitted_at, s.appealed,
              p.username::text, p.display_name, p.avatar_url,
              q.title AS quest_title, q.category::text AS quest_category
       FROM submission_verifications v
       JOIN submissions s ON s.id = v.submission_id
       JOIN profiles p ON p.id = s.user_id
       JOIN user_quests uq ON uq.id = s.user_quest_id
       JOIN quests q ON q.id = uq.quest_id
       WHERE v.state = 'complete' AND v.verdict = 'unclear' AND v.resolved_at IS NULL
         AND s.status = 'pending' AND s.deleted_at IS NULL
       ORDER BY s.submitted_at ASC, s.id
       LIMIT $1 OFFSET $2`,
      [Math.min(Math.max(limit, 1), 100), Math.max(offset, 0)],
    );
    return result.rows;
  }

  /// How many escalations are waiting, for the sidebar badge.
  async unclearCount(): Promise<number> {
    const result = await this.database.query<{ count: number }>(
      `SELECT count(*)::int AS count
       FROM submission_verifications v
       JOIN submissions s ON s.id = v.submission_id
       WHERE v.state = 'complete' AND v.verdict = 'unclear' AND v.resolved_at IS NULL
         AND s.status = 'pending' AND s.deleted_at IS NULL`,
    );
    return result.rows[0].count;
  }

  /// Current, unexpired CAMARA evidence for the place this submission's quest
  /// is tied to, or null when there is none (#53).
  ///
  /// Null is the normal answer today: `map_location_evidence` has no writer
  /// until the adapter exists, and a location-independent quest has no place
  /// to check against at all. `expires_at > now()` is what stops a stale
  /// check counting forever.
  async evidenceFor(submissionId: string): Promise<
    { location_verified: boolean; location_retrieved: boolean; geofence_verified: boolean } | null
  > {
    const result = await this.database.query<{
      location_verified: boolean;
      location_retrieved: boolean;
      geofence_verified: boolean;
    }>(
      `SELECT e.location_verified, e.location_retrieved, e.geofence_verified
       FROM submissions s
       JOIN user_quests uq ON uq.id = s.user_quest_id
       JOIN quest_destinations d ON d.quest_id = uq.quest_id
       JOIN map_location_evidence e
              ON e.user_id = s.user_id
             AND e.place_id = d.place_id
             AND e.expires_at > now()
       WHERE s.id = $1
       ORDER BY e.verified_at DESC
       LIMIT 1`,
      [submissionId],
    );
    return result.rows[0] ?? null;
  }

  /// Clears an escalation once a human has dealt with it.
  ///
  /// Called from the review path, so approving or rejecting a submission
  /// drains it from the unclear queue without a second admin action.
  async resolve(submissionId: string, actorId: string | null, transaction?: DatabaseTransaction): Promise<void> {
    await this.database.query(
      `UPDATE submission_verifications
       SET resolved_by = $2, resolved_at = now()
       WHERE submission_id = $1 AND resolved_at IS NULL`,
      [submissionId, actorId],
      transaction,
    );
  }

  /// Alerts every admin that a submission needs a human decision.
  ///
  /// One statement inserting the notifications and their outbox rows
  /// together, matching how submissions.repository notifies admins of a new
  /// submission.
  private async alertCommittee(
    submissionId: string,
    escalationReason: string,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    await transaction.query(
      `WITH inserted AS (
         INSERT INTO notifications (user_id, title, body, type, reference_id)
         SELECT user_id, $1, $2, 'proof_unclear', $3 FROM admins
         RETURNING id, user_id
       )
       INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       SELECT 'notification', id, 'notification.created',
         jsonb_build_object('notificationId', id, 'userId', user_id) FROM inserted`,
      [
        'Proof needs your eyes. 🔍',
        escalationReason || 'The agent could not decide on this proof.',
        submissionId,
      ],
    );
  }
}
