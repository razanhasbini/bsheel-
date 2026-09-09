import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_core/app_core.dart';

import '../providers/feed_provider.dart';

const String feedSortRecent = 'recent';
const String feedSortTop = 'top';
const String feedSortHot = 'hot';
const String feedSortBottom = 'bottom';
const String feedSortGraveyard = 'graveyard';

const _filterOptions = <_FilterOption>[
  _FilterOption(feedSortTop, 'MOST UPVOTED', Icons.trending_up_rounded),
  _FilterOption(feedSortHot, 'TRENDY', Icons.local_fire_department_rounded),
  _FilterOption(feedSortBottom, 'LEAST UPVOTED', Icons.trending_down_rounded),
  _FilterOption(feedSortGraveyard, 'GRAVEYARD', Icons.cancel_rounded),
];

/// Slides up a chunky filter sheet for the feed sort. Tap a row to apply,
/// tap "CLEAR FILTER" or outside the card to dismiss without changing
/// anything. The active filter persists across global / following until
/// the user clears it.
Future<void> showFeedFilterSheet(
  BuildContext context, {
  required WidgetRef ref,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: false,
    backgroundColor: Colors.transparent,
    barrierColor: QuestColors.pureBlack.withAlpha(120),
    useSafeArea: true,
    useRootNavigator: true,
    builder: (sheetCtx) => _FeedFilterSheet(ref: ref),
  );
}

class _FilterOption {
  const _FilterOption(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

class _FeedFilterSheet extends ConsumerWidget {
  const _FeedFilterSheet({required this.ref});
  final WidgetRef ref;

  void _select(BuildContext context, String key) {
    HapticFeedback.selectionClick();
    Navigator.of(context).maybePop();
    // changeSort already reloads the feed and respects the current scope
    // (global / following) so the filter applies to whichever the user is on.
    ref.read(feedProvider.notifier).changeSort(key);
  }

  @override
  Widget build(BuildContext context, WidgetRef sheetRef) {
    final ink = QuestColors.text(context);
    final active = sheetRef.watch(feedSortProvider);
    final hasFilter = active != feedSortRecent;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: QuestColors.bg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink, width: 2),
        boxShadow: [
          BoxShadow(color: ink, offset: const Offset(0, 4), blurRadius: 0),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: ink.withAlpha(80),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                Icon(Icons.filter_list_rounded, color: ink, size: 18),
                const SizedBox(width: 8),
                Text(
                  'FILTER FEED',
                  style: QuestTypography.headlineSmall.copyWith(
                    color: ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const Spacer(),
                if (hasFilter)
                  GestureDetector(
                    onTap: () => _select(context, feedSortRecent),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: QuestColors.softRed.withAlpha(40),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: QuestColors.softRed, width: 1.4),
                      ),
                      child: Text(
                        'CLEAR',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: QuestTypography.labelSmall.copyWith(
                          color: QuestColors.osRedText,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: ink.withAlpha(30)),
          for (var i = 0; i < _filterOptions.length; i++) ...[
            _FilterRow(
              option: _filterOptions[i],
              isActive: active == _filterOptions[i].key,
              onTap: () => _select(context, _filterOptions[i].key),
            ),
            if (i < _filterOptions.length - 1)
              Container(height: 1, color: ink.withAlpha(20)),
          ],
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.option,
    required this.isActive,
    required this.onTap,
  });

  final _FilterOption option;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final tint = isActive ? QuestColors.osPrimary : ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isActive ? QuestColors.osPrimary : ink.withAlpha(20),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                    color: isActive ? ink : ink.withAlpha(80), width: 1.5),
              ),
              child: Icon(option.icon,
                  color: isActive ? QuestColors.osTextOnPrimary : ink,
                  size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                option.label,
                style: QuestTypography.labelMedium.copyWith(
                  color: tint,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            if (isActive)
              const Icon(Icons.check_rounded,
                  color: QuestColors.osPrimary, size: 20),
          ],
        ),
      ),
    );
  }
}
