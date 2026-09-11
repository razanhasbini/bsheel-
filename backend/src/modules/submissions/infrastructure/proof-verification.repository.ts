import { Injectable } from '@nestjs/common';
import { DatabaseService, type DatabaseTransaction } from '../../../infrastructure/database/database.service.js';
import type {
  LocationSignals,
  ProofAnalysis,
  ProofObservation,
  ProofVerdict,
  VerificationState,
} from '../domain/proof-verification.types.js';

const OBSERVATION_KINDS: readonly ProofObservation['kind'][] = ['action', 'object', 'landmark', 'location_cue'];

/// Reads back what `complete()` wrote into content_evidence.
///
/// Defensive because the column is jsonb: a row written by an older build, or
/// by a hand-run fixture, must degrade to "no observations" rather than
/// throwing inside a queue worker.
function parseObservations(raw: unknown): readonly ProofObservation[] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((item) => {
    if (typeof item !== 'object' || item === null) return [];
    const record = item as Record<string, unknown>;
    if (typeof record.label !== 'string' || record.label.length === 0) return [];
    const kind = (OBSERVATION_KINDS as readonly string[]).includes(String(record.kind))
      ? (record.kind as ProofObservation['kind'])
      : ('object' as const);
    const confidence = typeof record.confidence === 'number' && Number.isFinite(record.confidence)
      ? Math.min(1, Math.max(0, record.confidence))
      : 0;
    return [{ kind, label: record.label, present: record.present === true, confidence }];
  });
}

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
  ///
  /// `claimed_at` is what makes this an actual lease rather than a label.
  /// Without it the state a row sits in while being analysed was
  /// indistinguishable from the state it sits in while waiting, so a second
  /// caller's UPDATE blocked on the row lock, read a row still marked
  /// 'queued', and claimed it too — two vision calls on the same bytes, at
  /// the top of a ladder whose rungs differ ~50x in price. Two callers is
  /// the normal case: the submission.created consumer runs the pass inline
  /// and the sweep walks everything still queued or failed every 15 minutes.
  ///
  /// An expired claim is taken rather than respected, which is what stops a
  /// worker killed mid-analysis from stranding the submission.
  async claim(
    submissionId: string,
    maxAttempts: number,
    leaseSeconds: number,
  ): Promise<VerificationSubject | null> {
    const result = await this.database.query<VerificationSubject>(
      `WITH claimed AS (
         UPDATE submission_verifications v
         SET attempts = v.attempts + 1, state = 'queued', claimed_at = now()
         WHERE v.submission_id = $1
           AND v.state IN ('queued', 'failed')
           AND v.attempts < $2
           AND (v.claimed_at IS NULL
                OR v.claimed_at < now() - make_interval(secs => $3))
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
      [submissionId, maxAttempts, leaseSeconds],
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
    /// Which rung is accountable, whether the decision was carried out, and
    /// which provider produced it. `acted` is false in shadow mode, which is
    /// what makes the row usable as eval data: the agent did not influence
    /// the human decision it is being scored against.
    provenance: { stage: string; acted: boolean; provider: string },
  ): Promise<void> {
    await this.database.transaction(async (transaction) => {
      await transaction.query(
        `UPDATE submission_verifications
         SET state = 'complete', verdict = $2::proof_verdict, confidence = $3,
             rationale = $4, escalation_reason = $5, model = $6,
             location_verified = $7, location_retrieved = $8, geofence_verified = $9,
             input_tokens = $10, output_tokens = $11, duration_ms = $12,
             stage = $13, acted = $14,
             relevance = $15, content_evidence = $16::jsonb,
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
          provenance.stage,
          provenance.acted,
          analysis.relevance,
          // Null rather than an empty object when nothing was observed, so
          // "no vision pass ran" stays distinguishable from "it ran and saw
          // nothing" — the same distinction CvEvidence.status exists to make.
          analysis.observations.length > 0
            ? JSON.stringify({ observations: analysis.observations.map((item) => ({ ...item })) })
            : null,
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
      // Never downgrades a verdict that was already reached.
      //
      // `submission_verifications_verdict_state_check` requires a
      // non-complete row to carry no verdict, so this UPDATE on a completed
      // row raised 23503 — and it is called from the catch block of
      // verify(), which is itself awaited inline by the shared
      // domain-events processor. A late failure *after* the verdict was
      // stored therefore threw out of the error handler and failed the whole
      // domain event, retrying the notification side effects with it. The
      // guard is also the right semantics on its own: a verdict that was
      // recorded is not un-recorded by a later problem.
      `UPDATE submission_verifications
       SET state = 'failed', last_error = $2, completed_at = NULL
       WHERE submission_id = $1 AND state <> 'complete'`,
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


  /// Submissions a **person** decided that carry no verdict, newest first.
  ///
  /// The eval set the agent's authority is supposed to be earned from, and
  /// the only way to have one without waiting. `proof:eval` scores stored
  /// verdicts against the human decision that followed, and `verify()`
  /// refuses to analyse anything already reviewed — correctly, since
  /// spending a vision call on a settled submission buys nothing
  /// operationally. So the ordinary path can only ever accumulate forward,
  /// and a database full of moderated history is unreadable to it.
  ///
  /// `reviewed_by IS NOT NULL` is what makes these rows ground truth: both
  /// automated deciders pass a null actor deliberately, so a reviewer id is
  /// proof a person decided. Newest first because moderation standards
  /// drift, and a precision number computed against last year's judgement
  /// describes last year's moderators.
  async decidedWithoutVerdict(limit: number): Promise<readonly string[]> {
    const result = await this.database.query<{ id: string }>(
      `SELECT s.id
       FROM submissions s
       LEFT JOIN submission_verifications v
              ON v.submission_id = s.id AND v.state = 'complete'
       WHERE s.status IN ('approved', 'rejected')
         AND s.reviewed_by IS NOT NULL
         AND s.reviewed_at IS NOT NULL
         AND s.deleted_at IS NULL
         AND s.visibility <> 'deleted'
         AND v.submission_id IS NULL
       ORDER BY s.reviewed_at DESC
       LIMIT $1`,
      [Math.min(Math.max(limit, 1), 500)],
    );
    return result.rows.map((row) => row.id);
  }

  /// The same read `claim()` performs, without claiming anything.
  ///
  /// No attempt increment and no state change, because a backfill is not
  /// work the pipeline owes anyone — it must not consume the retries a live
  /// submission would need, and it must be re-runnable.
  ///
  /// Returns null unless a person decided this submission. That guard is the
  /// point rather than caution: scoring a verdict against an automated
  /// decision measures the agent against itself.
  async evalSubject(submissionId: string): Promise<VerificationSubject | null> {
    const result = await this.database.query<VerificationSubject>(
      `SELECT s.id AS submission_id, 0 AS attempts, s.user_id, s.caption, s.media_url,
              s.status::text AS status,
              q.title AS quest_title, q.description AS quest_description,
              q.category::text AS quest_category
       FROM submissions s
       JOIN user_quests uq ON uq.id = s.user_quest_id
       JOIN quests q ON q.id = uq.quest_id
       WHERE s.id = $1
         AND s.status IN ('approved', 'rejected')
         AND s.reviewed_by IS NOT NULL
         AND s.deleted_at IS NULL`,
      [submissionId],
    );
    return result.rows[0] ?? null;
  }

  /// Stores a backfilled verdict, and alerts nobody.
  ///
  /// The difference from `complete()` is the whole reason this exists: that
  /// method alerts every admin when a verdict is 'unclear', in the same
  /// transaction, so an escalation cannot be recorded without the alert that
  /// makes someone look at it. Right for a live submission awaiting review.
  /// Catastrophic for a backfill — scoring a year of history would notify
  /// every admin about every old submission the agent found ambiguous, for
  /// submissions a human settled long ago.
  ///
  /// `acted` is hard-coded false rather than passed. A backfilled verdict is
  /// the cleanest eval data there is: the decision it is scored against was
  /// already made and recorded before this verdict existed, so it cannot
  /// have influenced it even in principle.
  async completeForEval(
    submissionId: string,
    analysis: ProofAnalysis,
    stage: string,
    verdict: ProofVerdict,
    durationMs: number,
  ): Promise<void> {
    await this.database.query(
      `INSERT INTO submission_verifications
         (submission_id, state, verdict, confidence, relevance, content_evidence,
          rationale, escalation_reason, model, input_tokens, output_tokens,
          duration_ms, stage, acted, completed_at)
       VALUES ($1, 'complete', $2::proof_verdict, $3, $4, $5::jsonb,
               $6, $7, $8, $9, $10, $11, $12, false, now())
       ON CONFLICT (submission_id) DO UPDATE
         SET state = 'complete', verdict = EXCLUDED.verdict,
             confidence = EXCLUDED.confidence, relevance = EXCLUDED.relevance,
             content_evidence = EXCLUDED.content_evidence,
             rationale = EXCLUDED.rationale,
             escalation_reason = EXCLUDED.escalation_reason,
             model = EXCLUDED.model, input_tokens = EXCLUDED.input_tokens,
             output_tokens = EXCLUDED.output_tokens, duration_ms = EXCLUDED.duration_ms,
             stage = EXCLUDED.stage, acted = false,
             last_error = NULL, completed_at = now()`,
      [
        submissionId,
        verdict,
        analysis.confidence,
        analysis.relevance,
        analysis.observations.length > 0
          ? JSON.stringify({ observations: analysis.observations.map((item) => ({ ...item })) })
          : null,
        analysis.rationale,
        analysis.escalationReason,
        analysis.model,
        analysis.inputTokens,
        analysis.outputTokens,
        durationMs,
        stage,
      ],
    );
  }

  /// The private object keys making up a submission's proof, with the window
  /// the attempt ran in.
  ///
  /// `media_url` holds one to ten keys, already validated on the way in. The
  /// window comes from `user_quests`, not from the submission alone, because
  /// "was this photograph taken for this attempt" is a question about the
  /// assignment.
  async forensicsSubject(submissionId: string): Promise<{
    mediaUrl: string;
    userId: string;
    assignedAt: Date;
    submittedAt: Date;
  } | null> {
    const result = await this.database.query<{
      media_url: string;
      user_id: string;
      assigned_at: Date;
      submitted_at: Date;
    }>(
      `SELECT s.media_url, s.user_id, uq.assigned_at, s.submitted_at
       FROM submissions s JOIN user_quests uq ON uq.id = s.user_quest_id
       WHERE s.id = $1`,
      [submissionId],
    );
    const row = result.rows[0];
    return row
      ? { mediaUrl: row.media_url, userId: row.user_id, assignedAt: row.assigned_at, submittedAt: row.submitted_at }
      : null;
  }

  /// Stores measured facts against the uploaded object.
  ///
  /// Keyed on `object_key`, which is unique, and a no-op when no row exists —
  /// the seed uploads bytes without creating `media_objects` rows, and a
  /// missing row must not fail the pass. The aggregate report is written to
  /// the verification row regardless, so the policy and the moderator always
  /// have it.
  async recordObjectFacts(facts: {
    objectKey: string;
    capturedAt?: Date;
    width: number;
    height: number;
    /// Null for a frame too flat to fingerprint; the column is nullable and
    /// findDuplicate skips perceptual matching when it is absent.
    perceptualHash: string | null;
    contentMd5: string;
    report: Record<string, unknown>;
  }): Promise<void> {
    await this.database.query(
      `UPDATE media_objects
       SET captured_at = $2, width = $3, height = $4,
           perceptual_hash = $5::bit(64), content_md5 = $6,
           forensics = $7::jsonb, forensics_at = now()
       WHERE object_key = $1`,
      [
        facts.objectKey,
        facts.capturedAt ?? null,
        facts.width,
        facts.height,
        facts.perceptualHash,
        facts.contentMd5,
        JSON.stringify(facts.report),
      ],
    );
  }

  /// Stores the aggregate forensics report on the verification row.
  async recordForensics(submissionId: string, report: Record<string, unknown>): Promise<void> {
    await this.database.query(
      `UPDATE submission_verifications SET forensics = $2::jsonb WHERE submission_id = $1`,
      [submissionId, JSON.stringify(report)],
    );
  }

  /// The closest prior submission to this image, exact match preferred.
  ///
  /// Scoped to submissions *other than* this one and to proof that still
  /// counts — a soft-deleted or moderator-removed post is not evidence of
  /// recycling. Ordering puts a byte-identical match first, then the nearest
  /// perceptual match within threshold.
  ///
  /// Hamming distance is `bit_count(a # b)`, computed by Postgres. The scan is
  /// bounded by the partial indexes from migration 0026, which is adequate at
  /// current volume; a platform-wide nearest-neighbour search at scale wants
  /// an LSH or BK-tree index and is deliberately not built yet.
  async findDuplicate(
    submissionId: string,
    ownerId: string,
    contentMd5: string,
    /// Null when this frame could not be perceptually fingerprinted, which
    /// disables the perceptual half of the search rather than matching
    /// everything — see `differenceHash`. Exact-byte matching still applies.
    perceptualHash: string | null,
    threshold: number,
  ): Promise<{ submissionId: string; distance: number; exact: boolean; ownedByThisUser: boolean } | null> {
    const result = await this.database.query<{
      submission_id: string;
      distance: number | null;
      exact: boolean;
      owned_by_this_user: boolean;
    }>(
      `SELECT s.id AS submission_id,
              bit_count(m.perceptual_hash # $4::bit(64))::int AS distance,
              (m.content_md5 = $3) AS exact,
              (s.user_id = $2) AS owned_by_this_user
       FROM media_objects m
       JOIN submissions s ON s.id = m.submission_id
       WHERE m.kind = 'submission' AND m.status = 'ready' AND m.deleted_at IS NULL
         AND s.id <> $1
         AND s.deleted_at IS NULL AND s.moderation_removed_at IS NULL
         AND (
           m.content_md5 = $3
           OR ($4::bit(64) IS NOT NULL
               AND m.perceptual_hash IS NOT NULL
               AND bit_count(m.perceptual_hash # $4::bit(64)) <= $5)
         )
       ORDER BY (m.content_md5 = $3) DESC,
                bit_count(m.perceptual_hash # $4::bit(64)) ASC NULLS LAST
       LIMIT 1`,
      [submissionId, ownerId, contentMd5, perceptualHash, threshold],
    );
    const row = result.rows[0];
    return row
      ? {
          submissionId: row.submission_id,
          // Null only when a hash was absent, which the WHERE above allows
          // solely on the exact-bytes branch — and distance is meaningless
          // for an exact match, which the caller reports as such without
          // consulting it.
          distance: row.distance ?? 0,
          exact: row.exact,
          ownedByThisUser: row.owned_by_this_user,
        }
      : null;
  }

  /// The resolved verification contract for a submission's quest.
  ///
  /// Read through the view so the worker cannot disagree with the admin
  /// surface about what a quest's proof means or what the agent may do.
  async contractFor(submissionId: string): Promise<{
    verifiability: 'content' | 'provenance_only' | 'none';
    evidenceRubric: string;
    mayAutoApprove: boolean;
    mayAutoReject: boolean;
  } | null> {
    const result = await this.database.query<{
      verifiability: 'content' | 'provenance_only' | 'none';
      evidence_rubric: string;
      may_auto_approve: boolean;
      may_auto_reject: boolean;
    }>(
      `SELECT c.verifiability, c.evidence_rubric, c.may_auto_approve, c.may_auto_reject
       FROM submissions s
       JOIN user_quests uq ON uq.id = s.user_quest_id
       JOIN quest_verification_contract c ON c.quest_id = uq.quest_id
       WHERE s.id = $1`,
      [submissionId],
    );
    const row = result.rows[0];
    return row
      ? {
          verifiability: row.verifiability,
          evidenceRubric: row.evidence_rubric,
          mayAutoApprove: row.may_auto_approve,
          mayAutoReject: row.may_auto_reject,
        }
      : null;
  }

  /// What the vision pass concluded about one submission's media, for the
  /// agent pipeline to read as CV evidence.
  ///
  /// This is the bridge between the two verifiers. The vision cascade runs
  /// once, inline off `submission.created`, and stores its findings here; the
  /// CAMARA agent picks the same submission up from its queue moments later
  /// and reads them rather than paying for a second look at the same image.
  /// One vision pass, one recorded opinion, two readers — which is also what
  /// stops the two systems from reaching different conclusions about the same
  /// photograph.
  ///
  /// Returns null when no row exists at all. A row in any state is returned
  /// as-is: `state` is what tells the caller whether there is a usable
  /// finding, and collapsing 'failed' into null would hide a retryable
  /// failure behind the same answer as a submission nobody has looked at.
  async contentEvidenceFor(submissionId: string): Promise<{
    state: VerificationState;
    verdict: ProofVerdict | null;
    confidence: number | null;
    relevance: number | null;
    stage: string | null;
    model: string;
    observations: readonly ProofObservation[];
    forensics: Record<string, unknown> | null;
  } | null> {
    const result = await this.database.query<{
      state: VerificationState;
      verdict: ProofVerdict | null;
      confidence: string | null;
      relevance: string | null;
      stage: string | null;
      model: string;
      content_evidence: { observations?: unknown } | null;
      forensics: Record<string, unknown> | null;
    }>(
      `SELECT state, verdict, confidence, relevance, stage, model, content_evidence, forensics
       FROM submission_verifications WHERE submission_id = $1`,
      [submissionId],
    );
    const row = result.rows[0];
    if (!row) return null;
    return {
      state: row.state,
      verdict: row.verdict,
      // numeric(4,3) comes back from the driver as a string; parsed here so
      // callers never compare a threshold against '0.850'.
      confidence: row.confidence === null ? null : Number(row.confidence),
      relevance: row.relevance === null ? null : Number(row.relevance),
      stage: row.stage,
      model: row.model,
      observations: parseObservations(row.content_evidence?.observations),
      forensics: row.forensics,
    };
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
              -- Relevance beside confidence, never instead of it: one is how
              -- much the media has to do with the quest, the other how sure
              -- the analysis was. A moderator triaging this queue wants both.
              v.relevance, v.content_evidence,
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
      // FOR KEY SHARE: the same fan-out race guarded in
      // submissions.repository.ts. This insert shares a transaction with the
      // verdict, so an admin closing their account at the wrong moment would
      // roll back the verdict along with its alert.
      `WITH recipients AS (
         SELECT a.user_id FROM admins a
         JOIN users u ON u.id = a.user_id
         FOR KEY SHARE OF u
       ), inserted AS (
         INSERT INTO notifications (user_id, title, body, type, reference_id)
         SELECT user_id, $1, $2, 'proof_unclear', $3 FROM recipients
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
