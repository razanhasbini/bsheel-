import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_models/app_models.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../providers/leaderboard_provider.dart';
import '../../../../l10n/app_localizations.dart';
import 'package:app_core/app_core.dart';
import '../../../../design/bs_widgets.dart';

// Screen-specific colour — not a theme token.
const Color _avatarOrange = Color(0xFFFF9F1C);

// Color palette for avatar squares (cycling)
const _avatarColors = [
  QuestColors.osRed, // hot red
  QuestColors.violet, // violet
  QuestColors.osSuccess, // green
  QuestColors.accentYellow, // gold
  QuestColors.osCool, // cyan
  _avatarOrange, // orange
];

Color _avatarColor(String userId) =>
    _avatarColors[userId.hashCode.abs() % _avatarColors.length];

/// Avatar that shows the user's profile image if available, otherwise falls
/// back to a chunky coloured square with the first letter of their name.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.user,
    required this.size,
    required this.fontSize,
    required this.radius,
  });

  final LeaderboardUserModel user;
  final double size;
  final double fontSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final tint = _avatarColor(user.userId);
    final border = Border.all(
        color: QuestColors.osTextPrimary, width: QuestSpacing.cardBorderWidth);
    final radiusObj = BorderRadius.circular(radius);

    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint,
        border: border,
        borderRadius: radiusObj,
        boxShadow: const [
          BoxShadow(color: QuestColors.osTextPrimary, offset: Offset(0, 2))
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
        style: TextStyle(
          fontFamily: 'Syne',
          fontVariations: const [FontVariation('wght', 800)],
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: QuestColors.onAccent(tint),
        ),
      ),
    );

    final url = user.avatarUrl;
    if (url == null || url.isEmpty) return placeholder;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: border,
        borderRadius: radiusObj,
        boxShadow: const [
          BoxShadow(color: QuestColors.osTextPrimary, offset: Offset(0, 2))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: size,
          height: size,
          // Cap in-memory decode at 2x size for retina; prevents megabyte
          // avatars in scrollable leaderboard. Only width — height derives
          // from source aspect so non-square avatar uploads aren't stretched.
          memCacheWidth: (size * 2).round(),
          placeholder: (_, __) => Container(color: tint),
          errorWidget: (_, __, ___) => placeholder,
        ),
      ),
    );
  }
}

class LeaderboardPage extends ConsumerStatefulWidget {
  const LeaderboardPage({super.key});
  @override
  ConsumerState<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends ConsumerState<LeaderboardPage> {
  String _scope = 'global';

  @override
  Widget build(BuildContext context) {
    // Realtime: profile XP/level/avatar changes refresh the board.
    // Throttled inside the provider to avoid re-fetch storms.
    ref.watch(leaderboardRealtimeProvider);

    final currentUser = ref.watch(authSessionProvider);
    final loc = AppLocalizations.of(context)!;

    final provider = _scope == 'following'
        ? followingLeaderboardProvider
        : leaderboardProvider;

    return Scaffold(
      backgroundColor: QuestColors.osBg,
      body: SafeArea(
        child: Consumer(builder: (context, ref, _) {
          final asyncValue = ref.watch(provider);
          return RefreshIndicator(
            color: QuestColors.osPrimary,
            onRefresh: () async {
              ref.invalidate(provider);
              // Wait for the new fetch to settle so the spinner doesn't
              // disappear before fresh data arrives.
              await ref.read(provider.future);
            },
            child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(
                      child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
                    child: Text('Leaderboard',
                        style: TextStyle(
                            fontFamily: 'Syne',
                            fontVariations: [FontVariation('wght', 800)],
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: QuestColors.osTextPrimary,
                            letterSpacing: -0.3)),
                  )),
                  SliverToBoxAdapter(
                      child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: BsSegBar(
                      options: const ['global', 'following'],
                      value: _scope,
                      onChange: (v) => setState(() => _scope = v),
                    ),
                  )),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  asyncValue.when(
                    loading: () => const SliverToBoxAdapter(
                      child: Center(
                          child: CircularProgressIndicator(
                              color: QuestColors.osPrimary, strokeWidth: 2)),
                    ),
                    error: (e, _) => SliverToBoxAdapter(
                      child: Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.error_outline,
                            color: QuestColors.osRed, size: 48),
                        const SizedBox(height: 16),
                        const Text('Failed to load',
                            style: TextStyle(
                                fontFamily: 'DMSans',
                                fontVariations: [FontVariation('wght', 500)],
                                color: QuestColors.osTextSecondary)),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => ref.invalidate(provider),
                          child: const Text('TAP TO RETRY',
                              style: TextStyle(
                                  fontFamily: 'Syne',
                                  fontVariations: [FontVariation('wght', 800)],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: QuestColors.osPrimary)),
                        ),
                      ])),
                    ),
                    data: (users) {
                      if (users.isEmpty) {
                        return SliverToBoxAdapter(
                            child: Center(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                              const SizedBox(height: 60),
                              const Icon(Icons.leaderboard_outlined,
                                  color: QuestColors.osTextMuted, size: 64),
                              const SizedBox(height: 16),
                              Text(loc.noRankingsYet,
                                  style: const TextStyle(
                                      fontFamily: 'Syne',
                                      fontVariations: [
                                        FontVariation('wght', 800)
                                      ],
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: QuestColors.osTextPrimary)),
                            ])));
                      }

                      final top3 = users.take(3).toList();
                      final rest = users.skip(3).toList();

                      return SliverMainAxisGroup(slivers: [
                        if (top3.length >= 3)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: _Podium(
                                  entries: top3,
                                  currentUserId: currentUser?.id),
                            ),
                          ),

                        // Rest of the list in one ChunkyCard
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          sliver: SliverToBoxAdapter(
                            child: ChunkyCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                  children: List.generate(rest.length, (i) {
                                final u = rest[i];
                                final isMe = u.userId == currentUser?.id;
                                return _RankRow(
                                  user: u,
                                  isCurrentUser: isMe,
                                  onTap: () => context.pushNamed(
                                      RouteNames.userProfile,
                                      pathParameters: {'userId': u.userId}),
                                  showDivider: i < rest.length - 1,
                                );
                              })),
                            ),
                          ),
                        ),
                      ]);
                    },
                  ),
                ]),
          );
        }),
      ),
    );
  }
}

// ── Podium ────────────────────────────────────────────────────────────────────

class _Podium extends StatelessWidget {
  const _Podium({required this.entries, this.currentUserId});
  final List<LeaderboardUserModel> entries;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    // Display order: 2nd (left), 1st (center), 3rd (right). Tolerate
    // fewer than 3 entries — leaving the slot empty rather than
    // RangeError-ing if a caller forgets the >=3 gate (every callsite
    // SHOULD gate, but defending here is cheap).
    final slots = <LeaderboardUserModel?>[
      entries.length > 1 ? entries[1] : null,
      entries.isNotEmpty ? entries[0] : null,
      entries.length > 2 ? entries[2] : null,
    ];
    final podiumColors = [
      QuestColors.osCool, // 2nd: cyan
      QuestColors.accentYellow, // 1st: gold
      QuestColors.osRed, // 3rd: hot red
    ];
    final sizes = [88.0, 108.0, 78.0]; // card heights

    return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          final e = slots[i];
          if (e == null) {
            return Expanded(child: SizedBox(height: sizes[i]));
          }
          final isMe = e.userId == currentUserId;
          return Expanded(
              child: Padding(
            padding: EdgeInsets.only(left: i > 0 ? 8 : 0),
            child: GestureDetector(
              onTap: () => context.pushNamed(RouteNames.userProfile,
                  pathParameters: {'userId': e.userId}),
              child: _PodiumCard(
                entry: e,
                color: podiumColors[i],
                cardHeight: sizes[i],
                isMe: isMe,
              ),
            ),
          ));
        }));
  }
}

class _PodiumCard extends StatelessWidget {
  const _PodiumCard(
      {required this.entry,
      required this.color,
      required this.cardHeight,
      required this.isMe});
  final LeaderboardUserModel entry;
  final Color color;
  final double cardHeight;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final isFirst = entry.rank == 1;
    final avatarSize = isFirst ? 52.0 : 42.0;
    final rankFontSize = isFirst ? 44.0 : 34.0;

    return Column(children: [
      // Avatar (profile image if available, otherwise coloured initial)
      _Avatar(
        user: entry,
        size: avatarSize,
        fontSize: isFirst ? 22.0 : 17.0,
        radius: isFirst ? 16 : 13,
      ),
      const SizedBox(height: 6),
      FitText(entry.username,
          minFontSize: 8,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontFamily: 'Syne',
              fontVariations: [FontVariation('wght', 800)],
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: QuestColors.osTextPrimary)),
      Text('${entry.xp} XP',
          style: const TextStyle(
              fontFamily: 'DMSans',
              fontVariations: [FontVariation('wght', 500)],
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: QuestColors.osTextSecondary)),
      const SizedBox(height: 4),
      // Podium block
      Container(
        height: cardHeight,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(
              color: QuestColors.osTextPrimary,
              width: QuestSpacing.cardBorderWidth),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          boxShadow: const [
            BoxShadow(color: QuestColors.osTextPrimary, offset: Offset(0, 4))
          ],
        ),
        alignment: Alignment.center,
        child: Text('#${entry.rank}',
            style: TextStyle(
                fontFamily: 'Syne',
                fontVariations: const [FontVariation('wght', 800)],
                fontSize: rankFontSize,
                fontWeight: FontWeight.w800,
                color: QuestColors.onAccent(color),
                height: 1)),
      ),
    ]);
  }
}

// ── Rank Row ──────────────────────────────────────────────────────────────────

class _RankRow extends StatelessWidget {
  const _RankRow(
      {required this.user,
      required this.isCurrentUser,
      required this.onTap,
      this.showDivider = true});
  final LeaderboardUserModel user;
  final bool isCurrentUser;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    // The ground decides the ink. The self row is an ink panel, so its text
    // has to invert or it disappears entirely; gold and white both take ink.
    final ground = isCurrentUser
        ? QuestColors.osTextPrimary
        : user.rank == 1
            ? QuestColors.osAccent
            : QuestColors.osCard;
    final fg = QuestColors.onAccent(ground);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          // The render draws each rank as its own card, not as a row in a
          // shared list: white ground, full 2px outline, 3px shadow. First
          // place takes gold, and the signed-in user takes an ink panel with
          // a violet shadow so it reads as "you" wherever it lands.
          color: ground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          boxShadow: [
            BoxShadow(
              color: isCurrentUser
                  ? QuestColors.osPrimary
                  : QuestColors.osTextPrimary,
              offset: const Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              // Rank number — pill grows horizontally past 2 digits so triple-
              // digit ranks don't overflow. Min-width matches the old 28dp look
              // for 1–2 digit ranks.
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: isCurrentUser
                        ? QuestColors.osTextPrimary
                        : QuestColors.osSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: QuestColors.osTextPrimary, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${user.rank}',
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Syne',
                      fontVariations: const [FontVariation('wght', 800)],
                      fontSize: user.rank > 99 ? 11 : 12,
                      fontWeight: FontWeight.w800,
                      color: isCurrentUser
                          ? QuestColors.osAccent
                          : QuestColors.osTextPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Avatar (profile image or coloured initial)
              _Avatar(user: user, size: 40, fontSize: 16, radius: 12),
              const SizedBox(width: 10),
              // Name
              Expanded(
                child: FitText(
                  user.username + (isCurrentUser ? '  · YOU' : ''),
                  minFontSize: 10,
                  style: TextStyle(
                    fontFamily: 'Syne',
                    fontVariations: const [FontVariation('wght', 800)],
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
              // XP score — bounded so a 7-digit XP can't collide with
              // the username column on small phones.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 90),
                child: FitText('${user.xp}',
                    minFontSize: 10,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontFamily: 'Syne',
                        fontVariations: const [FontVariation('wght', 800)],
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: fg)),
              ),
            ]),
          ),
          if (showDivider)
            const Divider(
                height: 1,
                thickness: 1,
                color: QuestColors.osBorder,
                indent: 14,
                endIndent: 14),
        ]),
      ),
    );
  }
}
