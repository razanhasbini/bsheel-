import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { AgentRunKind, CvEvidence, NetworkEvidence } from '../domain/agent.schemas.js';

export interface AgentRunRecord {
  readonly id: string;
  readonly status: 'pending' | 'running' | 'succeeded' | 'failed';
}

export interface StartAgentRunInput {
  readonly kind: AgentRunKind;
  readonly subjectType: 'user_quest' | 'submission';
  readonly subjectId: string;
  readonly idempotencyKey: string;
  readonly model: string;
  readonly promptVersion: string;
  readonly policyVersion: string;
  readonly inputSnapshot: Record<string, unknown>;
}

@Injectable()
export class AgentRunsRepository {
  constructor(private readonly database: DatabaseService) {}

  /**
   * Claims this idempotency key for one run, atomically.
   *
   * This single statement IS the claim — there is deliberately no read-then-
   * decide in front of it, because a caller that reads the row first and then
   * starts has two predicates for one question, and the one that loses is
   * silent. The read method that used to exist for that purpose is gone
   * rather than left lying around.
   *
   * Returns null when the key is held: either a run succeeded, or another
   * worker holds a claim that has not yet expired.
   *
   * `leaseSeconds` is what makes a killed worker recoverable. The reclaim
   * clause used to read `WHERE agent_runs.status = 'failed'` alone, so a row
   * left 'running' by a restart or an OOM could never be started again —
   * the submission was permanently unevaluable, `start()` returned null, and
   * the processor logged "nothing to verify" and acknowledged the job. A
   * claim older than the lease is presumed abandoned and taken.
   */
  async start(input: StartAgentRunInput, leaseSeconds: number): Promise<AgentRunRecord | null> {
    const result = await this.database.query<AgentRunRecord>(
      `INSERT INTO agent_runs (kind, subject_type, subject_id, idempotency_key, status, model, prompt_version, policy_version, input_snapshot, started_at)
       VALUES ($1, $2, $3, $4, 'running', $5, $6, $7, $8::jsonb, now())
       ON CONFLICT (idempotency_key) DO UPDATE SET
         status = 'running', model = EXCLUDED.model,
         prompt_version = EXCLUDED.prompt_version,
         policy_version = EXCLUDED.policy_version,
         input_snapshot = EXCLUDED.input_snapshot,
         output = NULL, error_code = NULL, error_message = NULL,
         started_at = now(), completed_at = NULL
       WHERE agent_runs.status = 'failed'
          OR (agent_runs.status IN ('pending', 'running')
              AND (agent_runs.started_at IS NULL
                   OR agent_runs.started_at < now() - make_interval(secs => $9)))
       RETURNING id, status`,
      [
        input.kind,
        input.subjectType,
        input.subjectId,
        input.idempotencyKey,
        input.model,
        input.promptVersion,
        input.policyVersion,
        JSON.stringify(input.inputSnapshot),
        leaseSeconds,
      ],
    );
    return result.rows[0] ?? null;
  }

  async succeed(runId: string, output: Record<string, unknown>): Promise<void> {
    await this.database.query(
      `UPDATE agent_runs SET status = 'succeeded', output = $2::jsonb, completed_at = now() WHERE id = $1`,
      [runId, JSON.stringify(output)],
    );
  }

  async fail(runId: string, errorCode: string, errorMessage: string): Promise<void> {
    await this.database.query(
      `UPDATE agent_runs SET status = 'failed', error_code = $2, error_message = $3, completed_at = now() WHERE id = $1`,
      [runId, errorCode, errorMessage.slice(0, 2000)],
    );
  }

  async recordNetworkEvidence(
    runId: string,
    userQuestId: string,
    submissionId: string,
    evidence: NetworkEvidence,
  ): Promise<void> {
    await this.database.query(
      `INSERT INTO network_evidence (agent_run_id, user_quest_id, submission_id, capability, provider, provider_reference, outcome, result, observed_at, valid_until)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9, $10)
       ON CONFLICT (provider, capability, provider_reference) DO NOTHING`,
      [
        runId,
        userQuestId,
        submissionId,
        evidence.capability,
        evidence.provider,
        evidence.providerReference,
        evidence.outcome,
        JSON.stringify(evidence.result),
        evidence.observedAt,
        evidence.validUntil ?? null,
      ],
    );
  }

  /// Submissions whose geofence answer was wrong *at the time* and is not any
  /// more, because the event arrived late (#15).
  ///
  /// The recoverable half of "CAMARA was unavailable". The three mandatory
  /// capabilities are not equally retryable, and treating them as if they
  /// were is how a retry becomes a fabrication:
  ///
  ///   LOCATION_VERIFICATION and LOCATION_RETRIEVAL ask where the device is
  ///   **now**, bounded by maxAge. Re-asking tomorrow about a quest that
  ///   ended yesterday answers a different question, and recording that
  ///   answer as evidence for the old window would be inventing proof of
  ///   presence. Those stay with a human, permanently, and that is correct.
  ///
  ///   GEOFENCING is the exception, and the only one. Its evidence is not a
  ///   request at all — it is a replay of entry/exit events the provider
  ///   POSTed to our webhook and we stored. Those events are *historical*:
  ///   `occurred_at` is when the device crossed the boundary, `received_at`
  ///   is when we heard about it. A webhook retry, a provider backlog or an
  ///   outage on our side separates the two, and an event that lands after
  ///   the agent ran is genuinely new information about a window that has
  ///   already closed.
  ///
  /// So: a GEOFENCING evidence row that did not support completion, and an
  /// event for that same assignment received after that evidence was
  /// observed. The submission must still be pending — once a person has
  /// decided, late evidence is a matter for an appeal, not a re-run.
  ///
  /// Returns the newest event id alongside, which becomes part of the run's
  /// idempotency key: one re-verification per batch of new evidence, and a
  /// redelivered event re-runs nothing.
  async submissionsWithLateGeofenceEvidence(limit: number): Promise<readonly {
    submissionId: string;
    latestEventId: string;
  }[]> {
    const result = await this.database.query<{ submission_id: string; latest_event_id: string }>(
      `SELECT ne.submission_id,
              (SELECT event.id FROM geofencing_events event
               JOIN geofencing_subscriptions subscription ON subscription.id = event.subscription_id
               WHERE subscription.user_quest_id = ne.user_quest_id
                 AND event.received_at > ne.observed_at
               ORDER BY event.received_at DESC, event.id DESC
               LIMIT 1) AS latest_event_id
       FROM network_evidence ne
       JOIN submissions s ON s.id = ne.submission_id
       WHERE ne.capability = 'GEOFENCING'
         AND ne.outcome <> 'SUPPORTED'
         AND s.status = 'pending'
         AND s.deleted_at IS NULL
         AND EXISTS (
           SELECT 1 FROM geofencing_events event
           JOIN geofencing_subscriptions subscription ON subscription.id = event.subscription_id
           WHERE subscription.user_quest_id = ne.user_quest_id
             AND event.received_at > ne.observed_at
         )
       GROUP BY ne.submission_id, ne.user_quest_id, ne.observed_at
       ORDER BY ne.observed_at
       LIMIT $1`,
      [Math.min(Math.max(limit, 1), 200)],
    );
    return result.rows.map((row) => ({
      submissionId: row.submission_id,
      latestEventId: row.latest_event_id,
    }));
  }

  async recordCvEvidence(runId: string, submissionId: string, evidence: CvEvidence): Promise<void> {
    await this.database.query(
      `INSERT INTO cv_evidence (agent_run_id, submission_id, provider, model_version, status, result, analyzed_at)
       VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7)`,
      [runId, submissionId, evidence.provider, evidence.modelVersion, evidence.status, JSON.stringify(evidence), evidence.analyzedAt],
    );
  }

  /// Most recent runs, for the demo surface. Returns the decision only —
  /// never the input snapshot, which carries user content.
  async recent(limit: number): Promise<readonly {
    kind: string;
    status: string;
    decision: string | null;
    createdAt: string;
  }[]> {
    const capped = Math.min(Math.max(limit, 1), 50);
    const result = await this.database.query<{
      kind: string;
      status: string;
      decision: string | null;
      created_at: Date;
    }>(
      `SELECT kind, status, output->>'decision' AS decision, created_at
       FROM agent_runs ORDER BY created_at DESC LIMIT $1`,
      [capped],
    );
    return result.rows.map((row) => ({
      kind: row.kind,
      status: row.status,
      decision: row.decision,
      createdAt: row.created_at.toISOString(),
    }));
  }

}
