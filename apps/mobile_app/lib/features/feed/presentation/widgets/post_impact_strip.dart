import 'package:app_core/app_core.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';

/// Server-computed credit for one of the viewer's own posts (0049).
final postAttributionProvider =
    FutureProvider.autoDispose.family<PostAttribution, String>((ref, postId) {
  return AppBackend.repositories.analytics.attributionForPost(postId);
});

/// "Your post's impact": who saw it, who pressed BSHEEEL from it, and how
/// many of them went on to do the quest — verified.
///
/// Shown only to the author, and only once there is something to say: an
/// empty strip on every new post would teach people to ignore it. It is an
/// addition to the page, so loading and failure draw nothing — the post is
/// the page, this is a footnote to it.
///
/// Counts only. The server never returns who, and this never asks.
class PostImpactStrip extends ConsumerWidget {
  const PostImpactStrip({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attribution = ref.watch(postAttributionProvider(postId)).valueOrNull;
    if (attribution == null || attribution.isEmpty) {
      return const SizedBox.shrink();
    }
    final a = attribution;
    final ink = QuestColors.text(context);
    final parts = <String>[
      if (a.viewers > 0)
        '${a.viewers} ${a.viewers == 1 ? 'person' : 'people'} saw it',
      if (a.bsheeels > 0) "${a.bsheeels} BSHEEEL'D from it",
      if (a.activations > 0) '${a.activations} took the quest',
      if (a.completions > 0) '${a.completions} finished it · verified',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: QuestColors.osAccent.withAlpha(60),
          borderRadius: BorderRadius.circular(QuestSpacing.radiusPanel),
          border: Border.all(color: ink, width: QuestSpacing.cardBorderWidth),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🔥', style: TextStyle(fontSize: 18, height: 1)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "YOUR POST'S IMPACT",
                    style: QuestTypography.osLabelSmall.copyWith(
                      letterSpacing: 1.2,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    parts.join(' · '),
                    style: QuestTypography.osBodySmall.copyWith(color: ink),
                  ),
                  if (a.completions > 0) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Verified means the network and a moderator agreed they '
                      'were there. That credit is yours.',
                      style: QuestTypography.osBodySmall.copyWith(
                        fontSize: 11,
                        color: QuestColors.textDim(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
