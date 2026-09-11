/** A quest as a discovery surface shows it: enough to decide, not the whole row. */
export interface DiscoveryQuestCard {
  readonly id: string;
  readonly title: string;
  readonly description: string;
  readonly category: string;
  readonly difficulty: string;
  readonly xpReward: number;
  readonly durationHours: number;
  /** Present only for destination quests. */
  readonly destination: {
    readonly placeId: string;
    readonly placeName: string;
    readonly city: string;
    readonly countryCode: string;
    readonly countryName: string;
    readonly latitude: number;
    readonly longitude: number;
    readonly requiresVerification: boolean;
  } | null;
  /**
   * Short mechanic labels for the card — HIDDEN, LIMITED, 3 STAGES, PARTNER.
   * Computed server-side so the client never has to infer a mechanic from a
   * combination of columns, and so the two can never disagree about what a
   * quest is.
   */
  readonly badges: readonly string[];
  /** Community participation, when the channel ranked on it. */
  readonly signal: { readonly completions: number; readonly netScore: number } | null;
}

/** The module types Home can render. Empty modules are never serialised. */
export type HomeModuleType =
  | 'CONTINUE_JOURNEY'
  | 'MULTI_STAGE'
  | 'HIDDEN_DISCOVERED'
  | 'LIMITED_TIME'
  | 'WORTH_THE_TRIP'
  | 'TRENDING'
  | 'NEAR_YOU'
  | 'EXPLORE_COUNTRY'
  | 'FEATURED_PARTNER';

export interface HomeModule {
  readonly type: HomeModuleType;
  /** Display title, resolved server-side so "EXPLORE QATAR" can name a country. */
  readonly title: string;
  readonly subtitle: string | null;
  readonly items: readonly DiscoveryQuestCard[];
  /** Collections, for CONTINUE_JOURNEY. */
  readonly journeys: readonly JourneyProgress[];
}

/**
 * A journey card on Home, from either of two different backend concepts.
 *
 * `kind` is the discriminator, and it exists so the two stay separate in the
 * database while reading as one shelf to a player. A chain is ordered
 * progression with dependencies; a collection is a themed grouping with no
 * ordering. Merging the tables would lose that distinction; merging only the
 * PRESENTATION is what lets Home say "continue your journey" about both.
 */
export interface JourneyProgress {
  /** 'chain' — a multi-stage run. 'collection' — a themed set. */
  readonly kind: 'chain' | 'collection';
  /** Present on a chain: the run to continue, and whether this user can. */
  readonly runId?: string;
  readonly canContinue?: boolean;
  readonly nextCheckpointName?: string | null;
  readonly hasUnseenUnlock?: boolean;
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly countryCode: string | null;
  readonly countryName: string | null;
  readonly totalQuests: number;
  readonly completedQuests: number;
}

/**
 * How many items a module is worth showing.
 *
 * A carousel with one card looks broken, so a module that cannot reach its
 * minimum is dropped rather than rendered thin — that is the rule that keeps
 * Home from turning into five rows of one item each.
 */
export const MODULE_LIMITS: Record<HomeModuleType, { min: number; max: number }> = {
  CONTINUE_JOURNEY: { min: 1, max: 3 },
  // min 1: a single multi-stage quest is still worth showing. This shelf is
  // the only place the mechanic is discoverable at all, and dropping it for
  // thinness is what made multi-level quests invisible to every new account.
  MULTI_STAGE: { min: 1, max: 5 },
  HIDDEN_DISCOVERED: { min: 1, max: 3 },
  LIMITED_TIME: { min: 1, max: 5 },
  WORTH_THE_TRIP: { min: 2, max: 5 },
  TRENDING: { min: 2, max: 5 },
  NEAR_YOU: { min: 2, max: 5 },
  EXPLORE_COUNTRY: { min: 2, max: 5 },
  FEATURED_PARTNER: { min: 1, max: 2 },
};

/**
 * Which modules outrank which when more qualify than Home should show.
 *
 * Ordered by how much the user has already invested: something they started
 * beats something they found, which beats something expiring, which beats
 * editorial recommendation. A sponsored placement is last on purpose — it may
 * appear, but it may never crowd out the things the user actually chose.
 */
export const MODULE_PRIORITY: readonly HomeModuleType[] = [
  'CONTINUE_JOURNEY',
  'MULTI_STAGE',
  'HIDDEN_DISCOVERED',
  'LIMITED_TIME',
  'WORTH_THE_TRIP',
  'TRENDING',
  'NEAR_YOU',
  'EXPLORE_COUNTRY',
  'FEATURED_PARTNER',
];

/** Home shows at most this many discovery modules below the roll and QOTD. */
export const MAX_HOME_MODULES = 5;
