import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';

/// A round avatar with a 2px ink border.
///
/// `shared_ui`'s [PixelAvatar] is a rounded *square* (`r10`), which is right
/// for the profile grid but wrong here: every avatar in `09-feed.jpg`,
/// `10-comments.jpg` and `20-post-detail.jpg` is a circle, and the shape is
/// what separates "a person" from "a thing" across those three screens.
///
/// The fallback fill is derived from the username so the same person keeps
/// the same colour between the feed card, the comment row and the detail
/// header — the renders show sky, jade and coral discs doing exactly that.
class PostAvatar extends StatelessWidget {
  const PostAvatar({
    super.key,
    required this.username,
    this.imageUrl,
    this.size = 44,
  });

  final String username;
  final String? imageUrl;
  final double size;

  /// Deterministic tint per handle. Not the *category* palette's job — this
  /// is identity, so it must not change when a user posts in a new category.
  static Color tintFor(String username) {
    const palette = [
      QuestColors.osCool,
      QuestColors.osSuccess,
      QuestColors.osRed,
      QuestColors.osAccent,
      QuestColors.osPrimary,
    ];
    if (username.isEmpty) return QuestColors.osCool;
    var hash = 0;
    for (final unit in username.codeUnits) {
      hash = (hash * 31 + unit) & 0x1fffffff;
    }
    return palette[hash % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final tint = tintFor(username);
    final url = imageUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint,
        shape: BoxShape.circle,
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: url == null || url.isEmpty
          ? _initial(tint)
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              width: size,
              height: size,
              placeholder: (_, __) => _initial(tint),
              errorWidget: (_, __, ___) => _initial(tint),
            ),
    );
  }

  Widget _initial(Color tint) {
    return Center(
      child: Text(
        username.isEmpty ? '?' : username[0].toUpperCase(),
        maxLines: 1,
        style: QuestTypography.osHeadlineMedium.copyWith(
          // The disc is the ground, so the helper picks the ink.
          color: QuestColors.onAccent(tint),
          fontSize: size * 0.38,
          height: 1,
        ),
      ),
    );
  }
}
