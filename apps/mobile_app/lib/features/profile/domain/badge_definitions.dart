import 'package:flutter/material.dart';
import 'package:app_models/app_models.dart';

/// Rarity tiers for badges.
enum BadgeRarity {
  common('COMMON'),
  rare('RARE'),
  epic('EPIC'),
  legendary('LEGENDARY');

  const BadgeRarity(this.label);
  final String label;
}

/// Defines a badge with its unlock condition.
class BadgeDefinition {
  BadgeDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.rarity,
    required this.icon,
    required this.isUnlocked,
    required this.currentValue,
    required this.targetValue,
  });

  final String id;
  final String label;
  final String description;
  final BadgeRarity rarity;
  final IconData icon;

  final bool Function({
    required ProfileModel profile,
    required int streak,
    required int socialQuestCount,
  }) isUnlocked;

  /// Returns current progress value toward this badge.
  final int Function({
    required ProfileModel profile,
    required int streak,
    required int socialQuestCount,
  }) currentValue;

  /// Target value to unlock.
  final int targetValue;
}

/// All badge definitions for the app.
final _badges = <BadgeDefinition>[
  BadgeDefinition(
    id: 'first_quest',
    label: 'FIRST QUEST',
    description: 'Complete your first quest',
    rarity: BadgeRarity.common,
    icon: Icons.emoji_events_outlined,
    isUnlocked: _firstQuest,
    targetValue: 1,
    currentValue: ({required profile, required streak, required socialQuestCount}) => profile.questsCompleted,
  ),
  BadgeDefinition(
    id: 'fire_starter',
    label: 'FIRE STARTER',
    description: 'Complete 5 quests',
    rarity: BadgeRarity.rare,
    icon: Icons.local_fire_department,
    isUnlocked: _fireStarter,
    targetValue: 5,
    currentValue: ({required profile, required streak, required socialQuestCount}) => profile.questsCompleted,
  ),
  BadgeDefinition(
    id: 'level_10',
    label: 'LEVEL 10',
    description: 'Reach level 10',
    rarity: BadgeRarity.rare,
    icon: Icons.shield_outlined,
    isUnlocked: _level10,
    targetValue: 10,
    currentValue: ({required profile, required streak, required socialQuestCount}) => profile.level,
  ),
  BadgeDefinition(
    id: 'streak_master',
    label: 'STREAK MASTER',
    description: 'Achieve a 7-day streak',
    rarity: BadgeRarity.epic,
    icon: Icons.bolt,
    isUnlocked: _streakMaster,
    targetValue: 7,
    currentValue: ({required profile, required streak, required socialQuestCount}) => streak,
  ),
  BadgeDefinition(
    id: 'social_butterfly',
    label: 'SOCIAL BUTTERFLY',
    description: 'Complete 3 social quests',
    rarity: BadgeRarity.rare,
    icon: Icons.people_outline,
    isUnlocked: _socialButterfly,
    targetValue: 3,
    currentValue: ({required profile, required streak, required socialQuestCount}) => socialQuestCount,
  ),
  BadgeDefinition(
    id: 'xp_hunter',
    label: 'XP HUNTER',
    description: 'Earn 500+ XP',
    rarity: BadgeRarity.rare,
    icon: Icons.star_outline,
    isUnlocked: _xpHunter,
    targetValue: 500,
    currentValue: ({required profile, required streak, required socialQuestCount}) => profile.xp,
  ),
  BadgeDefinition(
    id: 'legend',
    label: 'LEGEND',
    description: 'Reach level 36',
    rarity: BadgeRarity.legendary,
    icon: Icons.military_tech,
    isUnlocked: _legend,
    targetValue: 36,
    currentValue: ({required profile, required streak, required socialQuestCount}) => profile.level,
  ),
];

/// Public accessor for all badge definitions.
List<BadgeDefinition> get allBadges => _badges;

// ── Unlock functions ────────────────────────────────────────────────────────

bool _firstQuest({
  required ProfileModel profile,
  required int streak,
  required int socialQuestCount,
}) =>
    profile.questsCompleted >= 1;

bool _fireStarter({
  required ProfileModel profile,
  required int streak,
  required int socialQuestCount,
}) =>
    profile.questsCompleted >= 5;

bool _level10({
  required ProfileModel profile,
  required int streak,
  required int socialQuestCount,
}) =>
    profile.level >= 10;

bool _streakMaster({
  required ProfileModel profile,
  required int streak,
  required int socialQuestCount,
}) =>
    streak >= 7;

bool _socialButterfly({
  required ProfileModel profile,
  required int streak,
  required int socialQuestCount,
}) =>
    socialQuestCount >= 3;

bool _xpHunter({
  required ProfileModel profile,
  required int streak,
  required int socialQuestCount,
}) =>
    profile.xp >= 500;

bool _legend({
  required ProfileModel profile,
  required int streak,
  required int socialQuestCount,
}) =>
    profile.level >= 36;
