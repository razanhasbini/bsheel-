import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';

/** One verification, assembled for a moderator rather than for a machine. */
export interface VerificationDossier {
  readonly submissionId: string;
  readonly questTitle: string;
  readonly username: string;
  readonly submittedAt: string;
  readonly submissionStatus: string;
  readonly verifiability: string;
  readonly mayAutoApprove: boolean;
  readonly mayAutoReject: boolean;
  readonly needsLocation: boolean;
  readonly placeName: string | null;
  /**
   * Where the quest actually was, and how close counts as there.
   *
   * Sent so the console can say how far off a network fix landed rather
   * than printing a pair of raw coordinates — "3,180 km away" is a fact a
   * reader can weigh; "47.486, 19.079" is one they have to look up.
   */
  readonly placeLatitude: number | null;
  readonly placeLongitude: number | null;
  readonly placeRadiusMeters: number | null;
  readonly decision: string | null;
  readonly confidence: number | null;
  readonly reasons: readonly string[];
  readonly humanReviewReason: string | null;
  readonly conflicts: readonly string[];
  readonly assessment: Record<string, string>;
  readonly model: string;
  readonly ranAt: string | null;
  readonly shadow: boolean;
  readonly network: readonly {
    readonly capability: string;
    readonly outcome: string;
    readonly detail: Record<string, unknown>;
    readonly observedAt: string;
  }[];
  readonly cv: {
    readonly status: string;
    readonly provider: string;
    readonly relevance: number | null;
    readonly observations: readonly { readonly kind: string; readonly label: string; readonly confidence: number | null }[];
    readonly integrity: Record<string, unknown>;
  } | null;
  readonly xpAwarded: number | null;
  readonly recommendedXp: number | null;
  readonly questXp: number;
}

/**
 * Reads the evidence behind a decision, for the review screen.
 *
 * Everything here was already being written — the agent run, the three
 * CAMARA results, the CV findings — and none of it was readable anywhere.
 * A moderator was asked to second-guess a decision whose reasoning they
 * could not see, and the CAMARA work had no way of being shown to anyone.
 *
 * Deliberately assembled per submission rather than as a raw dump: the
 * moderator needs to know which signal drove the outcome, not how Nokia
 * spells its payloads.
 */
@Injectable()
export class AgentEvidenceRepository {
  constructor(private readonly database: DatabaseService) {}

  async recent(limit: number, offset: number): Promise<readonly VerificationDossier[]> {
    const runs = await this.database.query<Row>(
      `${SELECT_DOSSIER}
       ORDER BY r.created_at DESC
       LIMIT $1 OFFSET $2`,
      [limit, offset],
    );
    return Promise.all(runs.rows.map((row) => this.hydrate(row)));
  }

  async forSubmission(submissionId: string): Promise<VerificationDossier | null> {
    const runs = await this.database.query<Row>(
      `${SELECT_DOSSIER} WHERE r.subject_id = $1 ORDER BY r.created_at DESC LIMIT 1`,
      [submissionId],
    );
    return runs.rows[0] ? this.hydrate(runs.rows[0]) : null;
  }

  private async hydrate(row: Row): Promise<VerificationDossier> {
    const [network, cv] = await Promise.all([
      this.database.query<{ capability: string; outcome: string; result: Record<string, unknown>; observed_at: Date }>(
        `SELECT capability, outcome, result, observed_at FROM network_evidence
         WHERE agent_run_id = $1 ORDER BY capability`,
        [row.run_id],
      ),
      this.database.query<{ status: string; provider: string; result: Record<string, unknown> }>(
        `SELECT status, provider, result FROM cv_evidence WHERE agent_run_id = $1 LIMIT 1`,
        [row.run_id],
      ),
    ]);

    const output = (row.output ?? {}) as Record<string, unknown>;
    const cvRow = cv.rows[0];
    const cvResult = (cvRow?.result ?? {}) as Record<string, unknown>;
    const observations = Array.isArray(cvResult.observations) ? cvResult.observations : [];

    return {
      submissionId: row.subject_id,
      questTitle: row.quest_title ?? 'Unknown quest',
      username: row.username ?? 'unknown',
      submittedAt: row.submitted_at?.toISOString() ?? '',
      submissionStatus: row.submission_status ?? 'unknown',
      verifiability: row.verifiability ?? 'unknown',
      mayAutoApprove: row.may_auto_approve ?? false,
      mayAutoReject: row.may_auto_reject ?? false,
      needsLocation: row.needs_location ?? false,
      placeName: row.place_name,
      placeLatitude: row.place_latitude,
      placeLongitude: row.place_longitude,
      placeRadiusMeters: row.place_radius_meters,
      decision: typeof output.decision === 'string' ? output.decision : null,
      confidence: typeof output.confidence === 'number' ? output.confidence : null,
      reasons: Array.isArray(output.reasons) ? (output.reasons as string[]) : [],
      humanReviewReason:
        typeof output.humanReviewReason === 'string' ? output.humanReviewReason : null,
      conflicts: Array.isArray(output.conflicts) ? (output.conflicts as string[]) : [],
      assessment: (output.evidenceAssessment ?? {}) as Record<string, string>,
      model: row.model ?? '',
      ranAt: row.completed_at?.toISOString() ?? null,
      // A shadow run reasoned but changed nothing — worth saying plainly, or
      // the list reads as decisions that were never acted on.
      shadow: row.submission_status === 'pending' && output.decision !== 'HUMAN_REVIEW',
      network: network.rows.map((n) => ({
        capability: n.capability,
        outcome: n.outcome,
        detail: n.result ?? {},
        observedAt: n.observed_at?.toISOString() ?? '',
      })),
      cv: cvRow
        ? {
            status: cvRow.status,
            provider: cvRow.provider,
            relevance: typeof cvResult.relevance === 'number' ? cvResult.relevance : null,
            observations: observations
              .filter((o): o is Record<string, unknown> => typeof o === 'object' && o !== null)
              .map((o) => ({
                kind: String(o.kind ?? o.type ?? 'OBSERVATION'),
                label: String(o.label ?? o.value ?? ''),
                confidence: typeof o.confidence === 'number' ? o.confidence : null,
              })),
            integrity: (cvResult.integrity ?? {}) as Record<string, unknown>,
          }
        : null,
      xpAwarded: row.xp_awarded_amount,
      recommendedXp: row.recommended_xp,
      questXp: row.quest_xp ?? 0,
    };
  }
}

interface Row {
  run_id: string; subject_id: string; model: string; output: unknown;
  completed_at: Date | null;
  quest_title: string | null; username: string | null;
  submitted_at: Date | null; submission_status: string | null;
  verifiability: string | null; may_auto_approve: boolean | null; may_auto_reject: boolean | null;
  needs_location: boolean | null; place_name: string | null;
  place_latitude: number | null; place_longitude: number | null;
  place_radius_meters: number | null;
  xp_awarded_amount: number | null; recommended_xp: number | null; quest_xp: number | null;
}

const SELECT_DOSSIER = `
  SELECT r.id AS run_id, r.subject_id, r.model, r.output, r.completed_at,
         q.title AS quest_title, q.xp_reward AS quest_xp,
         p.username::text AS username,
         s.submitted_at, s.status::text AS submission_status,
         s.xp_awarded_amount, s.recommended_xp,
         c.verifiability, c.may_auto_approve, c.may_auto_reject,
         (d.place_id IS NOT NULL) AS needs_location, mp.name AS place_name,
         -- Where the quest actually was, so the console can say how far off
         -- a network fix landed instead of printing raw coordinates and
         -- leaving the reader to do the geography.
         mp.latitude::float8 AS place_latitude, mp.longitude::float8 AS place_longitude,
         mp.radius_m::float8 AS place_radius_meters
  FROM agent_runs r
  LEFT JOIN submissions s ON s.id = r.subject_id
  LEFT JOIN profiles p ON p.id = s.user_id
  LEFT JOIN user_quests uq ON uq.id = s.user_quest_id
  LEFT JOIN quests q ON q.id = uq.quest_id
  LEFT JOIN quest_verification_contract c ON c.quest_id = q.id
  LEFT JOIN quest_destinations d ON d.quest_id = q.id
  LEFT JOIN map_places mp ON mp.id = d.place_id
  WHERE r.kind = 'submission_verification'`;
