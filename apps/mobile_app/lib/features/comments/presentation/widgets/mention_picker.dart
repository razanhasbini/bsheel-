import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:shared_ui/shared_ui.dart';

/// [TextEditingController] that paints `@handle` spans in the comment
/// input with the brand violet so the user can see at a glance which
/// part of their text will become a mention. Drop-in replacement for
/// the default controller — swap the type and you get the highlighting
/// for free.
class MentionTextEditingController extends TextEditingController {
  MentionTextEditingController({super.text});

  // Matches `@` followed by 1–30 word chars. Wider than the picker's
  // 3-char minimum because we want the highlight to start as soon as
  // the user types `@a`.
  static final RegExp _mentionRegex =
      RegExp(r'@([\p{L}\p{N}_]{1,30})', unicode: true);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // While the IME is composing, defer to the default behaviour so the
    // composing-underline keeps working — most non-Latin keyboards rely
    // on it. Mention highlighting resumes once composing settles.
    if (value.isComposingRangeValid && withComposing) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final mentionStyle = (style ?? const TextStyle()).copyWith(
      color: QuestColors.osPrimary,
      fontWeight: FontWeight.w800,
    );
    final children = <TextSpan>[];
    var lastEnd = 0;
    for (final match in _mentionRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        children.add(
            TextSpan(text: text.substring(lastEnd, match.start), style: style));
      }
      children.add(TextSpan(text: match.group(0), style: mentionStyle));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      children.add(TextSpan(text: text.substring(lastEnd), style: style));
    }
    if (children.isEmpty) {
      return TextSpan(style: style, text: text);
    }
    return TextSpan(style: style, children: children);
  }
}

/// One row in the mention dropdown — wraps the user's profile and whether
/// the current viewer follows them (so we can rank follows first and tag
/// them in the row).
class MentionCandidate {
  const MentionCandidate({
    required this.profile,
    required this.isFollowing,
  });

  final ProfileModel profile;
  final bool isFollowing;
}

/// Drop-down panel shown above a comment input while the user is typing
/// `@something`. Renders matched profiles with their avatar, display
/// name, handle, and a `FOLLOWING` badge for people the viewer already
/// follows.
class MentionSuggestionsPanel extends StatelessWidget {
  const MentionSuggestionsPanel({
    super.key,
    required this.suggestions,
    required this.loading,
    required this.query,
    required this.onTap,
  });

  final List<MentionCandidate> suggestions;
  final bool loading;
  final String query;
  final ValueChanged<MentionCandidate>? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final showEmpty = !loading && suggestions.isEmpty && query.isNotEmpty;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink, width: 2),
        boxShadow: [
          BoxShadow(
            color: ink,
            offset: const Offset(2, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: loading && suggestions.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : showEmpty
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'NO USERS FOUND',
                    style: QuestTypography.labelSmall.copyWith(
                      color: QuestColors.textDim(context),
                      letterSpacing: 1,
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: ink.withAlpha(24),
                  ),
                  itemBuilder: (context, index) {
                    final candidate = suggestions[index];
                    final profile = candidate.profile;
                    final name = profile.displayName.isNotEmpty
                        ? profile.displayName
                        : profile.username;
                    return InkWell(
                      onTap: onTap == null ? null : () => onTap!(candidate),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            PixelAvatar(
                              imageUrl: profile.avatarUrl,
                              username: profile.username,
                              size: 32,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: QuestTypography.labelSmall.copyWith(
                                      color: ink,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '@${profile.username}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: QuestTypography.bodySmall.copyWith(
                                      color: ink.withAlpha(150),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (candidate.isFollowing)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: QuestColors.osPrimary.withAlpha(24),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: QuestColors.osPrimary,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  'FOLLOWING',
                                  style: QuestTypography.labelSmall.copyWith(
                                    color: QuestColors.osPrimary,
                                    fontSize: 9,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
