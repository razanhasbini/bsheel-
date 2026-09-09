/// The rank ladder the frames print under the XP meter and beside every
/// username: SCOUT → WARRIOR → MAGE → CHAMPION → LEGEND.
///
/// Lives here rather than inside a page because three screens render it —
/// the profile panel (`export/mobile/12-profile.jpg`), every leaderboard row
/// (`13-leaderboard.jpg`) and every people result (`18-search.jpg`) — and
/// they were drifting apart when each kept its own copy.
library;

const List<String> playerClassLadder = <String>[
  'SCOUT',
  'WARRIOR',
  'MAGE',
  'CHAMPION',
  'LEGEND',
];

/// The class name for [level]. Boundaries match the ladder the design draws.
String playerClassForLevel(int level) {
  if (level <= 5) return 'SCOUT';
  if (level <= 10) return 'WARRIOR';
  if (level <= 20) return 'MAGE';
  if (level <= 35) return 'CHAMPION';
  return 'LEGEND';
}
