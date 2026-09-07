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
    DateTime parseDate(dynamic v) {
      if (v is String) return DateTime.parse(v);
      if (v is DateTime) return v;
      throw ArgumentError('Bad display_date type: ${v.runtimeType}');
    }

    // Defensive numeric coercion: Supabase RPC payloads have surfaced
    // integer-typed columns as `num`/`double` in some SDK versions, which
    // makes a strict `as int?` cast throw. Any error here propagates up
    // to the provider's catch block and silently hides the entire QOTD
    // widget, so we accept any numeric type and round.
    int parseInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    return QuestOfTheDayModel(
      id: row['id'] as String,
      displayDate: parseDate(row['display_date']),
      ticketNo: row['ticket_no'] as String?,
      bonusXp: parseInt(row['bonus_xp']),
      questId: row['quest_id'] as String,
      questTitle: (row['quest_title'] as String?) ?? '',
      questDescription: (row['quest_description'] as String?) ?? '',
      questCategory: (row['quest_category'] as String?) ?? '',
      questDifficulty: (row['quest_difficulty'] as String?) ?? 'medium',
      questXpReward: parseInt(row['quest_xp_reward']),
      questDurationHours: parseInt(row['quest_duration_hours'], 4),
    );
  }
}
