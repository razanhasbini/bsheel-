import type { AgentPolicy, NetworkEvidence, VerificationDecision } from './agent.schemas.js';
import { MANDATORY_CAPABILITIES, type MandatoryCapability } from './network-evidence.port.js';

/**
 * Deterministic bounds and gates the backend enforces around every AI
 * recommendation. Nothing here is a suggestion the model can override — the
 * exact numbers (multipliers, thresholds) are placeholders pending a
 * product decision; they are configured in config/environment.ts, not
 * hard-coded here, so tightening them later is a config change.
 */

export type PolicyBounds = AgentPolicy;

export interface QuestPolicyInputs {
  readonly baseXp: number;
  readonly defaultDurationHours: number;
}

export interface PolicyLimits {
  readonly globalMinDurationMinutes: number;
  readonly globalMaxDurationMinutes: number;
  readonly globalMinXp: number;
  readonly globalMaxXp: number;
  readonly approveThreshold: number;
  readonly rejectThreshold: number;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

/**
 * The absolute range any recommendation must land in: 4 hours to 2 weeks,
 * 5 to 100 XP. Deliberately NOT scaled off the quest's admin-set
 * xp_reward/duration_hours — those are one flat number per quest, and the
 * whole point here is that the same quest is worth a different amount of
 * time and XP to two different users depending on how far they are from it.
 */
export function resolvePolicyBounds(_quest: QuestPolicyInputs, limits: PolicyLimits): PolicyBounds {
  const minDurationMinutes = limits.globalMinDurationMinutes;
  const maxDurationMinutes = Math.max(minDurationMinutes, limits.globalMaxDurationMinutes);
  const minXp = Math.max(0, limits.globalMinXp);
  const maxXp = Math.max(minXp, limits.globalMaxXp);

  return {
    minDurationMinutes,
    maxDurationMinutes,
    minXp,
    maxXp,
    approveThreshold: limits.approveThreshold,
    rejectThreshold: limits.rejectThreshold,
  };
}

export interface RewardShapeInputs {
  /** Network-measured metres between the user and the destination; null when unknown or the quest has no destination. */
  readonly distanceMeters: number | null;
  readonly hasDestination: boolean;
  readonly category: string;
  readonly difficulty: string;
  readonly participantCount: number;
}

/** Travel bands the time and XP curves both key off. */
function travelBand(input: RewardShapeInputs): 'none' | 'local' | 'city' | 'regional' | 'far' | 'unknown' {
  if (!input.hasDestination) return 'none';
  if (input.distanceMeters === null) return 'unknown';
  if (input.distanceMeters < 5_000) return 'local';
  if (input.distanceMeters < 50_000) return 'city';
  if (input.distanceMeters < 500_000) return 'regional';
  return 'far';
}

/**
 * The deterministic time curve — used directly when the AI is disabled or
 * fails, and as the anchor the model is told to reason around.
 *
 * Shape: a quest you can do at home gets the 4-hour floor; something you
 * have to learn, research or watch gets 8; visiting a place in your city
 * gets a day; a regional trip (a mountain hike, say) gets ~3 days; and
 * genuine long-distance travel gets a week. Two weeks is the ceiling and
 * only difficulty pushes anything that far.
 */
export function deterministicQuestMinutes(input: RewardShapeInputs, bounds: PolicyBounds): number {
  const hour = 60;
  const baseByTravel: Record<ReturnType<typeof travelBand>, number> = {
    none: 4 * hour,
    local: 12 * hour,
    city: 24 * hour,
    regional: 72 * hour,
    far: 168 * hour,
    unknown: 24 * hour,
  };
  let minutes = baseByTravel[travelBand(input)];

  // Learning, research and creative work take time even with no travel.
  const category = input.category.toLowerCase();
  if (category === 'learning' || category === 'creativity') {
    minutes = Math.max(minutes, 8 * hour);
  }

  const difficulty = input.difficulty.toLowerCase();
  if (difficulty === 'medium') minutes *= 1.5;
  if (difficulty === 'hard') minutes *= 2.5;

  // Coordinating other people costs a day on top.
  if (input.participantCount > 1) minutes += 24 * hour;

  return clampDurationMinutes(minutes, bounds);
}

/**
 * The deterministic XP curve: 5 for something simple done at home, up to
 * 100 for a hard quest someone genuinely travelled for.
 */
export function deterministicXp(input: RewardShapeInputs, bounds: PolicyBounds): number {
  const xpByTravel: Record<ReturnType<typeof travelBand>, number> = {
    none: 0,
    local: 5,
    city: 15,
    regional: 35,
    far: 60,
    unknown: 10,
  };
  const difficulty = input.difficulty.toLowerCase();
  const difficultyXp = difficulty === 'hard' ? 25 : difficulty === 'medium' ? 10 : 0;
  const collaborationXp = input.participantCount > 1 ? 5 : 0;

  return clampXp(bounds.minXp + xpByTravel[travelBand(input)] + difficultyXp + collaborationXp, bounds);
}

export function clampDurationMinutes(recommended: number, bounds: PolicyBounds): number {
  return clamp(Math.round(recommended), bounds.minDurationMinutes, bounds.maxDurationMinutes);
}

export function clampXp(recommended: number, bounds: PolicyBounds): number {
  return clamp(Math.round(recommended), bounds.minXp, bounds.maxXp);
}

export interface MandatoryEvidenceCheck {
  readonly capability: MandatoryCapability;
  readonly present: boolean;
  readonly supports: boolean;
}

/** True only when every mandatory capability was collected and SUPPORTED — missing/stale/contradicted fails it. */
export function mandatoryEvidenceSatisfied(evidence: readonly NetworkEvidence[]): boolean {
  return MANDATORY_CAPABILITIES.every((capability) => {
    const match = evidence.find((item) => item.capability === capability);
    return Boolean(match) && match?.outcome === 'SUPPORTED';
  });
}

export type MandatoryEvidenceStatus = 'SUPPORTED' | 'CONTRADICTED' | 'UNAVAILABLE';

export function mandatoryEvidenceStatus(evidence: readonly NetworkEvidence[]): MandatoryEvidenceStatus {
  const mandatory = MANDATORY_CAPABILITIES.map((capability) =>
    evidence.find((item) => item.capability === capability),
  );
  if (mandatory.some((item) => !item || item.outcome === 'UNAVAILABLE' || item.outcome === 'ERROR')) {
    return 'UNAVAILABLE';
  }
  return mandatory.every((item) => item?.outcome === 'SUPPORTED') ? 'SUPPORTED' : 'CONTRADICTED';
}

/** The quest's resolved verification contract (#47, migration 0034). */
export interface VerificationContract {
  readonly verifiability: 'content' | 'provenance_only' | 'none';
  readonly mayAutoApprove: boolean;
  readonly mayAutoReject: boolean;
}

export interface FinalizeDecisionInput {
  readonly modelDecision: VerificationDecision;
  readonly isLocationBased: boolean;
  readonly mandatoryStatus: MandatoryEvidenceStatus;
  readonly cvAvailable: boolean;
  /**
   * How much the submitted media had to do with the quest, when the vision
   * pass assessed it. Null means not assessed, which is the correct state for
   * any quest a photograph cannot show — never "irrelevant".
   */
  readonly cvRelevance: number | null;
  /**
   * Whether the measured provenance forbids an automated approval — a capture
   * time outside the quest window, a duplicate of someone else's proof, a
   * screenshot, a generated-content marker.
   *
   * A measurement, not an opinion, which is why it is a gate here rather than
   * a consideration in the prompt.
   */
  readonly cvBlocksApproval: boolean;
  readonly contract: VerificationContract;
  readonly minRelevance: number;
  readonly bounds: PolicyBounds;
}

/**
 * The backend's final say over the model's proposed decision. Overrides
 * APPROVED to HUMAN_REVIEW whenever mandatory location evidence is missing
 * or confidence sits below the configured threshold — the model recommends,
 * this function decides what is safe to trust.
 *
 * Takes one object rather than positional arguments because it now weighs
 * eight things, and `finalizeDecision(d, true, 'SUPPORTED', true, 0.9, c, 0.35, b)`
 * is a call nobody can read or safely reorder.
 *
 * The gates are ordered cheapest-and-most-absolute first, and every one of
 * them can only move a decision *towards* HUMAN_REVIEW. Nothing here can turn
 * a HUMAN_REVIEW into an action, which is the property that makes it safe to
 * keep adding gates.
 */
export function finalizeDecision(input: FinalizeDecisionInput): VerificationDecision {
  const { modelDecision, contract, bounds } = input;

  // The quest's own contract first, because it is the only gate that does not
  // depend on any evidence having been gathered — and because it is where the
  // catalogue's central awkwardness lives. `may_auto_reject` is seeded false
  // for every category deliberately (migration 0034): authority over telling
  // a player their proof is fake is earned from a measured precision number,
  // not asserted by enabling a feature. Without this gate the agent path
  // bypassed that decision entirely, which would have made the seeding
  // decorative.
  if (modelDecision.decision === 'REJECTED' && !contract.mayAutoReject) {
    return humanReview(
      modelDecision,
      "This quest's verification contract does not permit automated rejection, so a moderator decides.",
    );
  }
  if (modelDecision.decision === 'APPROVED' && !contract.mayAutoApprove) {
    return humanReview(
      modelDecision,
      "This quest's verification contract does not permit automated approval, so a moderator decides.",
    );
  }

  // No vision pass ran, so nobody looked at the media and the media cannot
  // decide anything.
  //
  // The network still can, and that is the one carve-out. A geofence that was
  // live for the whole quest window and never fired is a measurement about
  // where the device was, arrived at without looking at any photograph — so a
  // rejection resting on it does not need one. Refusing to act there sent the
  // single most conclusive piece of evidence the system collects to a human
  // for confirmation it could not improve on.
  const networkDecides = input.isLocationBased
    && input.mandatoryStatus === 'CONTRADICTED'
    && modelDecision.decision === 'REJECTED';
  if (!input.cvAvailable && !networkDecides) {
    return humanReview(
      modelDecision,
      'Computer-vision evidence is unavailable; the agent may not decide the submitted media without it.',
    );
  }

  // A rejection on a quest the media is supposed to settle has to rest on the
  // media actually having been assessed. cvRelevance null here means the
  // vision pass ran but produced no read on how much this media has to do
  // with the quest — which is the state the model is told to escalate, and
  // enforcing it means a confident-sounding rejection can never rest on the
  // model's unassisted impression of an image it saw only through someone
  // else's notes.
  if (
    modelDecision.decision === 'REJECTED'
    && contract.verifiability === 'content'
    && input.cvRelevance === null
    && !networkDecides
  ) {
    return humanReview(
      modelDecision,
      'This quest is judged on what the media shows, and no relevance assessment of the media was produced; '
      + 'a rejection may not rest on an unassessed image.',
    );
  }

  // The media-relevance gate, and the reason the agent can no longer approve a
  // submission on the strength of a file having been attached. Applied ONLY
  // where the contract says content can decide: for the third of the catalogue
  // a photograph cannot establish — "spend an hour with no phone" — low
  // relevance is what honest proof looks like, and gating on it there would
  // punish exactly the players it is meant to protect.
  //
  // One-directional on purpose. Low relevance can stop an approval; it can
  // never produce a rejection, because "this photo has little to do with the
  // quest" and "this player cheated" are different claims and only the first
  // is supported by the number.
  // Provenance keeps its veto over an approval, on every quest.
  //
  // proof-policy.ts treats these measurements as absolute: a decisive finding
  // ends the matter before any model opinion is considered, and a strong one
  // vetoes a model's 'pass'. That cascade no longer acts when the agent
  // pipeline is the decider, so without this gate the decision moved to the
  // one path that treated a *measured* provenance failure as a suggestion the
  // model could overrule — and every content category is seeded
  // may_auto_approve = true. A photograph downloaded from the feed genuinely
  // shows a sunrise; the thing that knows it is not this player's photograph
  // is the byte hash, not the model.
  //
  // Approval only. A rejection stays out of reach here: rejection authority
  // belongs to the quest contract (gated above) and, as with unavailable
  // location evidence, a measurement that something is wrong with the file is
  // grounds to ask a human, not to accuse the player.
  //
  // Unlike the relevance gate this applies to every verifiability, because
  // authenticity is the *only* question for provenance_only and none quests —
  // it would be perverse to skip the check exactly where it is the whole
  // basis of the decision.
  if (modelDecision.decision === 'APPROVED' && input.cvBlocksApproval) {
    return humanReview(
      modelDecision,
      'The deterministic provenance checks on the submitted file forbid an automated approval; a moderator decides.',
    );
  }

  if (
    modelDecision.decision === 'APPROVED'
    && contract.verifiability === 'content'
    && input.cvRelevance !== null
    && input.cvRelevance < input.minRelevance
  ) {
    return humanReview(
      modelDecision,
      `The submitted media scored ${input.cvRelevance.toFixed(2)} for relevance to this quest, below the `
      + `${input.minRelevance.toFixed(2)} floor required to approve automatically. A moderator decides.`,
    );
  }

  if (modelDecision.conflicts.length > 0) {
    return humanReview(
      modelDecision,
      modelDecision.humanReviewReason ?? 'The collected evidence conflicts and requires a human decision.',
    );
  }
  if (input.isLocationBased && input.mandatoryStatus === 'UNAVAILABLE') {
    return humanReview(
      modelDecision,
      'Mandatory location evidence (Location Verification, Location Retrieval, Geofencing) is unavailable; provider failure must not become a rejection.',
    );
  }
  if (input.isLocationBased && input.mandatoryStatus !== 'SUPPORTED' && modelDecision.decision === 'APPROVED') {
    return humanReview(
      modelDecision,
      'Mandatory location evidence contradicts completion; the agent may not approve it.',
    );
  }
  if (modelDecision.decision === 'APPROVED' && modelDecision.confidence < bounds.approveThreshold) {
    return humanReview(
      modelDecision,
      modelDecision.humanReviewReason ?? 'Confidence below the approval threshold.',
    );
  }
  if (modelDecision.decision === 'REJECTED' && modelDecision.confidence < bounds.rejectThreshold) {
    return humanReview(
      modelDecision,
      modelDecision.humanReviewReason ?? 'Confidence below the rejection threshold.',
    );
  }
  return modelDecision;
}

function humanReview(decision: VerificationDecision, reason: string): VerificationDecision {
  return { ...decision, decision: 'HUMAN_REVIEW', humanReviewReason: reason };
}
