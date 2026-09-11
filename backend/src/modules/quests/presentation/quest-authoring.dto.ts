import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize, ArrayMinSize, IsArray, IsBoolean, IsIn, IsInt, IsISO8601,
  IsOptional, IsString, IsUUID, Length, Max, Min, ValidateNested,
} from 'class-validator';
import { QUEST_CATEGORIES, normaliseQuestCategory, type QuestCategory } from '../domain/quest-category.js';

/**
 * The authoring surface, as opposed to `CreateQuestDto`.
 *
 * `CreateQuestDto` is the narrow shape the bulk importer uses and it stays
 * that way; this one carries every dimension a quest actually has. They are
 * separate because the dimensions are COMPOSABLE, not alternatives: a quest
 * can be hidden AND time-limited AND at a destination AND step 2 of a chain
 * all at once. An enum of "quest types" cannot express that, and the whole
 * catalogue design rests on it not being one.
 */
export class QuestDestinationDto {
  @IsUUID() placeId!: string;

  /**
   * Whether the carrier has to confirm the player is there.
   *
   * Checked at SUBMISSION, never at assignment — somebody in Beirut must be
   * able to accept a quest in Doha before they fly. Defaulting to true means
   * a destination quest is verified unless someone deliberately says
   * otherwise.
   */
  @IsOptional() @IsBoolean() requiresVerification = true;
}

export class QuestUnlockRuleDto {
  @IsIn(['country_entered', 'place_entered', 'prerequisite_quest', 'collection_progress', 'date_event'])
  unlockType!: string;

  @IsOptional() @IsString() @Length(2, 2) countryCode?: string;
  @IsOptional() @IsUUID() placeId?: string;
  @IsOptional() @IsUUID() prerequisiteQuestId?: string;
  @IsOptional() @IsUUID() collectionId?: string;
  @IsOptional() @IsInt() @Min(1) @Max(500) threshold?: number;
}

export class AuthorQuestDto {
  @IsString() @Length(1, 160) title!: string;
  @IsString() @Length(1, 2000) description!: string;

  @Transform(({ value }) => normaliseQuestCategory(value))
  @IsIn(QUEST_CATEGORIES)
  category!: QuestCategory;

  @IsIn(['easy', 'medium', 'hard']) difficulty!: string;

  @IsInt() @Min(0) @Max(10_000) xpReward!: number;
  @IsInt() @Min(1) @Max(168) durationHours = 4;
  @IsOptional() @IsBoolean() isActive = true;

  /**
   * Withheld until an unlock rule fires. Never offered by the roll.
   *
   * Deliberately NOT defaulted here. A class property initializer runs
   * during transformation, so `= false` would make an omitted field
   * indistinguishable from an explicit `false` — and the chain builder
   * needs that distinction to default later steps to hidden while still
   * honouring an author who wants a visible one. The default lives at the
   * insert instead.
   */
  @IsOptional() @IsBoolean() isHidden?: boolean;

  /** `flagship` is the editorial "worth the trip" tier. */
  @IsOptional() @IsIn(['standard', 'flagship']) editorialTier = 'standard';

  /** False keeps a quest out of every browse surface without deactivating it. */
  @IsOptional() @IsBoolean() isGloballyDiscoverable = true;

  /** The limited-time window. Both null means it never expires. */
  @IsOptional() @IsISO8601() availableFrom?: string;
  @IsOptional() @IsISO8601() availableUntil?: string;

  /** Display credit only — partner ACCOUNTS are a separate product. */
  @IsOptional() @IsString() @Length(1, 120) sponsorName?: string;
  @IsOptional() @IsUUID() partnerId?: string;

  @IsOptional() @ValidateNested() @Type(() => QuestDestinationDto)
  destination?: QuestDestinationDto;

  /**
   * What opens this quest, when it is hidden. Multiple rules are OR-ed, so a
   * landmark can be reached either by going there or by finishing the chain
   * that leads to it.
   */
  @IsOptional() @IsArray() @ArrayMaxSize(10)
  @ValidateNested({ each: true }) @Type(() => QuestUnlockRuleDto)
  unlockRules?: QuestUnlockRuleDto[];

  /** Collections/journeys this quest counts towards. */
  @IsOptional() @IsArray() @ArrayMaxSize(20) @IsUUID('4', { each: true })
  collectionIds?: string[];
}

/**
 * A whole multi-stage quest, authored in one call.
 *
 * Steps have to be created together and in one transaction: a chain with
 * three quests and two steps recorded is a quest that dead-ends, and a step
 * pointing at a quest that failed to insert is worse. Either the whole
 * journey exists or none of it does.
 */
export class AuthorChainDto {
  @IsString() @Length(1, 160) name!: string;
  @IsOptional() @IsString() @Length(0, 2000) description = '';

  /** `solo` — one player walks it. `group` — a relay across a collab group. */
  @IsOptional() @IsIn(['solo', 'group']) mode = 'solo';

  /**
   * `sequential` gates each step on the previous one's approval.
   * `all_steps_any_order` gates nothing — a cross-country challenge has no
   * reason to make Palestine wait for Lebanon.
   */
  @IsOptional() @IsIn(['sequential', 'all_steps_any_order'])
  completionRule = 'sequential';

  /** Required for a `group` relay: which collab group runs it. */
  @IsOptional() @IsUUID() collabGroupId?: string;

  /**
   * Two steps minimum, because a one-step chain is just a quest, and ten
   * maximum so one call cannot author an unbounded catalogue.
   *
   * Order is the array order. Steps after the first default to hidden unless
   * the author says otherwise — the reveal is the mechanic.
   */
  @IsArray() @ArrayMinSize(2) @ArrayMaxSize(10)
  @ValidateNested({ each: true }) @Type(() => AuthorQuestDto)
  steps!: AuthorQuestDto[];
}
