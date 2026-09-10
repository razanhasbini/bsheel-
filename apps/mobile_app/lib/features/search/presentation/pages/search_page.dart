import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../follows/presentation/widgets/follow_button.dart';
import '../../../profile/domain/player_class.dart';
import '../../../quests/data/quest_providers.dart';
import '../providers/search_provider.dart';

/// Search — built to `export/mobile/18-search.jpg`.
///
/// A single `r14` white field with a 4px ink shadow and a mono ALL-CAPS
/// placeholder; PEOPLE / QUESTS / POSTS as three separate outlined chips in a
/// `Wrap` (not a segmented track); RECENT as stadium chips with a violet
/// CLEAR; and result cards at `r16` where the **first** result carries a sky
/// shadow, which is how the frame marks the top hit.

// Avatar tints for people results, in the frame's cycle order.
const _avatarTints = <Color>[
  QuestColors.osCool,
  QuestColors.osRed,
  QuestColors.osSuccess,
  QuestColors.osAccent,
  QuestColors.textSecondary,
];

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  /// 0 = PEOPLE, 1 = QUESTS, 2 = POSTS.
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    ref.read(searchQueryProvider.notifier).state = value;
  }

  Future<void> _onResultTapped(VoidCallback navigate) async {
    final query = ref.read(searchQueryProvider).trim();
    if (query.isNotEmpty) {
      // Strongest signal that the search was useful — persist it.
      await ref.read(recentSearchesProvider.notifier).add(query);
    }
    if (!mounted) return;
    navigate();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final query = ref.watch(searchQueryProvider).trim();
    final resultsAsync = ref.watch(searchResultsProvider);
    final recents = ref.watch(recentSearchesProvider);

    return Scaffold(
      backgroundColor: QuestColors.osBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: Row(
                children: [
                  // The frame draws no back button, because SEARCH is one of
                  // the five nav tabs there. In this build `/search` still
                  // sits outside the ShellRoute and is pushed, so it needs a
                  // way out. Gated on canPop, which means this disappears by
                  // itself the day the route moves into the shell.
                  if (context.canPop()) ...[
                    _IconButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => context.pop(),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: _SearchField(
                      controller: _controller,
                      focusNode: _focusNode,
                      hint: l.searchHint,
                      onChanged: (v) =>
                          ref.read(searchQueryProvider.notifier).state = v,
                      onClear: () {
                        _controller.clear();
                        ref.read(searchQueryProvider.notifier).state = '';
                        _focusNode.requestFocus();
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < 3; i++)
                    _OptionChip(
                      label: [
                        l.searchPeople,
                        l.searchQuests,
                        l.searchPosts,
                      ][i],
                      selected: _tabIndex == i,
                      onTap: () => setState(() => _tabIndex = i),
                    ),
                ],
              ),
            ),
            Expanded(
              child: query.isEmpty
                  ? _RecentBlock(
                      recents: recents,
                      onTap: _setQuery,
                      onClear: () =>
                          ref.read(recentSearchesProvider.notifier).clear(),
                    )
                  : resultsAsync.when(
                      loading: () => ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        children: const [
                          ArcadeSkeletonList(itemCount: 4, itemHeight: 76),
                        ],
                      ),
                      error: (e, _) => ListView(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                        children: [
                          _DashedPanel(
                            label: 'ERROR',
                            title: l.searchFailed,
                            body: 'Check your connection and try again.',
                          ),
                          const SizedBox(height: 16),
                          ArcadeButton(
                            label: l.retry,
                            variant: ArcadeButtonVariant.secondary,
                            onTap: () => ref.invalidate(searchResultsProvider),
                          ),
                        ],
                      ),
                      data: (results) {
                        final users = results.users;
                        final quests = results.quests;
                        final posts = results.posts;
                        final activeCount = switch (_tabIndex) {
                          0 => users.length,
                          1 => quests.length,
                          _ => posts.length,
                        };
                        if (activeCount == 0) {
                          return ListView(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                            children: [
                              _DashedPanel(
                                label: 'EMPTY STATE',
                                title: l.searchNoMatches,
                                body: l.searchNoMatchesSubtitle,
                              ),
                            ],
                          );
                        }
                        if (_tabIndex == 0) {
                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                            itemCount: users.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) => _UserResultCard(
                              profile: users[i],
                              tint: _avatarTints[i % _avatarTints.length],
                              // The frame gives the top hit a sky shadow.
                              highlighted: i == 0,
                              onTap: () => _onResultTapped(
                                () => context.pushNamed(
                                  RouteNames.userProfile,
                                  pathParameters: {'userId': users[i].id},
                                ),
                              ),
                            ),
                          );
                        }
                        if (_tabIndex == 1) {
                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                            itemCount: quests.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) => _QuestResultCard(
                              quest: quests[i],
                              onTap: () => _onResultTapped(
                                () => context.pushNamed(
                                  RouteNames.questDetails,
                                  pathParameters: {'id': quests[i].id},
                                ),
                              ),
                            ),
                          );
                        }
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.78,
                          ),
                          itemCount: posts.length,
                          itemBuilder: (context, i) => _PostResultTile(
                            post: posts[i],
                            onTap: () => _onResultTapped(
                              () => context.pushNamed(
                                RouteNames.feedPostDetails,
                                pathParameters: {'id': posts[i].id},
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Field ─────────────────────────────────────────────────────────────────

/// White, `r14`, 2px ink, 4px ink shadow, 52 tall. The glyph on the left is
/// the frame's ring, and the placeholder is mono ALL CAPS in muted ink.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
        boxShadow: const [
          BoxShadow(
            color: QuestColors.osTextPrimary,
            offset: Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          const _RingGlyph(),
          const SizedBox(width: 10),
          Expanded(
            child: Center(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                cursorColor: QuestColors.osPrimary,
                // Hide iOS suggestion / autocorrect chrome.
                enableSuggestions: false,
                autocorrect: false,
                style: QuestTypography.osLabelLarge,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  hintText: hint.toUpperCase(),
                  hintStyle: QuestTypography.osLabelLarge
                      .copyWith(color: QuestColors.osTextMuted),
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClear,
              // 44x44 hit area around the 18px glyph.
              child: const SizedBox(
                width: QuestSpacing.minTouchTarget,
                height: QuestSpacing.minTouchTarget,
                child: Center(
                  child: Icon(
                    Icons.close_rounded,
                    color: QuestColors.osTextPrimary,
                    size: 18,
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 14),
        ],
      ),
    );
  }
}

/// The frame's search glyph is a plain ring, not a magnifier.
class _RingGlyph extends StatelessWidget {
  const _RingGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: QuestColors.osTextMuted, width: 2),
      ),
    );
  }
}

// ── Recent ────────────────────────────────────────────────────────────────

class _RecentBlock extends StatelessWidget {
  const _RecentBlock({
    required this.recents,
    required this.onTap,
    required this.onClear,
  });

  final List<String> recents;
  final ValueChanged<String> onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        if (recents.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  l.searchRecent.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.osLabelMedium.copyWith(
                    color: QuestColors.osTextSecondary,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 12,
                  ),
                  child: Text(
                    l.searchClearRecent.toUpperCase(),
                    style: QuestTypography.osLabelMedium.copyWith(
                      color: QuestColors.osPrimary,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final query in recents)
                _RecentChip(query: query, onTap: () => onTap(query)),
            ],
          ),
          const SizedBox(height: 24),
        ],
        _DashedPanel(
          label: 'EMPTY STATE',
          title: l.searchPrompt,
          body: l.searchPromptSubtitle,
        ),
      ],
    );
  }
}

/// Stadium chip — white, 2px ink, `r999`, mono ink. Recent queries only;
/// the scope chips are `r11` because they behave as buttons.
class _RecentChip extends StatelessWidget {
  const _RecentChip({required this.query, required this.onTap});

  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: QuestColors.osCard,
            borderRadius: BorderRadius.circular(QuestSpacing.radiusFull),
            border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          ),
          child: Text(
            query,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osLabelLarge.copyWith(height: 1),
          ),
        ),
      ),
    );
  }
}

/// Selected = ink ground with cream type; the rest are white with a 2px ink
/// outline. Same chip as the leaderboard scope and the language pair.
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        // No `alignment:` on this Container. Inside a Wrap the constraints
        // are bounded, and an Align with no widthFactor stretches the chip
        // to the full run width — which is what made these read as stacked
        // full-width bars instead of a row of chips.
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? QuestColors.osTextPrimary : QuestColors.osCard,
            borderRadius: BorderRadius.circular(QuestSpacing.radiusButton),
            border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          ),
          child: Text(
            label.toUpperCase(),
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

// ── People results ────────────────────────────────────────────────────────

class _UserResultCard extends ConsumerWidget {
  const _UserResultCard({
    required this.profile,
    required this.tint,
    required this.highlighted,
    required this.onTap,
  });

  final ProfileModel profile;
  final Color tint;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authSessionProvider);
    final isSelf = currentUser?.id == profile.id;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: QuestColors.osCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          boxShadow: [
            BoxShadow(
              color:
                  highlighted ? QuestColors.osCool : QuestColors.osTextPrimary,
              offset: const Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          children: [
            _RoundAvatar(
              url: profile.avatarUrl,
              name: profile.username,
              tint: tint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    profile.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osHeadlineLarge.copyWith(
                      fontSize: 18,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'LVL ${profile.level} · '
                    '${playerClassForLevel(profile.level)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osLabelSmall.copyWith(height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isSelf)
              const ArcadeCategoryTag(
                label: 'YOU',
                tint: QuestColors.osAccent,
                compact: true,
              )
            else
              FollowButton(targetUserId: profile.id, expand: false),
          ],
        ),
      ),
    );
  }
}

class _RoundAvatar extends StatelessWidget {
  const _RoundAvatar({
    required this.url,
    required this.name,
    required this.tint,
  });

  final String? url;
  final String name;
  final Color tint;

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint,
        shape: BoxShape.circle,
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: QuestTypography.osHeadlineMedium.copyWith(
          color: QuestColors.onAccent(tint),
          fontSize: 18,
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
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url!,
          fit: BoxFit.cover,
          width: _size,
          height: _size,
          memCacheWidth: (_size * 2).round(),
          placeholder: (_, __) => ColoredBox(color: tint),
          errorWidget: (_, __, ___) => placeholder,
        ),
      ),
    );
  }
}

// ── Quest results ─────────────────────────────────────────────────────────

class _QuestResultCard extends ConsumerStatefulWidget {
  const _QuestResultCard({required this.quest, required this.onTap});

  final QuestModel quest;
  final VoidCallback onTap;

  @override
  ConsumerState<_QuestResultCard> createState() => _QuestResultCardState();
}

class _QuestResultCardState extends ConsumerState<_QuestResultCard> {
  bool _busy = false;

  Future<void> _toggleSave() async {
    if (_busy) return;
    if (guardAccountAction(context, ref)) return;
    final user = ref.read(authSessionProvider);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to save quests')),
      );
      return;
    }
    final key = (questId: widget.quest.id, userId: user.id);
    final saved = ref.read(isQuestSavedProvider(key)).valueOrNull ?? false;
    setState(() => _busy = true);
    HapticFeedback.selectionClick();
    try {
      final repo = ref.read(savedQuestsRepositoryProvider);
      if (saved) {
        await repo.unsaveQuest(widget.quest.id, user.id);
      } else {
        await repo.saveQuest(widget.quest.id, user.id);
      }
      ref.invalidate(isQuestSavedProvider(key));
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(saved
                ? AppLocalizations.of(context)!.removedFromBsheeel
                : AppLocalizations.of(context)!.savedToBsheeel),
            duration: const Duration(seconds: 1),
          ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
            SnackBar(content: Text(mapDbError(e, action: 'save quest'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quest = widget.quest;
    final user = ref.watch(authSessionProvider);
    final saved = user == null
        ? false
        : (ref
                .watch(isQuestSavedProvider(
                  (questId: quest.id, userId: user.id),
                ))
                .valueOrNull ??
            false);
    final tint = QuestColors.category(quest.category);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: QuestColors.osCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          boxShadow: [
            // The category shadow, as on the feed card.
            BoxShadow(color: tint, offset: const Offset(3, 3), blurRadius: 0),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Flexible(
                  child: ArcadeCategoryTag(
                    label: quest.category,
                    tint: tint,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 8),
                ArcadeCategoryTag(
                  label: '+${quest.xpReward} XP',
                  tint: QuestColors.osAccent,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              quest.title.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osHeadlineLarge
                  .copyWith(fontSize: 18, height: 1.15),
            ),
            if (quest.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                quest.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.osBodySmall.copyWith(fontSize: 13),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _busy ? null : _toggleSave,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: QuestSpacing.minTouchTarget,
                  ),
                  child: Center(
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                            saved ? QuestColors.osAccent : QuestColors.osCard,
                        borderRadius:
                            BorderRadius.circular(QuestSpacing.radiusButton),
                        border: Border.all(
                          color: QuestColors.osTextPrimary,
                          width: 2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: QuestColors.osTextPrimary,
                            offset: Offset(3, 3),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: Text(
                        saved ? 'SAVED' : 'BSHEEEL',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: QuestTypography.osHeadlineSmall.copyWith(
                          fontSize: 13,
                          letterSpacing: 1.2,
                          height: 1,
                        ),
                      ),
                    ),
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

// ── Post results ──────────────────────────────────────────────────────────

class _PostResultTile extends StatelessWidget {
  const _PostResultTile({required this.post, required this.onTap});

  final SubmissionModel post;
  final VoidCallback onTap;

  /// First non-empty media URL for the thumbnail, regardless of type.
  String? _firstMediaUrl() {
    final urls = post.mediaUrls.where((u) => u.trim().isNotEmpty).toList();
    return urls.isEmpty ? null : urls.first;
  }

  @override
  Widget build(BuildContext context) {
    final url = _firstMediaUrl();
    final isVideo = url != null && isVideoUrl(url);

    final author = (post.authorDisplayName?.trim().isNotEmpty ?? false)
        ? post.authorDisplayName!
        : (post.authorUsername ?? '');
    final questTitle = post.questTitle ?? '';

    Widget thumb;
    if (url == null) {
      thumb = const ColoredBox(
        color: QuestColors.osSurface,
        child: Center(
          child: Icon(Icons.image_outlined, color: QuestColors.osTextMuted),
        ),
      );
    } else if (isVideo) {
      thumb = _PostVideoThumb(url: url);
    } else {
      thumb = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => const ColoredBox(color: QuestColors.osSurface),
        errorWidget: (_, __, ___) => const ColoredBox(
          color: QuestColors.osSurface,
          child: Center(
            child: Icon(Icons.image_outlined, color: QuestColors.osTextMuted),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: QuestColors.osCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          boxShadow: const [
            BoxShadow(
              color: QuestColors.osTextPrimary,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ClipRect because video_player on iOS can paint outside its
            // layout bounds; without it the texture bleeds into the footer.
            Expanded(
              child: ClipRect(child: SizedBox.expand(child: thumb)),
            ),
            Container(
              height: 64,
              width: double.infinity,
              color: QuestColors.osCard,
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    questTitle.isNotEmpty ? questTitle.toUpperCase() : 'POST',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osHeadlineSmall
                        .copyWith(fontSize: 12, height: 1.2),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    author.isNotEmpty ? 'BY ${author.toUpperCase()}' : ' ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osLabelSmall.copyWith(fontSize: 9),
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

// ── States ────────────────────────────────────────────────────────────────

/// Absent state, as the frame draws it: a dashed 2px outline on the page
/// cream with a mono kicker, a display title and one sentence.
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

/// 44pt square icon button — white ground, `r11`, 2px ink, 3px ink shadow.
class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: QuestSpacing.minTouchTarget,
        height: QuestSpacing.minTouchTarget,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: QuestColors.osCard,
          borderRadius: BorderRadius.circular(QuestSpacing.radiusButton),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          boxShadow: const [
            BoxShadow(
              color: QuestColors.osTextPrimary,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: QuestColors.osTextPrimary),
      ),
    );
  }
}

// ── Video thumbnail (paused first frame) ─────────────────────────────────
//
// Search hits are limited to ~24 results, so spinning up a controller per
// video tile is acceptable. The controller initializes, seeks to frame 0,
// and stays paused — VideoPlayer renders that single frame as the thumbnail
// without ever calling .play().
class _PostVideoThumb extends StatefulWidget {
  const _PostVideoThumb({required this.url});
  final String url;

  @override
  State<_PostVideoThumb> createState() => _PostVideoThumbState();
}

class _PostVideoThumbState extends State<_PostVideoThumb> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await c.initialize();
      await c.setVolume(0);
      await c.seekTo(Duration.zero);
    } catch (_) {
      c.dispose();
      return;
    }
    if (!mounted) {
      c.dispose();
      return;
    }
    setState(() {
      _controller = c;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _controller == null) {
      return const ColoredBox(
        color: QuestColors.osSurface,
        child: Center(
          child: Icon(
            Icons.play_circle_outline,
            size: 32,
            color: QuestColors.osTextMuted,
          ),
        ),
      );
    }
    final size = _controller!.value.size;
    return Stack(
      fit: StackFit.expand,
      children: [
        SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(_controller!),
            ),
          ),
        ),
        // Subtle play glyph so the user reads it as a video at a glance.
        Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: QuestColors.pureBlack.withAlpha(QuestColors.alphaOverlay),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: QuestColors.pureWhite,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }
}
