/**
 * A multi-step quest as the player experiences it: a line of milestones,
 * where exactly one is reachable and the rest are earned or still dark.
 *
 * The state lives here rather than being inferred by the client because
 * "reachable" is the whole rule. A step opens only when the previous one has
 * APPROVED proof — not submitted, not pending — and approval is something
 * only the server has seen. A client that guessed would show an unlockable
 * milestone that refuses when tapped, which is worse than showing it locked.
 */
export type MilestoneState =
  /** Approved. Behind the player. */
  | 'COMPLETE'
  /** Awaiting a decision on submitted proof. */
  | 'IN_REVIEW'
  /** The one step the player may take right now. */
  | 'CURRENT'
  /** Not yet reachable: the step before it is unfinished. */
  | 'LOCKED';

export interface JourneyMilestone {
  readonly questId: string;
  readonly stepOrder: number;
  readonly state: MilestoneState;
  /**
   * Withheld while LOCKED on a hidden chain — the point of a discovery chain
   * is that you do not know what is at the end. Present otherwise.
   */
  readonly title: string | null;
  readonly xpReward: number;
  /** Where this step happens, when it is somewhere. */
  readonly placeName: string | null;
  readonly countryName: string | null;
  /**
   * Whether finishing this step needs network-verified presence. Declared per
   * step because a chain can mix: reach the castle (verified), then tell us
   * what you saw (not).
   */
  readonly requiresLocationVerification: boolean;
  /** Who completed it, for a relay. Null on a solo chain. */
  readonly completedBy: string | null;
}

export interface QuestJourney {
  readonly chainId: string;
  readonly name: string;
  readonly description: string;
  /** `solo` — one player walks it. `group` — a relay across a collab group. */
  readonly mode: 'solo' | 'group';
  /** `sequential` — order matters. `all_steps_any_order` — a cross-country set. */
  readonly completionRule: 'sequential' | 'all_steps_any_order';
  readonly milestones: readonly JourneyMilestone[];
  readonly completedSteps: number;
  readonly totalSteps: number;
}
