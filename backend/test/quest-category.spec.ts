// Nest's entrypoints import this for their whole process; a unit test that
// instantiates a DTO has to do it itself, or class-transformer's @Type has no
// Reflect.getMetadata to call.
import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { InjectQuestDto } from '../src/modules/admin/presentation/admin.dto.js';
import { SubmitQuestSuggestionDto } from '../src/modules/public-intake/presentation/public-intake.dto.js';
import { QUEST_CATEGORIES } from '../src/modules/quests/domain/quest-category.js';
import { CreateQuestDto, UpdateQuestDto } from '../src/modules/quests/presentation/quest.dto.js';

/// The DTO half of the closed quest-category set.
///
/// The `quests_category_check` constraint is the guard; these tests are about
/// the other half of the contract — that a caller who sends a category nobody
/// recognises gets a 400 naming the legal values rather than a 500 out of a
/// 23514 nothing maps to a status code.

const categoryErrors = <T extends object>(type: new () => T, payload: Record<string, unknown>) =>
  validateSync(plainToInstance(type, payload) as object).filter((error) => error.property === 'category');

const createQuest = (category: unknown) => ({
  title: 'Walk somewhere new',
  description: 'Pick a street you have never walked down and follow it.',
  category,
  difficulty: 'easy',
  xpReward: 15,
  durationHours: 4,
  isActive: true,
});

describe('quest category is a closed set', () => {
  it('is the same five values the clients switch on', () => {
    // packages/app_contracts/lib/statuses.dart is the client's source of
    // truth and its own comment calls these "Quest category CHECK constraint
    // values". Reading it here is the only thing that keeps that claim and
    // migration 0027 from drifting apart silently.
    const dart = readFileSync(new URL('../../packages/app_contracts/lib/statuses.dart', import.meta.url), 'utf8');
    const block = /abstract final class QuestCategory \{(?<body>[^}]*)\}/.exec(dart)?.groups?.body;
    expect(block, 'QuestCategory not found in statuses.dart').toBeTruthy();
    const declared = [...(block as string).matchAll(/=\s*'(?<value>[^']+)'/g)].map((match) => match.groups!.value);

    expect(declared).toEqual([...QUEST_CATEGORIES]);
  });

  it.each([...QUEST_CATEGORIES])('accepts %s', (category) => {
    expect(categoryErrors(CreateQuestDto, createQuest(category))).toEqual([]);
  });

  it.each([
    ['sports', 'a plausible category nobody implemented'],
    ['creative', 'the near-miss spelling of creativity that was already in the data'],
    ['e2e', 'the fixture string the integration harness used to insert'],
    ['', 'empty'],
    ['fitness,social', 'two at once'],
  ])('rejects %s (%s)', (category) => {
    expect(categoryErrors(CreateQuestDto, createQuest(category))).not.toEqual([]);
  });

  it.each([[42], [null], [['fitness']], [{ value: 'fitness' }]])('rejects the non-string %s', (category) => {
    expect(categoryErrors(CreateQuestDto, createQuest(category))).not.toEqual([]);
  });

  it('folds case and surrounding whitespace rather than refusing on it', () => {
    const dto = plainToInstance(CreateQuestDto, createQuest('  Fitness \n'));
    expect(validateSync(dto).filter((error) => error.property === 'category')).toEqual([]);
    expect(dto.category).toBe('fitness');
  });

  it('closes the update path too, and still treats category as optional there', () => {
    expect(categoryErrors(UpdateQuestDto, { category: 'adventure' })).toEqual([]);
    expect(categoryErrors(UpdateQuestDto, {})).toEqual([]);
    expect(categoryErrors(UpdateQuestDto, { category: 'sports' })).not.toEqual([]);
  });

  it('closes the admin injection path, which writes a quests row like any other', () => {
    const injection = {
      targetUserId: '00000000-0000-4000-8000-000000000001',
      title: 'Injected quest',
      description: 'Handed straight to one user.',
      difficulty: 'easy',
      xpReward: 25,
      durationHours: 4,
    };
    expect(categoryErrors(InjectQuestDto, { ...injection, category: 'social' })).toEqual([]);
    expect(categoryErrors(InjectQuestDto, { ...injection, category: 'sports' })).not.toEqual([]);
  });

  it('keeps the public suggestion intake closed, since approval copies its category into quests', () => {
    const suggestion = {
      title: 'Watch the sunrise',
      description: 'Be outside before the sun is up and photograph first light.',
      difficulty: 'medium',
    };
    expect(categoryErrors(SubmitQuestSuggestionDto, { ...suggestion, category: 'adventure' })).toEqual([]);
    expect(categoryErrors(SubmitQuestSuggestionDto, { ...suggestion, category: 'sports' })).not.toEqual([]);
  });
});
