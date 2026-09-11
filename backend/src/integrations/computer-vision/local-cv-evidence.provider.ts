import { Injectable, Logger } from '@nestjs/common';
import type { CvEvidence } from '../../modules/agent/domain/agent.schemas.js';
import type { CvEvidenceAnalysisInput, CvEvidenceProvider } from '../../modules/agent/domain/cv-evidence.port.js';
import type { ProofObservation } from '../../modules/submissions/domain/proof-verification.types.js';
import { ProofVerificationRepository } from '../../modules/submissions/infrastructure/proof-verification.repository.js';

/**
 * The in-process CV provider: the agent's eyes (#47 + #53).
 *
 * Before this existed, `CV_PROVIDER` had two settings — `none`, which returns
 * UNAVAILABLE, and `http`, which needs a computer-vision service nobody has
 * built. Every deployment therefore ran `none`, and `finalizeDecision` sends
 * every submission with unavailable CV evidence to a human. So the CAMARA
 * agent could establish, to network-grade certainty, that a player's phone was
 * standing inside the right geofence — and knew about the photograph they
 * submitted only that a file had been attached. It could check that media was
 * uploaded. It could not see it.
 *
 * Meanwhile the #47 vision cascade was looking at that same photograph
 * properly — forensics, then a tiered vision pass against the quest's
 * verification contract — and keeping the answer to itself in
 * `submission_verifications`. One system had eyes; the other had authority.
 *
 * This adapter is the seam between them, and it is deliberately a *reader*.
 *
 * Why reading, and not running: the vision pass is already run inline by the
 * `submission.created` consumer, awaited to completion **before** the agent's
 * job is enqueued (see domain-events.processor.ts), so by the time an agent
 * worker picks a submission up there is a finding to read. Calling the
 * cascade again from here would be a second grammar-constrained vision call
 * on the same bytes — a straight duplicate of the most expensive thing the
 * feature does — and worse, two passes can disagree, leaving two stored
 * opinions about one photograph with nothing to say which governs. Reading
 * makes the shared vision pass the single source of truth about the media, at
 * the cost of one row read.
 *
 * That ordering is load-bearing rather than lucky, and
 * domain-events.processor.spec.ts fails if the two calls are reordered or
 * run concurrently, so a future edit cannot quietly blind the agent again.
 *
 * What the ordering does NOT promise is that the finding is usable. The row
 * may be 'queued' (the analyzer is unconfigured, so verify() only enqueued),
 * 'skipped', 'failed', or — since the catch-up sweep can re-run a failed
 * submission at any time — mid-flight on another worker. Every one of those
 * maps to UNAVAILABLE or FAILED below and reaches a human. This adapter
 * reports what it found; it never waits for a better answer.
 *
 * What this never does: decide. It reports relevance, typed detections and a
 * measured integrity block. The verdict the cascade reached is deliberately
 * left behind — handing the agent a second opinion to defer to is not the same
 * as handing it evidence to reason over, and `CvEvidenceProvider` forbids it.
 */
@Injectable()
export class LocalCvEvidenceProvider implements CvEvidenceProvider {
  private readonly logger = new Logger(LocalCvEvidenceProvider.name);

  constructor(private readonly proofVerification: ProofVerificationRepository) {}

  async analyze(input: CvEvidenceAnalysisInput): Promise<CvEvidence> {
    const finding = await this.proofVerification.contentEvidenceFor(input.submissionId);
    const evidence = toCvEvidence(finding, input, new Date().toISOString());
    this.logger.debug(
      {
        submissionId: input.submissionId,
        status: evidence.status,
        verifiability: input.task.verifiability,
        relevance: evidence.relevance ?? null,
        detections: evidence.detections.length,
      },
      'CV evidence resolved from the shared vision pass',
    );
    return evidence;
  }
}

/** What `contentEvidenceFor` returns; narrowed here so the mapping is pure. */
export type StoredProofFinding = Awaited<
  ReturnType<ProofVerificationRepository['contentEvidenceFor']>
>;

const DETECTION_TYPE: Record<ProofObservation['kind'], CvEvidence['detections'][number]['type']> = {
  action: 'ACTION',
  object: 'OBJECT',
  landmark: 'LANDMARK',
  location_cue: 'LOCATION_CUE',
};

const PROVIDER = 'bsheel-proof-cascade';

/**
 * Translates one stored vision-pass finding into the agent's CV contract.
 *
 * Pure and exported so the mapping is unit-tested without a database: the
 * interesting behaviour here is entirely in which stored state becomes which
 * `status`, and in what is deliberately withheld.
 */
export function toCvEvidence(
  finding: StoredProofFinding,
  input: CvEvidenceAnalysisInput,
  analyzedAt: string,
): CvEvidence {
  // No row at all. The submission was never enqueued for analysis — an older
  // submission, or a deployment where the feature has never been on.
  if (!finding) {
    return unavailable(analyzedAt, 'No proof analysis exists for this submission.');
  }

  // 'failed' is reported as FAILED rather than UNAVAILABLE because the two are
  // different operationally: one is retryable work, the other is work nobody
  // asked for. Both reach a human — finalizeDecision refuses to act without
  // AVAILABLE CV evidence either way — but the stored evidence should say
  // which, or an outage is indistinguishable from a disabled feature.
  if (finding.state === 'failed') {
    return {
      status: 'FAILED',
      provider: PROVIDER,
      modelVersion: finding.model || 'unknown',
      analyzedAt,
      detections: [],
      keyFrames: [],
      warnings: ['The proof analysis failed for this submission and has not produced a finding.'],
    };
  }

  if (finding.state !== 'complete') {
    return unavailable(
      analyzedAt,
      finding.state === 'queued'
        ? 'The proof analysis has not run for this submission yet.'
        : 'The proof analysis was skipped for this submission.',
    );
  }

  const warnings: string[] = [];

  // Relevance is admissible ONLY where the quest's contract says content can
  // decide. This is the whole of #47's central finding applied to the new
  // signal, and getting it wrong is how an automated reviewer rejects honest
  // players: a photograph of a coffee cup is genuinely irrelevant to
  // "compliment a stranger", and the submission is genuinely honest. Reporting
  // the number anyway, on the theory that a downstream decider will remember
  // to ignore it, is exactly the sort of hope this codebase does not run on.
  const contentCanDecide = input.task.verifiability === 'content';
  if (!contentCanDecide) {
    warnings.push(
      `This quest's verification contract is '${input.task.verifiability}': the submitted media cannot `
      + 'establish whether the task was done, and its relevance to the task was deliberately not assessed. '
      + 'Judge authenticity only, and never treat the absence of visible proof as evidence against the player.',
    );
  }

  // An escalation reason is a statement about the media's legibility ("too
  // dark to judge", "the frame is out of focus"), which is evidence. The
  // verdict that reason accompanied is not, and is not passed on.
  const detections = finding.observations.map((observation) => ({
    type: DETECTION_TYPE[observation.kind],
    label: observation.label,
    confidence: observation.confidence,
    present: observation.present,
    // Stills carry no timeline. Video frames are sampled by the cascade and
    // reduced to observations before they reach this row, so per-detection
    // timestamps are not recoverable here and an invented 0 would read as
    // "seen at the first frame".
    timestampsMs: [],
  }));

  // A pass that completed without learning anything about the media is not
  // available evidence, whatever its state column says.
  //
  // This is the failure mode the whole change exists to close, arriving by the
  // back door. A vision call that was cut short, refused, or returned an
  // unreadable body is recorded as state 'complete' with verdict 'unclear' —
  // correctly, because the cascade did finish and did escalate. But it
  // carries no relevance and no observations, and reporting that as AVAILABLE
  // would let the agent approve a content-verifiable quest having learned
  // exactly nothing about the photograph: the "a file was attached, good
  // enough" decision, reached through a different door.
  //
  // A relevance score with no observations is still information, so both have
  // to be absent. And this applies only where content can decide:
  // provenance_only and none quests complete without a vision call by design,
  // and calling that unavailable would send a third of the catalogue to a
  // human for a reason that is not true.
  if (contentCanDecide && detections.length === 0 && finding.relevance === null) {
    return unavailable(
      analyzedAt,
      'The proof analysis completed without assessing the submitted media for this quest: '
      + 'no relevance score and no observations were recorded.',
    );
  }

  const integrity = toIntegrity(finding.forensics);
  return {
    status: 'AVAILABLE',
    provider: PROVIDER,
    // 'forensics-only' rather than an empty string when no vision model ran:
    // provenance_only and none quests complete without one by design, and a
    // blank model on an AVAILABLE row reads like a bug.
    modelVersion: finding.model || 'forensics-only',
    analyzedAt,
    ...(contentCanDecide && finding.relevance !== null ? { relevance: finding.relevance } : {}),
    detections,
    // The cascade holds decoded frames only for the duration of its own call
    // and stores none, so there is nothing for `getFrame` to serve. Offering
    // frame refs that cannot be resolved would be worse than offering none:
    // the agent would spend a tool call to be told "unavailable".
    keyFrames: [],
    ...(integrity ? { integrity } : {}),
    warnings,
  };
}

function unavailable(analyzedAt: string, reason: string): CvEvidence {
  return {
    status: 'UNAVAILABLE',
    provider: PROVIDER,
    modelVersion: 'none',
    analyzedAt,
    detections: [],
    keyFrames: [],
    warnings: [reason],
  };
}

/**
 * The integrity block, built from **measured** forensics rather than asked of
 * a model.
 *
 * `CvEvidence.integrity.manipulationLikely` is the sort of question a vision
 * model will answer confidently and badly. Every input here is a
 * measurement — an EXIF capture time outside the quest window, a byte-
 * identical copy of someone else's proof, screen dimensions, a
 * generated-content marker — so the block carries facts and the confidence
 * attached to it describes how much a reviewer should be moved, not how sure a
 * model felt. `weight` is already exactly that judgement, made once in
 * proof-forensics.ts.
 */
function toIntegrity(forensics: Record<string, unknown> | null): CvEvidence['integrity'] {
  if (!forensics || !Array.isArray(forensics.findings)) return undefined;
  const findings = forensics.findings.flatMap((item) => {
    if (typeof item !== 'object' || item === null) return [];
    const record = item as Record<string, unknown>;
    if (typeof record.detail !== 'string' || typeof record.weight !== 'string') return [];
    return [{ weight: record.weight, detail: record.detail }];
  });

  const decisive = findings.some((item) => item.weight === 'decisive');
  const strong = findings.some((item) => item.weight === 'strong');
  const notes = findings
    .filter((item) => item.weight !== 'info')
    .map((item) => item.detail);
  if (notes.length === 0) return undefined;

  return {
    manipulationLikely: decisive,
    // Both weights block an automated approval, which is exactly what
    // proof-policy.ts does with them: a decisive finding ends the matter
    // before any model opinion is considered, and a strong one vetoes a
    // model's 'pass'. Collapsing them into one boolean here is what lets the
    // deciding policy gate on a measurement instead of re-deriving the rule
    // from a confidence number — which it was previously doing by not
    // reading this block at all.
    blocksAutomatedApproval: decisive || strong,
    // A decisive finding is a measurement that settles the matter; a strong
    // one is a reason for a human to look. Neither is a model's hunch, which
    // is why these are fixed numbers rather than something inferred.
    confidence: decisive ? 0.95 : strong ? 0.6 : 0.3,
    notes,
  };
}
