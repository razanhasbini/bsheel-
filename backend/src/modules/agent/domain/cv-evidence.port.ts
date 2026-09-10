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
  readonly requirements: {
    readonly actions: readonly string[];
    readonly objects: readonly string[];
    readonly landmarks: readonly string[];
    readonly locationDescription?: string;
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
   */
  analyze(input: CvEvidenceAnalysisInput): Promise<CvEvidence>;

  /** Optional: resolve one of the opaque frame refs analyze() returned. */
  getFrame?(frameRef: string): Promise<{ contentType: 'image/jpeg' | 'image/png'; bytes: Uint8Array }>;
}
