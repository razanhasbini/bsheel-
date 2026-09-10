import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/router/route_names.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/leaderboard_provider.dart';

/// Leaderboard — the layout the legacy Bsheel app shipped.
///
/// A GLOBAL / FOLLOWING segmented track, the top three on a 2-1-3 podium
/// (gold in the middle, sky and coral either side), then every remaining
/// rank as a row inside one card, with the signed-in user's row tinted and
/// tagged "· YOU" at its real position. Pull to refresh; realtime XP changes
/// refresh the board on their own.
///
/// Same providers as before — only the presentation went back.

// Screen-specific colour — not a theme token. The sixth avatar tint in the
// legacy cycle; the palette has no orange.
const Color _avatarOrange = Color(0xFFFF9F1C);

// Avatar square tints, cycling by user so a person keeps their colour
// wherever they land on the board.
const _avatarColors = <Color>[
  QuestColors.osRed,
  QuestColors.violet,
  QuestColors.osSuccess,
  QuestColors.accentYellow,
  QuestColors.osCool,
  _avatarOrange,
];

Color _avatarColor(String userId) =>
    _avatarColors[userId.hashCode.abs() % _avatarColors.length];

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
    final asyncValue = ref.watch(provider);

    return Scaffold(
      backgroundColor: QuestColors.osBg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: QuestColors.osPrimary,
          backgroundColor: QuestColors.osCard,
          onRefresh: () async {
            ref.invalidate(provider);
            // Wait for the new fetch to settle so the spinner doesn't
            // disappear before fresh data arrives.
            await ref.read(provider.future);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Text(
                    loc.leaderboard.toUpperCase(),
                    style: QuestTypography.osDisplaySmall.copyWith(
                      fontSize: 24,
                      height: 1,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _SegBar(
                    options: const ['global', 'following'],
                    value: _scope,
                    onChange: (v) {
                      HapticFeedback.selectionClick();
                      setState(() => _scope = v);
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              asyncValue.when(
                loading: () => const SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 20),
                  sliver: SliverToBoxAdapter(
                    child: ArcadeSkeletonList(itemCount: 6, itemHeight: 60),
                  ),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: _CentredState(
                    icon: Icons.error_outline,
                    iconColor: QuestColors.osRed,
                    title: loc.failedToLoad,
                    action: _RetryLink(onTap: () => ref.invalidate(provider)),
                  ),
                ),
                data: (users) {
                  if (users.isEmpty) {
                    return SliverToBoxAdapter(
                      child: _CentredState(
                        icon: Icons.leaderboard_outlined,
                        iconColor: QuestColors.osTextMuted,
                        title: loc.noRankingsYet,
                      ),
                    );
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
                            currentUserId: currentUser?.id,
                          ),
                        ),
                      ),
                    // Fewer than three players: no podium, everyone is a row.
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverToBoxAdapter(
                        child: _RankList(
                          users: top3.length >= 3 ? rest : users,
                          currentUserId: currentUser?.id,
                        ),
                      ),
                    ),
                  ]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Segmented track ──────────────────────────────────────────────────────────

/// The legacy two-option track: warm surface, ink outline, the active
/// segment an ink pill with cream type.
class _SegBar extends StatelessWidget {
  const _SegBar({
    required this.options,
    required this.value,
    required this.onChange,
  });

  final List<String> options;
  final String value;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: QuestColors.osSurface,
        border: Border.all(
            color: QuestColors.osTextPrimary,
            width: QuestSpacing.cardBorderWidth),
        borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
      ),
      child: Row(
        children: options.map((o) {
          final active = o == value;
          return Expanded(
            child: Semantics(
              button: true,
              selected: active,
              label: o.toUpperCase(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChange(o),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  constraints: const BoxConstraints(
                      minHeight: QuestSpacing.minTouchTarget - 8),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color:
                        active ? QuestColors.osTextPrimary : Colors.transparent,
                    borderRadius: BorderRadius.circular(QuestSpacing.inner(
                        QuestSpacing.radiusMd, QuestSpacing.xs)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    o.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osLabelMedium.copyWith(
                      fontSize: 12,
                      color:
                          active ? QuestColors.osBg : QuestColors.osTextPrimary,
                      letterSpacing: 0.4,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Avatar ───────────────────────────────────────────────────────────────────

/// The user's profile image if there is one, otherwise a chunky coloured
/// square with the first letter of their name.
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
    const shadow = [
      BoxShadow(color: QuestColors.osTextPrimary, offset: Offset(0, 2)),
    ];

    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint,
        border: border,
        borderRadius: radiusObj,
        boxShadow: shadow,
      ),
      alignment: Alignment.center,
      child: Text(
        user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
        style: QuestTypography.osHeadlineLarge.copyWith(
          fontSize: fontSize,
          // Ink on gold and sky, white on the darker tints — measured.
          color: QuestColors.onAccent(tint),
          height: 1,
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
        boxShadow: shadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
            QuestSpacing.inner(radius, QuestSpacing.cardBorderWidth)),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: size,
          height: size,
          // Cap in-memory decode at 2x size for retina; prevents megabyte
          // avatars in a scrollable board.
          memCacheWidth: (size * 2).round(),
          placeholder: (_, __) => ColoredBox(color: tint),
          errorWidget: (_, __, ___) => placeholder,
        ),
      ),
    );
  }
}

// ── Podium ───────────────────────────────────────────────────────────────────

class _Podium extends StatelessWidget {
  const _Podium({required this.entries, this.currentUserId});
  final List<LeaderboardUserModel> entries;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    // Display order: 2nd (left), 1st (centre), 3rd (right). Tolerates fewer
    // than three entries by leaving the slot empty rather than throwing.
    final slots = <LeaderboardUserModel?>[
      entries.length > 1 ? entries[1] : null,
      entries.isNotEmpty ? entries[0] : null,
      entries.length > 2 ? entries[2] : null,
    ];
    const podiumColors = [
      QuestColors.osCool, // 2nd: sky
      QuestColors.accentYellow, // 1st: gold
      QuestColors.osRed, // 3rd: coral
    ];
    const heights = [88.0, 108.0, 78.0];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (i) {
        final e = slots[i];
        if (e == null) {
          return Expanded(child: SizedBox(height: heights[i]));
        }
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i > 0 ? 8 : 0),
            child: Semantics(
              button: true,
              label: 'Rank ${e.rank}, ${e.username}, ${e.xp} XP',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.pushNamed(
                  RouteNames.userProfile,
                  pathParameters: {'userId': e.userId},
                ),
                child: _PodiumCard(
                  entry: e,
                  color: podiumColors[i],
                  cardHeight: heights[i],
                  isMe: e.userId == currentUserId,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _PodiumCard extends StatelessWidget {
  const _PodiumCard({
    required this.entry,
    required this.color,
    required this.cardHeight,
    required this.isMe,
  });
  final LeaderboardUserModel entry;
  final Color color;
  final double cardHeight;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final isFirst = entry.rank == 1;
    final avatarSize = isFirst ? 52.0 : 42.0;
    final rankFontSize = isFirst ? 44.0 : 34.0;

    return Column(
      children: [
        _Avatar(
          user: entry,
          size: avatarSize,
          fontSize: isFirst ? 22.0 : 17.0,
          radius: isFirst ? QuestSpacing.radiusCard : QuestSpacing.radiusPanel,
        ),
        const SizedBox(height: 6),
        FitText(
          isMe ? '${entry.username} · YOU' : entry.username,
          minFontSize: 8,
          textAlign: TextAlign.center,
          style: QuestTypography.osHeadlineSmall.copyWith(fontSize: 12),
        ),
        Text(
          '${entry.xp} XP',
          style: QuestTypography.osLabelSmall.copyWith(
            fontSize: 10,
            color: QuestColors.osTextSecondary,
          ),
        ),
        const SizedBox(height: 4),
        // Podium block
        Container(
          height: cardHeight,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(
                color: QuestColors.osTextPrimary,
                width: QuestSpacing.cardBorderWidth),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(QuestSpacing.radiusMd)),
            boxShadow: const [
              BoxShadow(color: QuestColors.osTextPrimary, offset: Offset(0, 4)),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            '#${entry.rank}',
            style: QuestTypography.osDisplayLarge.copyWith(
              fontSize: rankFontSize,
              // Ink on gold and sky, white on coral — measured, not guessed.
              color: QuestColors.onAccent(color),
              height: 1,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Rank list ────────────────────────────────────────────────────────────────

/// Every rank below the podium, as rows inside one bordered card.
class _RankList extends StatelessWidget {
  const _RankList({required this.users, required this.currentUserId});
  final List<LeaderboardUserModel> users;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) return const SizedBox.shrink();
    return ArcadeCard(
      padding: EdgeInsets.zero,
      borderRadius: QuestSpacing.radiusCard,
      shadowOffset: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(QuestSpacing.inner(
            QuestSpacing.radiusCard, QuestSpacing.cardBorderWidth)),
        child: Column(
          children: List.generate(users.length, (i) {
            final u = users[i];
            return _RankRow(
              user: u,
              isCurrentUser: u.userId == currentUserId,
              onTap: () => context.pushNamed(
                RouteNames.userProfile,
                pathParameters: {'userId': u.userId},
              ),
              showDivider: i < users.length - 1,
            );
          }),
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.user,
    required this.isCurrentUser,
    required this.onTap,
    this.showDivider = true,
  });
  final LeaderboardUserModel user;
  final bool isCurrentUser;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Rank ${user.rank}, ${user.username}, ${user.xp} XP',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ColoredBox(
          color: isCurrentUser
              ? QuestColors.osAccent.withAlpha(40)
              : Colors.transparent,
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    // Rank number — the pill grows horizontally past two
                    // digits so triple-digit ranks don't overflow.
                    Container(
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isCurrentUser
                            ? QuestColors.osTextPrimary
                            : QuestColors.osSurface,
                        borderRadius:
                            BorderRadius.circular(QuestSpacing.radiusChip),
                        border: Border.all(
                            color: QuestColors.osTextPrimary, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${user.rank}',
                        maxLines: 1,
                        style: QuestTypography.osLabelMedium.copyWith(
                          fontSize: user.rank > 99 ? 11 : 12,
                          color: isCurrentUser
                              ? QuestColors.osAccent
                              : QuestColors.osTextPrimary,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _Avatar(
                      user: user,
                      size: 40,
                      fontSize: 16,
                      radius: QuestSpacing.radiusControl,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FitText(
                        user.username + (isCurrentUser ? '  · YOU' : ''),
                        minFontSize: 10,
                        style: QuestTypography.osHeadlineSmall
                            .copyWith(fontSize: 14),
                      ),
                    ),
                    // XP score — bounded so a 7-digit XP can't collide with
                    // the username column on small phones.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 90),
                      child: FitText(
                        '${user.xp}',
                        minFontSize: 10,
                        textAlign: TextAlign.right,
                        style: QuestTypography.osHeadlineMedium
                            .copyWith(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
              if (showDivider)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: QuestColors.osBorder,
                  indent: 14,
                  endIndent: 14,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty / error ────────────────────────────────────────────────────────────

class _CentredState extends StatelessWidget {
  const _CentredState({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.action,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 56),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: QuestTypography.osHeadlineMedium.copyWith(fontSize: 16),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );
  }
}

class _RetryLink extends StatelessWidget {
  const _RetryLink({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            'TAP TO RETRY',
            style: QuestTypography.osLabelMedium.copyWith(
              fontSize: 12,
              color: QuestColors.osPrimary,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}
