import type { ForensicsReport } from './proof-forensics.js';
import type { ProofAnalysis, ProofTier, Verifiability } from './proof-verification.types.js';

/// The decision policy for AI proof verification (#47).
///
/// Pure, so the whole of "what is the agent allowed to conclude, and when" is
/// one readable function with no I/O, no provider and no database. Everything
/// that grants authority lives here; nothing else in the pipeline may approve
/// or reject.
///
/// Two asymmetries run through it, and both are deliberate.
///
/// The errors are not equally costly. A false approval costs leaderboard
/// integrity and is recoverable — takedown and XP rollback already exist. A
/// false rejection tells an honest player that they cheated, and the appeal
/// costs *them* the effort. So the reject bar is higher, requires the most
/// capable model, and requires the quest's contract to permit it.
///
/// Proof does not mean the same thing for every quest. A photograph cannot
/// establish that someone read twenty pages or spent an hour without their
/// phone. Where content cannot decide, this never lets content decide.

export type ProofDecision = 'approve' | 'reject' | 'escalate';

export interface PolicyInput {
  readonly verifiability: Verifiability;
  readonly mayAutoApprove: boolean;
  readonly mayAutoReject: boolean;
  readonly forensics: ForensicsReport;
  /// Absent when no content analysis was run, which is correct for
  /// `provenance_only` and `none` quests — spending a vision call to produce
  /// advice the policy must ignore is waste.
  readonly analysis?: ProofAnalysis;
  readonly approveMinConfidence: number;
  readonly rejectMinConfidence: number;
}

export interface PolicyOutcome {
  readonly decision: ProofDecision;
  /// Why, in the words a moderator or an audit row should carry.
  readonly reason: string;
  /// Which rung is accountable for this outcome.
  readonly stage: 'forensics' | ProofTier;
}

/// Findings that settle the matter on their own, without a model.
///
/// These are the safest possible grounds for an automated rejection, and it
/// is worth being clear why: they are measurements, not opinions. A
/// photograph captured before the quest was assigned is recycled whatever it
/// depicts; a byte-identical copy of another user's proof is not this user's
/// proof; a file declaring itself generated is not a photograph of anything
/// done. None of that requires judgement, so none of it is spent on a model.
function decisiveForensicReason(forensics: ForensicsReport): string | null {
  const decisive = forensics.findings.find((finding) => finding.weight === 'decisive');
  return decisive ? decisive.detail : null;
}

/// Findings that should stop an automated approval without justifying a
/// rejection — a screenshot, a near-duplicate of the user's own earlier
/// proof. Suspicious enough that a human should look, nowhere near enough to
/// accuse anyone.
function hasStrongDoubt(forensics: ForensicsReport): boolean {
  return forensics.findings.some((finding) => finding.weight === 'strong');
}

export function decide(input: PolicyInput): PolicyOutcome {
  // 1. Deterministic provenance failure. Ends it before any model opinion is
  //    considered, and before any is paid for.
  const decisive = decisiveForensicReason(input.forensics);
  if (decisive) {
    return input.mayAutoReject
      ? { decision: 'reject', reason: decisive, stage: 'forensics' }
      : {
          decision: 'escalate',
          reason: `${decisive} This quest does not permit automated rejection, so a human decides.`,
          stage: 'forensics',
        };
  }

  // 2. Quests where a photograph cannot establish the task. The question is
  //    authenticity, and provenance has just answered it.
  //
  //    `none` trusts by default: nothing about the image bears on the task, so
  //    demanding photographic proof would punish honest players — only a
  //    decisive failure, already handled above, counts against them.
  //
  //    `provenance_only` is stricter, because authenticity *is* meaningful
  //    there: a strong doubt escalates rather than passing.
  if (input.verifiability === 'none') {
    return input.mayAutoApprove
      ? {
          decision: 'approve',
          reason: 'Nothing about a photograph can establish this quest, and its provenance raises no decisive problem.',
          stage: 'forensics',
        }
      : { decision: 'escalate', reason: 'This quest is not photographically verifiable and does not permit automated approval.', stage: 'forensics' };
  }

  if (input.verifiability === 'provenance_only') {
    if (hasStrongDoubt(input.forensics)) {
      return {
        decision: 'escalate',
        reason: 'The proof cannot show this quest was done, and its provenance is doubtful enough to want a human.',
        stage: 'forensics',
      };
    }
    return input.mayAutoApprove
      ? {
          decision: 'approve',
          reason: 'What was learned is not visible in a photograph, and the proof is authentic on every check available.',
          stage: 'forensics',
        }
      : { decision: 'escalate', reason: 'This quest is judged on provenance alone and does not permit automated approval.', stage: 'forensics' };
  }

  // 3. Content-verifiable quests. A verdict is required to act at all.
  const analysis = input.analysis;
  if (!analysis) {
    return { decision: 'escalate', reason: 'No content analysis was produced for a quest that requires one.', stage: 'forensics' };
  }

  if (analysis.verdict === 'fail') {
    // Only the top rung may conclude that proof is fake. A cheap model's
    // 'fail' is a reason to look harder, never a reason to accuse.
    if (analysis.tier !== 'reject_review') {
      return {
        decision: 'escalate',
        reason: `Analysis at the ${analysis.tier} tier judged this proof to fail, which is not sufficient authority to reject.`,
        stage: analysis.tier,
      };
    }
    if (!input.mayAutoReject) {
      return { decision: 'escalate', reason: `${analysis.rationale} This quest does not permit automated rejection.`, stage: analysis.tier };
    }
    if (analysis.confidence === null || analysis.confidence < input.rejectMinConfidence) {
      return {
        decision: 'escalate',
        reason: `${analysis.rationale} Confidence is below the bar required to reject, so a human decides.`,
        stage: analysis.tier,
      };
    }
    return { decision: 'reject', reason: analysis.rationale, stage: analysis.tier };
  }

  if (analysis.verdict === 'pass') {
    // Provenance still has a veto. Content looking right does not make a
    // screenshot or a re-saved image into this user's own proof.
    if (hasStrongDoubt(input.forensics)) {
      return {
        decision: 'escalate',
        reason: `${analysis.rationale} The content looks right, but the file's provenance is doubtful.`,
        stage: analysis.tier,
      };
    }
    if (!input.mayAutoApprove) {
      return { decision: 'escalate', reason: `${analysis.rationale} This quest does not permit automated approval.`, stage: analysis.tier };
    }
    if (analysis.confidence === null || analysis.confidence < input.approveMinConfidence) {
      return {
        decision: 'escalate',
        reason: `${analysis.rationale} Confidence is below the bar required to approve, so a human decides.`,
        stage: analysis.tier,
      };
    }
    return { decision: 'approve', reason: analysis.rationale, stage: analysis.tier };
  }

  return {
    decision: 'escalate',
    reason: analysis.escalationReason || 'The agent could not decide on this proof.',
    stage: analysis.tier,
  };
}

/// Which rung to run next, given what the previous one said.
///
/// The cascade exists because the models differ ~50x in price and most
/// submissions are unambiguous. Returning null means stop — the policy can
/// decide on what it already has.
export function nextTier(
  current: ProofTier | null,
  approveMinConfidence: number,
  analysis?: ProofAnalysis,
): ProofTier | null {
  // Nothing has run yet: start at the bottom.
  if (current === null) return 'triage';
  if (!analysis) return null;

  const confidentEnoughToApprove = analysis.confidence !== null
    && analysis.confidence >= approveMinConfidence;

  if (current === 'triage') {
    // A cheap 'fail' is never acted on, but it is the strongest reason to
    // spend the top model — so it goes straight there rather than paying for
    // the middle rung on the way.
    if (analysis.verdict === 'fail') return 'reject_review';
    // A confident cheap 'pass' is exactly what the cheap rung is for. An
    // *unconfident* one is not a reason to give up and spend a moderator's
    // attention — the better model may well settle it, and it costs less than
    // a human review does.
    if (analysis.verdict === 'pass') return confidentEnoughToApprove ? null : 'deep';
    return 'deep';
  }

  if (current === 'deep') {
    return analysis.verdict === 'fail' ? 'reject_review' : null;
  }

  return null;
}
