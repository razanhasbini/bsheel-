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

/**
 * The backend's final say over the model's proposed decision. Overrides
 * APPROVED to HUMAN_REVIEW whenever mandatory location evidence is missing
 * or confidence sits below the configured threshold — the model recommends,
 * this function decides what is safe to trust.
 */
export function finalizeDecision(
  modelDecision: VerificationDecision,
  isLocationBased: boolean,
  mandatoryStatus: MandatoryEvidenceStatus,
  cvAvailable: boolean,
  bounds: PolicyBounds,
): VerificationDecision {
  if (!cvAvailable) {
    return {
      ...modelDecision,
      decision: 'HUMAN_REVIEW',
      humanReviewReason: 'Computer-vision evidence is unavailable; the agent may not decide the submitted media without it.',
    };
  }
  if (modelDecision.conflicts.length > 0) {
    return {
      ...modelDecision,
      decision: 'HUMAN_REVIEW',
      humanReviewReason: modelDecision.humanReviewReason ?? 'The collected evidence conflicts and requires a human decision.',
    };
  }
  if (isLocationBased && mandatoryStatus === 'UNAVAILABLE') {
    return {
      ...modelDecision,
      decision: 'HUMAN_REVIEW',
      humanReviewReason:
        'Mandatory location evidence (Location Verification, Location Retrieval, Geofencing) is unavailable; provider failure must not become a rejection.',
    };
  }
  if (isLocationBased && mandatoryStatus !== 'SUPPORTED' && modelDecision.decision === 'APPROVED') {
    return {
      ...modelDecision,
      decision: 'HUMAN_REVIEW',
      humanReviewReason:
        'Mandatory location evidence contradicts completion; the agent may not approve it.',
    };
  }
  if (modelDecision.decision === 'APPROVED' && modelDecision.confidence < bounds.approveThreshold) {
    return {
      ...modelDecision,
      decision: 'HUMAN_REVIEW',
      humanReviewReason: modelDecision.humanReviewReason ?? 'Confidence below the approval threshold.',
    };
  }
  if (modelDecision.decision === 'REJECTED' && modelDecision.confidence < bounds.rejectThreshold) {
    return {
      ...modelDecision,
      decision: 'HUMAN_REVIEW',
      humanReviewReason: modelDecision.humanReviewReason ?? 'Confidence below the rejection threshold.',
    };
  }
  return modelDecision;
}
