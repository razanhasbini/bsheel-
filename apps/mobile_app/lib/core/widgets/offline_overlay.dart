import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_core/app_core.dart';

import '../providers/connectivity_provider.dart';

/// Wraps a child widget. When the device is fully offline, paints a
/// blocking arcade-pop "you're offline" panel over it. The child stays
/// alive underneath so navigation state isn't lost.
class OfflineOverlay extends ConsumerWidget {
  const OfflineOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(isOfflineProvider);
    return Stack(
      children: [
        child,
        if (offline)
          Positioned.fill(
            child: _OfflinePanel(
              onRetry: () async {
                // Force a re-check by reading the current snapshot;
                // the stream will push the new value if it changed.
                try {
                  await Connectivity().checkConnectivity();
                } catch (_) {}
              },
            ),
          ),
      ],
    );
  }
}

class _OfflinePanel extends StatelessWidget {
  const _OfflinePanel({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Material(
      color: QuestColors.bg(context),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(QuestSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: QuestColors.softRed,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: ink, width: 3),
                    boxShadow: [
                      BoxShadow(color: ink, offset: const Offset(4, 5)),
                    ],
                  ),
                  child: Icon(
                    Icons.wifi_off_rounded,
                    size: 48,
                    color: QuestColors.onAccent(QuestColors.softRed),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'YOU\'RE OFFLINE',
                  style: TextStyle(
                    fontFamily: 'Syne',
                    fontWeight: FontWeight.w800,
                    fontSize: 28,
                    letterSpacing: 1.2,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Bsheel needs a connection to load quests, votes, and the feed.',
                  textAlign: TextAlign.center,
                  style: QuestTypography.bodyMedium.copyWith(
                    color: ink.withAlpha(190),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                _RetryButton(onTap: onRetry),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RetryButton extends StatefulWidget {
  const _RetryButton({required this.onTap});
  final Future<void> Function() onTap;

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return GestureDetector(
      onTap: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await widget.onTap();
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: QuestColors.accentYellow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ink, width: 2),
          boxShadow: [
            BoxShadow(color: ink, offset: const Offset(2, 3)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.refresh_rounded, size: 18, color: ink),
            const SizedBox(width: 8),
            Text(
              _busy ? 'CHECKING…' : 'TRY AGAIN',
              style: TextStyle(
                fontFamily: 'Syne',
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 1.4,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
