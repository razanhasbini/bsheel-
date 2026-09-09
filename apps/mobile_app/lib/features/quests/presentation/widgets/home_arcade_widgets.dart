library home_arcade_widgets;

import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';

import 'home_extras.dart' show BsStreakFlame;

// ── Colour helpers ────────────────────────────────────────────────────────

Color _ink(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? QuestColors.textPrimary
    : QuestColors.osTextPrimary;

Color _inkSoft(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? QuestColors.textSecondary
    : QuestColors.osTextSecondary;

Color _surface(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? QuestColors.darkCard
    : QuestColors.osCard;

/// The Arcade Pop hard shadow: zero blur, ink, **equal x and y**.
///
/// This used to be `Offset(0, n)`. A vertical-only offset reads as a soft
/// drop shadow no matter how hard its edge is, and it silently applied to
/// every avatar, chip, bell, stat tile and card on home.
BoxShadow _hardShadow(BuildContext c, {double offset = 4}) => BoxShadow(
      color: _ink(c),
      offset: Offset(offset, offset),
      blurRadius: 0,
    );

// ── Pixel grid background ─────────────────────────────────────────────────

class ArcadePixelGrid extends StatelessWidget {
  const ArcadePixelGrid({super.key, this.opacity = 0.05});
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ShaderMask(
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [QuestColors.pureBlack.withAlpha(255), Colors.transparent],
          stops: const [0.3, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: CustomPaint(
          painter: _PixelGridPainter(
            color: _ink(context).withAlpha((opacity * 255).round()),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _PixelGridPainter extends CustomPainter {
  _PixelGridPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 16.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_PixelGridPainter old) => old.color != color;
}

// ── Avatar with level badge ───────────────────────────────────────────────

class ArcadeAvatarLevel extends StatelessWidget {
  const ArcadeAvatarLevel({
    super.key,
    required this.initial,
    required this.level,
    this.onTap,
  });
  final String initial;
  final int level;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = _ink(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 52,
        height: 52,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [QuestColors.osPrimary, QuestColors.osRed],
                ),
                border: Border.all(color: ink, width: 2),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [_hardShadow(context, offset: 3)],
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: QuestTypography.headlineMedium.copyWith(
                  color: QuestColors.osTextOnPrimary,
                  fontSize: 18,
                ),
              ),
            ),
            Positioned(
              bottom: -2,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: QuestColors.accentYellow,
                  border: Border.all(color: ink, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'L$level',
                  style: QuestTypography.headlineSmall.copyWith(
                    color: QuestColors.accentYellowInk,
                    fontSize: 10,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Streak pill ───────────────────────────────────────────────────────────

class ArcadeStreakPill extends StatelessWidget {
  const ArcadeStreakPill({super.key, required this.streak});
  final int streak;

  @override
  Widget build(BuildContext context) {
    final ink = _ink(context);
    final onCoral = QuestColors.onAccent(QuestColors.osRed);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: QuestColors.osRed,
        border: Border.all(color: ink, width: 2),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [_hardShadow(context, offset: 3)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department, size: 16, color: onCoral),
          const SizedBox(width: 3),
          Text(
            '$streak',
            maxLines: 1,
            style: QuestTypography.headlineSmall.copyWith(
              color: onCoral,
              fontSize: 14,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Notification bell ─────────────────────────────────────────────────────

class ArcadeNotificationBell extends StatelessWidget {
  const ArcadeNotificationBell({
    super.key,
    required this.unreadCount,
    this.onTap,
  });
  final int unreadCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = _ink(context);
    return Semantics(
      button: true,
      label: unreadCount > 0
          ? 'Notifications, $unreadCount unread'
          : 'Notifications',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          // 44 painted, so the tile itself is already the hit target.
          width: QuestSpacing.minTouchTarget,
          height: QuestSpacing.minTouchTarget,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: QuestSpacing.minTouchTarget,
                height: QuestSpacing.minTouchTarget,
                decoration: BoxDecoration(
                  // Gold in the frame, not white: the bell is the one
                  // control in the name row, and gold is how the design
                  // says so.
                  color: QuestColors.osAccent,
                  border: Border.all(color: ink, width: 2),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [_hardShadow(context, offset: 3)],
                ),
                child: Icon(
                  Icons.notifications_none_rounded,
                  color: QuestColors.onAccent(QuestColors.osAccent),
                  size: 22,
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    height: 20,
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: QuestColors.osRed,
                      border: Border.all(color: ink, width: 2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: QuestTypography.osLabelMedium.copyWith(
                        // Ink on coral. White on coral is 3.03:1.
                        color: QuestColors.onAccent(QuestColors.osRed),
                        fontSize: 10,
                        letterSpacing: 0,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hero headline: "Ready to roll, {name}?" ───────────────────────────────

class ArcadeHero extends StatelessWidget {
  const ArcadeHero({super.key, required this.name, this.dateLine});
  final String name;
  final String? dateLine;

  @override
  Widget build(BuildContext context) {
    final ink = _ink(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dateLine != null)
          Text(
            dateLine!.toUpperCase(),
            style: QuestTypography.labelMedium.copyWith(
              color: _inkSoft(context),
              letterSpacing: 0.8,
            ),
          ),
        const SizedBox(height: 4),
        RichText(
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            style: QuestTypography.displayLarge.copyWith(
              color: ink,
              fontSize: 36,
              height: 1.05,
              letterSpacing: -0.5,
            ),
            children: [
              const TextSpan(text: 'Ready to roll,\n'),
              TextSpan(
                text: '$name?',
                style: const TextStyle(color: QuestColors.osPrimary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Dashed section header: — HEADING — ───────────────────────────────────

class ArcadeSectionHeader extends StatelessWidget {
  const ArcadeSectionHeader({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final ink = _ink(context);
    return Row(
      children: [
        Container(width: 20, height: 2, color: ink),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.headlineSmall.copyWith(
              color: ink,
              fontSize: 14,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(child: Container(height: 2, color: ink.withAlpha(30))),
      ],
    );
  }
}

// ── Chunky stat tile ──────────────────────────────────────────────────────

class ArcadeStatTile extends StatelessWidget {
  const ArcadeStatTile({
    super.key,
    required this.label,
    required this.value,
    this.sublabel,
    required this.tint,
    this.icon,
  });

  /// e.g. "QUESTS DONE"
  final String label;

  /// The big number, e.g. "27"
  final String value;

  /// The small line under the value, e.g. "ALL TIME"
  final String? sublabel;

  /// Card ground: gold on the left tile, violet on the right.
  final Color tint;

  /// Unused by the frame — it draws no glyph on these tiles. Kept so
  /// existing call sites compile.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ink = _ink(context);
    // Derived, never passed in: the ground decides the text colour. Gold
    // takes osAccentInk, violet takes white.
    final onTint = QuestColors.onAccent(tint);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tint,
        border: Border.all(color: ink, width: 2),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [_hardShadow(context)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osLabelMedium.copyWith(
              color: onTint,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 1),
          // Big numbers scale down rather than clip once they run long.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: QuestTypography.osDisplayMedium.copyWith(
                color: onTint,
                fontSize: 32,
                height: 1.05,
                letterSpacing: -1.12,
              ),
            ),
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 1),
            Text(
              sublabel!.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osLabelSmall.copyWith(
                // Full opacity on an accent ground: dimming ink on gold
                // drops it back under AA.
                color: onTint,
                fontSize: 9,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Streak card with 28-day heatmap ───────────────────────────────────────

class ArcadeStreakCard extends StatelessWidget {
  const ArcadeStreakCard({
    super.key,
    required this.currentStreak,
    required this.longestStreak,
    required this.activeDays,
  });

  final int currentStreak;
  final int longestStreak;

  /// Length 28, oldest first. The frame no longer draws a heatmap, but
  /// callers still compute it, so the parameter stays.
  final List<bool> activeDays;

  @override
  Widget build(BuildContext context) {
    final ink = _ink(context);
    // Ink on coral. The 28-cell heatmap this replaced was not in any
    // frame, and it made the streak the tallest card on a page whose
    // point is the quest.
    final fg = QuestColors.onAccent(QuestColors.osRed);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: QuestColors.osRed,
        border: Border.all(color: ink, width: 2),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [_hardShadow(context)],
      ),
      child: Row(
        children: [
          Text(
            '$currentStreak',
            maxLines: 1,
            style: QuestTypography.osDisplayMedium.copyWith(
              color: fg,
              fontSize: 30,
              height: 1,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DAY STREAK',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.osHeadlineMedium.copyWith(
                    color: fg,
                    fontSize: 15,
                    letterSpacing: -0.23,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'LONGEST: $longestStreak',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.osLabelMedium.copyWith(
                    color: fg,
                    fontSize: 10,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // The flame is the frame's one glyph here, and it swells with
          // the milestone tier so a 30-day run reads hotter than a 3-day.
          BsStreakFlame(streak: currentStreak, size: 24),
        ],
      ),
    );
  }
}

// ── Slot machine — 3 reels + gold GENERATE button ─────────────────────────

class ArcadeSlotMachine extends StatefulWidget {
  const ArcadeSlotMachine({
    super.key,
    required this.isGenerating,
    required this.progress,
    required this.onTap,
    this.lockLabel,
    this.activeQuestTitle,
    this.reelEmojis = const ['🎯', '⚡', '🎲'],
    this.resetsIn,
  });

  final bool isGenerating;
  final double progress; // 0..1
  final VoidCallback? onTap;

  /// when non-null, the slot is locked (e.g. "Quest in progress")
  final String? lockLabel;
  final String? activeQuestTitle;
  final List<String> reelEmojis;
  final String? resetsIn;

  @override
  State<ArcadeSlotMachine> createState() => _ArcadeSlotMachineState();
}

class _ArcadeSlotMachineState extends State<ArcadeSlotMachine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  static const _emojiPool = [
    '🎯',
    '⚡',
    '🎲',
    '🔥',
    '✨',
    '🎨',
    '🚀',
    '💪',
    '🧠',
    '🌟'
  ];

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    if (widget.isGenerating) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant ArcadeSlotMachine old) {
    super.didUpdateWidget(old);
    if (widget.isGenerating && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.isGenerating && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = _ink(context);
    const darkInk = QuestColors.osTextPrimary; // card is always dark-ink

    return Container(
      decoration: BoxDecoration(
        color: darkInk,
        border: Border.all(color: ink, width: 2),
        borderRadius: BorderRadius.circular(QuestSpacing.radiusXl),
        boxShadow: [_hardShadow(context, offset: 6)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(QuestSpacing.radiusXl - 2),
        child: Stack(
          children: [
            // Scanlines
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ScanlinePainter(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: QuestColors.accentYellow.withAlpha(40),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.casino,
                                size: 12, color: QuestColors.accentYellow),
                            const SizedBox(width: 5),
                            Text(
                              widget.lockLabel != null
                                  ? 'LOCKED'
                                  : 'DAILY ROLL',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: QuestTypography.labelSmall.copyWith(
                                color: QuestColors.accentYellow,
                                fontSize: 10,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (widget.resetsIn != null)
                        Flexible(
                          child: Text(
                            widget.resetsIn!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: QuestTypography.bodySmall.copyWith(
                              color: QuestColors.textPrimary.withAlpha(160),
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Reels
                  _Reels(
                    isGenerating: widget.isGenerating,
                    spin: _spin,
                    emojiPool: _emojiPool,
                    locked: widget.lockLabel != null,
                    restingEmojis: widget.reelEmojis,
                  ),

                  const SizedBox(height: 14),

                  // Lock copy (if active quest in progress)
                  if (widget.lockLabel != null) ...[
                    Text(
                      widget.lockLabel!.toUpperCase(),
                      style: QuestTypography.labelSmall.copyWith(
                        color: QuestColors.textPrimary.withAlpha(180),
                        fontSize: 10,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.activeQuestTitle ?? 'Quest in progress',
                      style: QuestTypography.displayMedium.copyWith(
                        color: QuestColors.textPrimary,
                        fontSize: 24,
                        height: 1.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // CTA
                  _GenerateButton(
                    enabled: widget.onTap != null && !widget.isGenerating,
                    isGenerating: widget.isGenerating,
                    progress: widget.progress,
                    locked: widget.lockLabel != null,
                    onTap: widget.onTap,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Reels extends StatelessWidget {
  const _Reels({
    required this.isGenerating,
    required this.spin,
    required this.emojiPool,
    required this.locked,
    required this.restingEmojis,
  });
  final bool isGenerating;
  final AnimationController spin;
  final List<String> emojiPool;
  final bool locked;
  final List<String> restingEmojis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: QuestColors.darkCard,
        border: Border.all(color: QuestColors.accentYellow, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: List.generate(3, (i) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: QuestColors.darkBg,
                    border:
                        Border.all(color: QuestColors.osTextPrimary, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: isGenerating
                      ? AnimatedBuilder(
                          animation: spin,
                          builder: (_, __) {
                            final emoji = emojiPool[
                                (spin.value * emojiPool.length).floor() +
                                            i * 2 <
                                        emojiPool.length
                                    ? (spin.value * emojiPool.length).floor() +
                                        i * 2
                                    : ((spin.value * emojiPool.length).floor() +
                                            i * 2) %
                                        emojiPool.length];
                            return Text(emoji,
                                style: const TextStyle(fontSize: 40));
                          },
                        )
                      : Opacity(
                          opacity: locked ? 0.25 : 1,
                          child: Text(
                            restingEmojis.length > i ? restingEmojis[i] : '?',
                            style: const TextStyle(fontSize: 40),
                          ),
                        ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _GenerateButton extends StatefulWidget {
  const _GenerateButton({
    required this.enabled,
    required this.isGenerating,
    required this.progress,
    required this.locked,
    this.onTap,
  });
  final bool enabled;
  final bool isGenerating;
  final double progress;
  final bool locked;
  final VoidCallback? onTap;

  @override
  State<_GenerateButton> createState() => _GenerateButtonState();
}

class _GenerateButtonState extends State<_GenerateButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.locked
        ? 'QUEST LOCKED'
        : widget.isGenerating
            ? 'ROLLING...'
            : 'GENERATE QUEST';
    final canTap = widget.enabled && !widget.locked;

    final bg = widget.locked
        ? QuestColors.pureWhite.withAlpha(30)
        : QuestColors.accentYellow;
    final fg = widget.locked
        ? QuestColors.textPrimary.withAlpha(150)
        : QuestColors.accentYellowInk;

    return GestureDetector(
      onTapDown: canTap ? (_) => setState(() => _pressed = true) : null,
      onTapUp: canTap ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: canTap ? () => setState(() => _pressed = false) : null,
      onTap: canTap ? widget.onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        transform: Matrix4.translationValues(0, _pressed ? 4 : 0, 0),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          borderRadius: BorderRadius.circular(18),
          boxShadow: _pressed || widget.locked
              ? []
              : const [
                  BoxShadow(
                    color: QuestColors.osTextPrimary,
                    offset: Offset(0, 4),
                    blurRadius: 0,
                  ),
                ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!widget.isGenerating && !widget.locked)
              Icon(Icons.bolt, size: 20, color: fg),
            if (widget.isGenerating)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  value: widget.progress > 0 ? widget.progress : null,
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                ),
              ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: QuestTypography.displayMedium.copyWith(
                  color: fg,
                  fontSize: 18,
                  letterSpacing: 0.5,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = QuestColors.pureWhite.withAlpha(10);
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Quest option row (after a roll) ───────────────────────────────────────

class ArcadeQuestOption extends StatelessWidget {
  const ArcadeQuestOption({
    super.key,
    required this.title,
    required this.category,
    required this.difficulty,
    required this.timeMinutes,
    required this.xp,
    required this.index, // 0, 1, 2 — drives icon tint
    required this.onAccept,
    this.isAccepting = false,
    this.isDisabled = false,
  });

  final String title;
  final String category;
  final String difficulty;
  final int timeMinutes;
  final int xp;
  final int index;
  final VoidCallback onAccept;
  final bool isAccepting;
  final bool isDisabled;

  Color _tileColor() {
    switch (index % 3) {
      case 0:
        return QuestColors.osPrimary; // violet
      case 1:
        return QuestColors.osRed; // coral
      default:
        return QuestColors.osCool; // sky
    }
  }

  Color _categoryColor() {
    switch (category.toLowerCase()) {
      case 'fitness':
        return QuestColors.catFitness;
      case 'creativity':
      case 'creative':
        return QuestColors.catCreativity;
      case 'social':
        return QuestColors.catSocial;
      case 'learning':
      case 'learn':
        return QuestColors.catLearning;
      case 'adventure':
        return QuestColors.catAdventure;
      default:
        return QuestColors.osPrimary;
    }
  }

  /// The same category hue, darkened where the fill fails contrast as 9px
  /// type on a cream/white chip. Sky has no darkened twin in the palette, so
  /// it falls back to ink — the fill behind it still carries the colour.
  Color _categoryTextColor() {
    switch (category.toLowerCase()) {
      case 'fitness':
        return QuestColors.osRedText;
      case 'learning':
      case 'learn':
        return QuestColors.osSuccessText;
      case 'adventure':
        return QuestColors.osAccentText;
      case 'social':
        return QuestColors.osTextPrimary;
      case 'creativity':
      case 'creative':
      default:
        return QuestColors.osPrimary;
    }
  }

  IconData _categoryIcon() {
    switch (category.toLowerCase()) {
      case 'fitness':
        return Icons.fitness_center;
      case 'creativity':
      case 'creative':
        return Icons.palette;
      case 'social':
        return Icons.people;
      case 'learning':
      case 'learn':
        return Icons.school;
      case 'adventure':
        return Icons.explore;
      default:
        return Icons.star;
    }
  }

  String _timeStr() {
    if (timeMinutes < 60) return '${timeMinutes}m';
    final h = timeMinutes ~/ 60;
    final m = timeMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final ink = _ink(context);
    final opacity = isDisabled ? 0.4 : 1.0;

    return Opacity(
      opacity: opacity,
      child: GestureDetector(
        onTap: isAccepting || isDisabled ? null : onAccept,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surface(context),
            border: Border.all(color: ink, width: 2),
            borderRadius: BorderRadius.circular(QuestSpacing.radiusLg),
            boxShadow: [_hardShadow(context)],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _tileColor(),
                  border: Border.all(color: ink, width: 2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_categoryIcon(),
                    color: QuestColors.onAccent(_tileColor()), size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _categoryColor().withAlpha(40),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        category.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: QuestTypography.labelSmall.copyWith(
                          color: _categoryTextColor(),
                          fontSize: 9,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: QuestTypography.headlineMedium.copyWith(
                        color: ink,
                        fontSize: 15,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.timer_outlined,
                            size: 12, color: _inkSoft(context)),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            _timeStr(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: QuestTypography.bodySmall.copyWith(
                              color: _inkSoft(context),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.bolt,
                            size: 12, color: QuestColors.osPrimary),
                        Flexible(
                          child: Text(
                            '+$xp XP',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: QuestTypography.headlineSmall.copyWith(
                              color: QuestColors.osPrimary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isAccepting)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.chevron_right, color: ink, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state card ──────────────────────────────────────────────────────

class ArcadeEmptyCard extends StatelessWidget {
  const ArcadeEmptyCard({super.key, required this.text, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ink = _ink(context);
    return DottedBorderBox(
      color: ink.withAlpha(80),
      radius: QuestSpacing.radiusLg,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (icon != null) ...[
              Icon(icon, color: _inkSoft(context), size: 32),
              const SizedBox(height: 8),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: QuestTypography.bodyMedium.copyWith(
                color: _inkSoft(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dotted-border helper ──────────────────────────────────────────────────

class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({
    super.key,
    required this.child,
    required this.color,
    this.radius = 16,
  });
  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DottedRectPainter(color: color, radius: radius),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }
}

class _DottedRectPainter extends CustomPainter {
  _DottedRectPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final dashPath = Path();
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        dashPath.addPath(metric.extractPath(dist, dist + 5), Offset.zero);
        dist += 10;
      }
    }
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}
