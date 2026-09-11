/** A checkpoint's state for one viewer, resolved server-side. */
/// `IN_PROGRESS` is distinct from `AVAILABLE` on purpose: a checkpoint you
/// have already started has a timer running, and offering to start it again
/// produces a button that fails. The app needs to say "return to it".
export type StageState =
  | 'COMPLETED'
  | 'UNDER_REVIEW'
  | 'IN_PROGRESS'
  | 'AVAILABLE'
  | 'LOCKED';

export type RunStatus = 'forming' | 'active' | 'completed' | 'abandoned' | 'expired';

/**
 * One checkpoint as a journey surface shows it.
 *
 * Hidden content is withheld by the QUERY, not by the client: a teammate
 * watching a relay sees that a stage is active and who is up, never a hidden
 * stage's instructions. `title` and `destination` are null in exactly that
 * case, which is why they are nullable here rather than optional decoration.
 */
export interface JourneyStage {
  readonly stepOrder: number;
  readonly questId: string | null;
  readonly state: StageState;
  readonly xpReward: number | null;
  readonly title: string | null;
  readonly description: string | null;
  readonly placeName: string | null;
  readonly countryName: string | null;
  readonly latitude: number | null;
  readonly longitude: number | null;
  readonly requiresLocationVerification: boolean;
  /** Shown on the current checkpoint, so a player knows what they are taking on. */
  readonly difficulty: string | null;
  readonly durationHours: number | null;
  /** When this checkpoint was approved. Null unless it is completed. */
  readonly completedAt: string | null;
  /** The proof that cleared it, so a finished checkpoint can be revisited. */
  readonly submissionId: string | null;
  /** Whose checkpoint this is, on a relay. Null on a solo run. */
  readonly targetUsername: string | null;
  /** True when the viewer is the one who may start it. */
  readonly isYours: boolean;
}

/** A run as the app renders it: where the journey is and what to do next. */
export interface JourneyRun {
  readonly runId: string;
  readonly chainId: string;
  readonly title: string;
  readonly description: string;
  readonly runKind: 'solo' | 'group';
  readonly completionRule: 'sequential' | 'all_steps_any_order';
  readonly status: RunStatus;
  readonly completedSteps: number;
  readonly totalSteps: number;
  readonly stages: readonly JourneyStage[];
  /**
   * The checkpoint this viewer can act on right now, if any. Null when the
   * ball is in a teammate's court, or the journey is done.
   */
  readonly nextForViewer: JourneyStage | null;
  /** An unlock this viewer has not been shown yet — drives the animation. */
  readonly unseenUnlock: { readonly stepOrder: number; readonly questId: string } | null;
}
