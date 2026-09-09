import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_models/app_models.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/providers/current_profile_provider.dart';
import '../../../profile/domain/player_class.dart';
import '../providers/leaderboard_provider.dart';
import '../../../../l10n/app_localizations.dart';
import 'package:app_core/app_core.dart';

/// Leaderboard — built to `export/mobile/13-leaderboard.jpg`.
///
/// The frame draws no podium. Every rank is its own card: white ground, 2px
/// ink outline, 3px ink shadow, 10px apart. Rank 1 takes gold. The signed-in
/// user is an ink panel with a violet shadow, and it is **stuck to the bottom
/// of the screen** rather than sitting at its numeric position — the render
/// shows ranks 1–5 in the list and rank 47 docked above the nav.

// Avatar tints, in the frame's cycle order: cream, sky, jade, coral,
// lavender. Every value is a QuestColors token — the previous local
// `_avatarOrange` hex was the only hard-coded colour on this screen.
const _avatarTints = <Color>[
  QuestColors.osBg,
  QuestColors.osCool,
  QuestColors.osSuccess,
  QuestColors.osRed,
  QuestColors.textSecondary,
  QuestColors.osAccent,
];

Color _avatarTint(int rank) => _avatarTints[(rank - 1) % _avatarTints.length];

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
    final users = asyncValue.valueOrNull ?? const <LeaderboardUserModel>[];

    // The self row: the real entry when the signed-in user is inside the
    // fetched page, otherwise synthesised from the cached profile so the
    // docked row still shows correct XP with an unknown rank rather than
    // vanishing for anyone outside the top 50.
    LeaderboardUserModel? selfEntry;
    if (currentUser != null) {
      for (final u in users) {
        if (u.userId == currentUser.id) {
          selfEntry = u;
          break;
        }
      }
    }
    final selfProfile = ref.watch(currentProfileProvider).valueOrNull;

    return Scaffold(
      backgroundColor: QuestColors.osBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: _PageTitle(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: _ScopeChips(
                scope: _scope,
                onChange: (value) => setState(() => _scope = value),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: QuestColors.osPrimary,
                backgroundColor: QuestColors.osCard,
                onRefresh: () async {
                  ref.invalidate(provider);
                  // Wait for the new fetch to settle so the spinner doesn't
                  // disappear before fresh data arrives.
                  await ref.read(provider.future);
                },
                child: asyncValue.when(
                  // Inside a ListView: `ArcadeSkeletonList` is a plain
                  // Column and overflows a short viewport on its own.
                  loading: () => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    children: const [
                      ArcadeSkeletonList(itemCount: 6, itemHeight: 60),
                    ],
                  ),
                  error: (e, _) => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                    children: [
                      _DashedPanel(
                        label: 'ERROR',
                        title: loc.failedToLoad,
                        body: 'Pull down to try again.',
                      ),
                    ],
                  ),
                  data: (rows) {
                    if (rows.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                        children: [
                          _DashedPanel(
                            label: 'EMPTY STATE',
                            title: loc.noRankingsYet,
                            body: 'Complete a quest to enter the board.',
                          ),
                        ],
                      );
                    }
                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final u = rows[i];
                        return _RankCard(
                          rank: '${u.rank}',
                          name: u.username,
                          level: u.level,
                          xp: u.xp,
                          avatarUrl: u.avatarUrl,
                          tint: _avatarTint(u.rank),
                          ground: u.rank == 1
                              ? QuestColors.osAccent
                              : QuestColors.osCard,
                          onTap: () => context.pushNamed(
                            RouteNames.userProfile,
                            pathParameters: {'userId': u.userId},
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            // Sticky self row. Docked, never scrolled away — the render puts
            // it against the bottom edge whatever the user's rank is.
            if (selfEntry != null || selfProfile != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: _RankCard(
                  rank: selfEntry != null ? '${selfEntry.rank}' : '—',
                  name: 'YOU',
                  level: selfEntry?.level ?? selfProfile!.level,
                  xp: selfEntry?.xp ?? selfProfile!.xp,
                  avatarUrl: selfEntry?.avatarUrl ?? selfProfile?.avatarUrl,
                  tint: QuestColors.osRed,
                  ground: QuestColors.osTextPrimary,
                  shadowColor: QuestColors.osPrimary,
                  onTap: () => context.goNamed(RouteNames.profile),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────

class _PageTitle extends StatelessWidget {
  const _PageTitle();

  @override
  Widget build(BuildContext context) {
    return FitText(
      'LEADERBOARD',
      minFontSize: 20,
      style: QuestTypography.osDisplayMedium.copyWith(
        fontSize: 30,
        letterSpacing: -0.8,
        height: 1,
      ),
    );
  }
}

/// GLOBAL / FOLLOWING as two separate outlined chips, not a segmented track:
/// selected is an ink fill with cream type, the other is white with a 2px ink
/// outline. Same treatment as the settings language chips.
class _ScopeChips extends StatelessWidget {
  const _ScopeChips({required this.scope, required this.onChange});

  final String scope;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _OptionChip(
          label: 'GLOBAL',
          selected: scope == 'global',
          onTap: () => onChange('global'),
        ),
        _OptionChip(
          label: 'FOLLOWING',
          selected: scope == 'following',
          onTap: () => onChange('following'),
        ),
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ground = selected ? QuestColors.osTextPrimary : QuestColors.osCard;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // 28pt of paint inside a 44pt hit box. The vertical padding is what
      // makes the target, rather than a ConstrainedBox — inside a Wrap a
      // Center would stretch the chip to the full run width.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        // No `alignment:` on this Container. Inside a Wrap the constraints
        // are bounded, and an Align with no widthFactor stretches the chip
        // to the full run width — which is what made these read as stacked
        // full-width bars instead of a row of chips.
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: ground,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osLabelMedium.copyWith(
              color: selected ? QuestColors.osBg : QuestColors.osTextPrimary,
              fontSize: 12,
              letterSpacing: 1,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Rank card ─────────────────────────────────────────────────────────────

class _RankCard extends StatelessWidget {
  const _RankCard({
    required this.rank,
    required this.name,
    required this.level,
    required this.xp,
    required this.avatarUrl,
    required this.tint,
    required this.ground,
    required this.onTap,
    this.shadowColor,
  });

  final String rank;
  final String name;
  final int level;
  final int xp;
  final String? avatarUrl;
  final Color tint;
  final Color ground;
  final Color? shadowColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The ground decides the ink. The self row is an ink panel, so its text
    // has to invert or it disappears entirely; gold and white both take ink.
    //
    // `onAccent` does not know about `osTextPrimary` — it only whitelists
    // osPrimary and the three dark* tokens — so ink-on-ink is guarded here.
    // See the handoff note: the frames use osTextPrimary as a panel ground
    // (this row, the collab hero, the selected chips) and the helper should
    // learn it.
    final isInk = ground == QuestColors.osTextPrimary;
    final onGround =
        isInk ? QuestColors.pureWhite : QuestColors.onAccent(ground);
    final subColor =
        isInk ? QuestColors.textSecondary : QuestColors.osTextSecondary;
    // Rank number: ink on gold, gold on the ink self panel, soft ink on white
    // — exactly what the frame prints.
    final rankColor = isInk
        ? QuestColors.osAccent
        : ground == QuestColors.osAccent
            ? QuestColors.osAccentInk
            : QuestColors.osTextSecondary;
    final xpColor = isInk ? QuestColors.osAccent : onGround;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: ground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          boxShadow: [
            BoxShadow(
              color: shadowColor ?? QuestColors.osTextPrimary,
              offset: const Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: FitText(
                rank,
                minFontSize: 12,
                style: QuestTypography.osDisplaySmall.copyWith(
                  fontSize: 24,
                  color: rankColor,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _RoundAvatar(
              url: avatarUrl,
              name: name,
              tint: tint,
              // An ink outline on an ink panel is invisible; the frame
              // switches the avatar ring to cream on the self row.
              borderColor: isInk ? QuestColors.osBg : QuestColors.osTextPrimary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osHeadlineLarge.copyWith(
                      fontSize: 18,
                      color: onGround,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'LVL $level · ${playerClassForLevel(level)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osLabelSmall.copyWith(
                      color: subColor,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 84),
              child: FitText(
                _thousands(xp),
                minFontSize: 10,
                textAlign: TextAlign.right,
                style: QuestTypography.osLabelLarge.copyWith(
                  fontSize: 16,
                  color: xpColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `18420` → `18,420`, which is how every score is set in the frames.
String _thousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Circle avatar, 40pt, 2px ring — the frame's leaderboard avatar. Falls
/// back to a tinted disc with the initial when there's no image.
class _RoundAvatar extends StatelessWidget {
  const _RoundAvatar({
    required this.url,
    required this.name,
    required this.tint,
    required this.borderColor,
  });

  final String? url;
  final String name;
  final Color tint;
  final Color borderColor;

  static const double _size = 40;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: QuestTypography.osHeadlineMedium.copyWith(
          color: QuestColors.onAccent(tint),
          height: 1,
        ),
      ),
    );

    if (url == null || url!.isEmpty) return placeholder;

    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
      ),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url!,
          fit: BoxFit.cover,
          width: _size,
          height: _size,
          // Cap in-memory decode at 2x for retina; prevents megabyte avatars
          // in a scrollable list.
          memCacheWidth: (_size * 2).round(),
          placeholder: (_, __) => ColoredBox(color: tint),
          errorWidget: (_, __, ___) => placeholder,
        ),
      ),
    );
  }
}

// ── Empty / error panel ───────────────────────────────────────────────────
//
// The frames draw an absent state as a dashed 2px outline on the page cream
// with a mono kicker, a display title and one sentence — see the EMPTY STATE
// block in `export/mobile/18-search.jpg`. Nothing filled, nothing coral.

class _DashedPanel extends StatelessWidget {
  const _DashedPanel({
    required this.label,
    required this.title,
    required this.body,
  });

  final String label;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _DashedBorderPainter(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: QuestTypography.osLabelSmall
                  .copyWith(color: QuestColors.osTextMuted),
            ),
            const SizedBox(height: 10),
            Text(
              title.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osDisplaySmall.copyWith(
                color: QuestColors.osTextSecondary,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: QuestTypography.osBodyMedium
                  .copyWith(color: QuestColors.osTextSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = QuestColors.osTextMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      const Radius.circular(16),
    );
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 6).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => false;
}
