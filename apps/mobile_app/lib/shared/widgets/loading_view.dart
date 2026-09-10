import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:app_core/app_core.dart';

import 'pixel_loader.dart';
export 'pixel_loader.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: PixelLoader());
  }
}

/// Shimmer loading placeholder for cards/lists.
class ShimmerList extends StatelessWidget {
  const ShimmerList({super.key, this.itemCount = 4});
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: QuestColors.cardBg(context),
      highlightColor: QuestColors.surfaceBg(context),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(QuestSpacing.screenPadding),
        itemCount: itemCount,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: QuestSpacing.md),
          child: _ShimmerCard(),
        ),
      ),
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(QuestSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: QuestColors.pureWhite,
                    borderRadius:
                        BorderRadius.circular(QuestSpacing.radiusBadge),
                  ),
                ),
                const SizedBox(width: QuestSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 120,
                        height: 10,
                        color: QuestColors.pureWhite,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 80,
                        height: 8,
                        color: QuestColors.pureWhite,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: QuestSpacing.md),
            Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                color: QuestColors.pureWhite,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: QuestSpacing.sm),
            Container(width: 200, height: 10, color: QuestColors.pureWhite),
            const SizedBox(height: 6),
            Container(width: 140, height: 8, color: QuestColors.pureWhite),
          ],
        ),
      ),
    );
  }
}

/// Offline banner shown when there's no internet.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: QuestColors.osRed.withAlpha(30),
        border: Border(
          bottom: BorderSide(
            color: QuestColors.osRed.withAlpha(80),
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: QuestSpacing.screenPadding,
          vertical: 6,
        ),
        child: Row(
          children: [
            const Icon(Icons.wifi_off, size: 14, color: QuestColors.osRedText),
            const SizedBox(width: QuestSpacing.sm),
            Flexible(
              child: Text(
                'NO CONNECTION',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.labelSmall.copyWith(
                  color: QuestColors.osRedText,
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
