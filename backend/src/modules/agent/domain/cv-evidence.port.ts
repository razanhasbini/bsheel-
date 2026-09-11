import type { CvEvidence } from './agent.schemas.js';

/**
 * The contract a computer-vision engineer's service must satisfy to plug
 * into the agent. The HTTP wire shape of `analyze()`'s input/output is
 * implemented literally in src/integrations/computer-vision — this
 * interface is what the rest of the agent module depends on, so swapping
 * models or providers never touches submission-verification.service.ts.
 */
export interface CvEvidenceAnalysisInput {
  readonly runId: string;
  readonly submissionId: string;
  readonly media: ReadonlyArray<{
    readonly mediaObjectId: string;
    readonly contentType: string;
    /** Short-lived, server-generated. Never a raw storage credential. */
    readonly downloadUrl: string;
  }>;
  /**
   * What the media is being judged *against*.
   *
   * The structured lists come from `quests.verification_requirements`, which
   * is hand-authored and empty on almost every quest — so a provider given
   * only those lists has nothing to match and can do no better than report
   * that media exists. `task` is the part that is always populated, and it is
   * what makes a relevance judgement possible at all.
   */
  readonly requirements: {
    readonly actions: readonly string[];
    readonly objects: readonly string[];
    readonly landmarks: readonly string[];
    readonly locationDescription?: string;
  };
  /**
   * The quest as specified, plus what proof is allowed to establish for it.
   *
   * `verifiability` is the single most important field here and the one an
   * external CV service is most likely to ignore at its peril. Roughly a third
   * of Bsheel's catalogue cannot be judged from a photograph at all — "spend
   * an hour with no phone" was photographed by the phone — and a model asked
   * an incoherent question answers it anyway with a confidence score attached.
   * A provider MUST NOT report low relevance as a negative finding when this
   * says `provenance_only` or `none`: there, low relevance is the expected and
   * correct state for an honest submission.
   */
  readonly task: {
    readonly title: string;
    readonly description: string;
    readonly category: string;
    /** What a passing photograph looks like for this quest, authored by an admin. */
    readonly evidenceRubric: string;
    readonly verifiability: 'content' | 'provenance_only' | 'none';
  };
  readonly maxKeyFrames: number;
  readonly idempotencyKey: string;
}

export interface CvEvidenceProvider {
  /**
   * Must return CvEvidenceSchema exactly. Required behavior:
   * - confidence always normalized to 0..1
   * - video timestamps in milliseconds
   * - distinguishes UNAVAILABLE/FAILED from "ran cleanly, detected nothing"
   * - never approves/rejects — analysis only
   * - a disabled/unreachable provider fails closed to UNAVAILABLE, never a
   *   fabricated positive result
   * - `relevance` answers "how much does this media have to do with the
   *   quest", which is NOT the same question as "how sure are you". Report it
   *   only where `task.verifiability` is 'content'; elsewhere leave it unset
   *   rather than reporting a low number a decider might act on.
   */
  analyze(input: CvEvidenceAnalysisInput): Promise<CvEvidence>;

  /** Optional: resolve one of the opaque frame refs analyze() returned. */
  getFrame?(frameRef: string): Promise<{ contentType: 'image/jpeg' | 'image/png'; bytes: Uint8Array }>;
}
