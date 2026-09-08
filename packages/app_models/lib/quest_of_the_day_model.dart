import 'src/json_coercions.dart';

/// Row returned from the `get_quest_of_the_day` RPC (see migration 0139).
/// Mirrors the SQL TABLE return shape so we can construct directly from
/// PostgREST rows. Holds quest-detail fields inline rather than a nested
/// QuestModel because the RPC returns a flat row — avoids an extra
/// repository fetch when rendering the home-page ticket.
class QuestOfTheDayModel {
  const QuestOfTheDayModel({
    required this.id,
    required this.displayDate,
    required this.ticketNo,
    required this.bonusXp,
    required this.questId,
    required this.questTitle,
    required this.questDescription,
    required this.questCategory,
    required this.questDifficulty,
    required this.questXpReward,
    required this.questDurationHours,
  });

  final String id;
  final DateTime displayDate;
  final String? ticketNo;
  final int bonusXp;
  final String questId;
  final String questTitle;
  final String questDescription;
  final String questCategory;
  final String questDifficulty;
  final int questXpReward;
  final int questDurationHours;

  /// Total XP for this QOTD = base reward + admin-curated bonus.
  int get totalXpReward => questXpReward + bonusXp;

  /// Ticket number shown in the top-right of the widget. Falls back to a
  /// readable date-derived number (e.g. "0512") when the admin didn't
  /// override the value at write-time.
  String get displayTicketNo {
    final t = ticketNo?.trim();
    if (t != null && t.isNotEmpty) return t;
    final mm = displayDate.month.toString().padLeft(2, '0');
    final dd = displayDate.day.toString().padLeft(2, '0');
    return '$mm$dd';
  }

  factory QuestOfTheDayModel.fromRow(Map<String, dynamic> row) {
    return QuestOfTheDayModel(
      id: row['id'] as String,
      // `display_date` is required, so it degrades to the epoch rather than
      // throwing — it used to raise an ArgumentError on a non-string and a
      // FormatException on an unparseable one, and the QOTD provider's
      // catch block turns any throw here into a silently hidden widget.
      displayDate: coerceTimestamp(row['display_date']),
      ticketNo: row['ticket_no'] as String?,
      // Defensive numeric coercion: Supabase RPC payloads have surfaced
      // integer-typed columns as `num`/`double` in some SDK versions, which
      // makes a strict `as int?` cast throw. Any error here propagates up
      // to the provider's catch block and silently hides the entire QOTD
      // widget, so we accept any numeric type and round.
      bonusXp: coerceInt(row['bonus_xp']),
      questId: row['quest_id'] as String,
      questTitle: (row['quest_title'] as String?) ?? '',
      questDescription: (row['quest_description'] as String?) ?? '',
      questCategory: (row['quest_category'] as String?) ?? '',
      questDifficulty: (row['quest_difficulty'] as String?) ?? 'medium',
      questXpReward: coerceInt(row['quest_xp_reward']),
      // Clamped to the same 1..168 range as QuestModel — see
      // [normalizeQuestDurationHours]. This model used to apply no bounds
      // at all, so a 0 reached the ticket's countdown copy.
      questDurationHours:
          normalizeQuestDurationHours(row['quest_duration_hours']),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QuestOfTheDayModel &&
        other.id == id &&
        other.displayDate == displayDate &&
        other.ticketNo == ticketNo &&
        other.bonusXp == bonusXp &&
        other.questId == questId &&
        other.questTitle == questTitle &&
        other.questDescription == questDescription &&
        other.questCategory == questCategory &&
        other.questDifficulty == questDifficulty &&
        other.questXpReward == questXpReward &&
        other.questDurationHours == questDurationHours;
  }

  @override
  int get hashCode => Object.hash(
        id,
        displayDate,
        ticketNo,
        bonusXp,
        questId,
        questTitle,
        questDescription,
        questCategory,
        questDifficulty,
        questXpReward,
        questDurationHours,
      );
}
