/// The closed set of quest categories.
///
/// The `quests_category_check` and `quest_suggestions_category_check`
/// constraints (migration 0027) are the guard; these values exist so a DTO can
/// refuse an illegal one with a 400 instead of letting a 23514 surface as a
/// 500. Keep them identical to `QuestCategory` in
/// `packages/app_contracts/lib/statuses.dart`, which is what the apps switch
/// on — `backend/test/quest-category.spec.ts` fails if the two drift.
///
/// Adding a category means: migration first, then this list, then
/// `statuses.dart`, then the clients that colour and label it.
export const QUEST_CATEGORIES = ['fitness', 'creativity', 'social', 'learning', 'adventure'] as const;

export type QuestCategory = (typeof QUEST_CATEGORIES)[number];

/// Folds the incoming value the way migration 0027 folded the existing rows,
/// so 'Fitness ' is accepted rather than rejected on a capital letter. Applied
/// as a class-transformer `@Transform` ahead of `@IsIn`; non-strings pass
/// through untouched for `@IsIn` to reject.
export function normaliseQuestCategory(value: unknown): unknown {
  return typeof value === 'string' ? value.trim().toLowerCase() : value;
}
