DateTime toLocalDateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

Set<DateTime> uniqueLocalDates(Iterable<DateTime> timestamps) {
  return timestamps.map(toLocalDateOnly).toSet();
}

int calculateCurrentStreakFromTimestamps(
  Iterable<DateTime> timestamps, {
  DateTime? now,
}) {
  final dates = uniqueLocalDates(timestamps).toList()
    ..sort((a, b) => b.compareTo(a));
  if (dates.isEmpty) return 0;

  final current = toLocalDateOnly(now ?? DateTime.now());
  final yesterday = current.subtract(const Duration(days: 1));
  if (dates.first.isBefore(yesterday)) return 0;

  var streak = 1;
  for (var i = 0; i < dates.length - 1; i++) {
    if (dates[i].difference(dates[i + 1]).inDays == 1) {
      streak++;
    } else {
      break;
    }
  }
  return streak;
}
