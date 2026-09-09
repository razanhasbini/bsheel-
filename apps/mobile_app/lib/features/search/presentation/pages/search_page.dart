import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../../design/bs_widgets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../follows/presentation/widgets/follow_button.dart';
import '../../../quests/data/quest_providers.dart';
import '../providers/search_provider.dart';

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
    final ink = QuestColors.text(context);
    final query = ref.watch(searchQueryProvider).trim();
    final resultsAsync = ref.watch(searchResultsProvider);
    // Three result types so the search isn't siloed onto people-only or
    // quests-only. POSTS surfaces the user's own approved posts plus
    // other people's posts whose quest matches the query — the closest
    // signal to "what others did on a quest like the one I'm on".
    final tabLabels = [l.searchPeople, l.searchQuests, l.searchPosts];

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            _SearchHeader(
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
              ink: ink,
            ),
            // Segmented PEOPLE / QUESTS tab bar — shown once a query is active
            // so the empty/prompt state can use the full vertical space.
            if (query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  QuestSpacing.screenPadding,
                  4,
                  QuestSpacing.screenPadding,
                  10,
                ),
                child: BsSegBar(
                  options: tabLabels,
                  value: tabLabels[_tabIndex],
                  onChange: (label) {
                    setState(() => _tabIndex = tabLabels.indexOf(label));
                  },
                ),
              ),
            Expanded(
              child: query.isEmpty
                  ? _PromptState(ink: ink, onRecentTap: _setQuery)
                  : resultsAsync.when(
                      loading: () => const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (e, _) => _ErrorState(
                        ink: ink,
                        onRetry: () => ref.invalidate(searchResultsProvider),
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
                          return _NoResultsState(ink: ink);
                        }
                        if (_tabIndex == 0) {
                          return _UserResultsList(
                            users: users,
                            onTap: (u) =>
                                _onResultTapped(() => context.pushNamed(
                                      RouteNames.userProfile,
                                      pathParameters: {'userId': u.id},
                                    )),
                          );
                        }
                        if (_tabIndex == 1) {
                          return _QuestResultsList(
                            quests: quests,
                            onTap: (q) =>
                                _onResultTapped(() => context.pushNamed(
                                      RouteNames.questDetails,
                                      pathParameters: {'id': q.id},
                                    )),
                          );
                        }
                        return _PostResultsList(
                          posts: posts,
                          onTap: (p) => _onResultTapped(() => context.pushNamed(
                                RouteNames.feedPostDetails,
                                pathParameters: {'id': p.id},
                              )),
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

// ── Header with back arrow + text field ─────────────────────────────────────

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
    required this.onClear,
    required this.ink,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        QuestSpacing.screenPadding,
        12,
        QuestSpacing.screenPadding,
        12,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: BsMinTouch(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: QuestColors.cardBg(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ink, width: 1.8),
                  boxShadow: [
                    BoxShadow(color: ink, offset: const Offset(1.5, 2)),
                  ],
                ),
                child: Icon(Icons.arrow_back, color: ink, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: QuestColors.cardBg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ink, width: 1.8),
                boxShadow: [
                  BoxShadow(color: ink, offset: const Offset(1.5, 2)),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: ink, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    // Center widget lets the single-line TextField shrink
                    // to its natural line height and sit dead-centre in
                    // the bar's 44px box, instead of being stretched and
                    // anchored to the top by Expanded.
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
                        style: QuestTypography.bodyMedium.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          hintText: hint,
                          hintStyle: TextStyle(
                            color: ink.withAlpha(110),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (controller.text.isNotEmpty)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onClear,
                      // UX-309: 44x44 hit area around the 18px glyph so
                      // the tap target matches the iOS minimum.
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Icon(Icons.close, color: ink, size: 18),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── User results list ──────────────────────────────────────────────────────

class _UserResultsList extends ConsumerWidget {
  const _UserResultsList({required this.users, required this.onTap});
  final List<ProfileModel> users;
  final void Function(ProfileModel) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authSessionProvider);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        QuestSpacing.screenPadding,
        4,
        QuestSpacing.screenPadding,
        32,
      ),
      itemCount: users.length,
      itemBuilder: (context, i) {
        final u = users[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _UserResultTile(
            profile: u,
            isSelf: currentUser?.id == u.id,
            onTap: () => onTap(u),
          ),
        );
      },
    );
  }
}

class _UserResultTile extends StatelessWidget {
  const _UserResultTile({
    required this.profile,
    required this.isSelf,
    required this.onTap,
  });
  final ProfileModel profile;
  final bool isSelf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: QuestColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ink, width: 1.8),
          boxShadow: [
            BoxShadow(color: ink, offset: const Offset(1.5, 2)),
          ],
        ),
        child: Row(
          children: [
            _Avatar(
                url: profile.avatarUrl,
                fallback: profile.displayName,
                ink: ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    profile.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.bodyMedium.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${profile.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.bodySmall.copyWith(
                      color: ink.withAlpha(160),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isSelf)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: QuestColors.accentYellow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ink, width: 1.4),
                ),
                child: Text(
                  'LV ${profile.level}',
                  style: TextStyle(
                    color: ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              )
            else
              FollowButton(targetUserId: profile.id, expand: false),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.fallback, required this.ink});
  final String? url;
  final String fallback;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final initial = fallback.isNotEmpty ? fallback[0].toUpperCase() : '?';
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: QuestColors.osPrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ink, width: 1.8),
        image: (url != null && url!.isNotEmpty)
            ? DecorationImage(
                image: CachedNetworkImageProvider(url!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: (url == null || url!.isEmpty)
          ? Text(
              initial,
              style: const TextStyle(
                color: QuestColors.osTextOnPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }
}

// ── Quest results list ─────────────────────────────────────────────────────

class _QuestResultsList extends StatelessWidget {
  const _QuestResultsList({required this.quests, required this.onTap});
  final List<QuestModel> quests;
  final void Function(QuestModel) onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        QuestSpacing.screenPadding,
        4,
        QuestSpacing.screenPadding,
        32,
      ),
      itemCount: quests.length,
      itemBuilder: (context, i) {
        final q = quests[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _QuestResultTile(
            quest: q,
            onTap: () => onTap(q),
          ),
        );
      },
    );
  }
}

class _QuestResultTile extends ConsumerStatefulWidget {
  const _QuestResultTile({
    required this.quest,
    required this.onTap,
  });
  final QuestModel quest;
  final VoidCallback onTap;

  @override
  ConsumerState<_QuestResultTile> createState() => _QuestResultTileState();
}

class _QuestResultTileState extends ConsumerState<_QuestResultTile> {
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
    final onTap = widget.onTap;
    final ink = QuestColors.text(context);
    final user = ref.watch(authSessionProvider);
    final saved = user == null
        ? false
        : (ref
                .watch(isQuestSavedProvider(
                  (questId: quest.id, userId: user.id),
                ))
                .valueOrNull ??
            false);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: QuestColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ink, width: 1.8),
          boxShadow: [
            BoxShadow(color: ink, offset: const Offset(1.5, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: QuestColors.softRed,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: ink, width: 1.2),
                  ),
                  child: Text(
                    quest.category.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: QuestColors.onAccent(QuestColors.softRed),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: QuestColors.accentYellow,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: ink, width: 1.2),
                  ),
                  child: Text(
                    '+${quest.xpReward} XP',
                    style: TextStyle(
                      color: ink,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              quest.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.bodyMedium.copyWith(
                color: ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (quest.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                quest.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.bodySmall.copyWith(
                  color: ink.withAlpha(170),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: _busy ? null : _toggleSave,
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: saved
                        ? QuestColors.accentYellow
                        : QuestColors.cardBg(context),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: ink, width: 1.6),
                    boxShadow: [
                      BoxShadow(
                          color: ink,
                          offset: const Offset(3, 3),
                          blurRadius: 0),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        saved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        size: 16,
                        color: ink,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          saved ? 'SAVED' : 'BSHEEEL',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: QuestTypography.labelMedium.copyWith(
                            color: ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                    ],
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

// ── Post results list ──────────────────────────────────────────────────────

class _PostResultsList extends StatelessWidget {
  const _PostResultsList({required this.posts, required this.onTap});
  final List<SubmissionModel> posts;
  final void Function(SubmissionModel) onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        QuestSpacing.screenPadding,
        4,
        QuestSpacing.screenPadding,
        32,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.78,
      ),
      itemCount: posts.length,
      itemBuilder: (context, i) =>
          _PostResultTile(post: posts[i], onTap: () => onTap(posts[i])),
    );
  }
}

class _PostResultTile extends StatelessWidget {
  const _PostResultTile({required this.post, required this.onTap});
  final SubmissionModel post;
  final VoidCallback onTap;

  /// First non-empty media URL for the thumbnail, regardless of type.
  /// We render images via [CachedNetworkImage] and videos via a paused
  /// [VideoPlayer] showing the first frame.
  String? _firstMediaUrl() {
    final urls = post.mediaUrls.where((u) => u.trim().isNotEmpty).toList();
    return urls.isEmpty ? null : urls.first;
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final url = _firstMediaUrl();
    final isVideo = url != null && isVideoUrl(url);

    final author = (post.authorDisplayName?.trim().isNotEmpty ?? false)
        ? post.authorDisplayName!
        : (post.authorUsername ?? '');
    final questTitle = post.questTitle ?? '';

    Widget thumbWidget;
    if (url == null) {
      thumbWidget = ColoredBox(
        color: QuestColors.surfaceBg(context),
        child: Icon(Icons.image_outlined, color: ink.withAlpha(140)),
      );
    } else if (isVideo) {
      thumbWidget = _PostVideoThumb(url: url);
    } else {
      thumbWidget = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) =>
            ColoredBox(color: QuestColors.surfaceBg(context)),
        errorWidget: (_, __, ___) => ColoredBox(
          color: QuestColors.surfaceBg(context),
          child: Icon(Icons.image_outlined, color: ink.withAlpha(140)),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: QuestColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ink, width: 1.8),
          boxShadow: [
            BoxShadow(color: ink, offset: const Offset(1.5, 2)),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Media is wrapped in ClipRect because video_player on iOS
            // can paint outside its layout bounds; without this the
            // texture bleeds into the footer for tall portrait sources.
            Expanded(
              child: ClipRect(
                child: SizedBox.expand(child: thumbWidget),
              ),
            ),
            // Fixed-height footer with its own opaque background, so the
            // text always sits on a clean cream strip regardless of the
            // media's aspect ratio.
            Container(
              height: 64,
              width: double.infinity,
              color: QuestColors.cardBg(context),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    questTitle.isNotEmpty ? questTitle.toUpperCase() : 'POST',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.labelSmall.copyWith(
                      color: ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    author.isNotEmpty ? 'by $author' : ' ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.bodySmall.copyWith(
                      color: ink.withAlpha(170),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
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

// ── Empty / prompt / error states ───────────────────────────────────────────

class _PromptState extends ConsumerWidget {
  const _PromptState({required this.ink, required this.onRecentTap});
  final Color ink;
  final ValueChanged<String> onRecentTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final recents = ref.watch(recentSearchesProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        QuestSpacing.screenPadding,
        12,
        QuestSpacing.screenPadding,
        32,
      ),
      children: [
        if (recents.isNotEmpty) ...[
          Row(
            children: [
              Flexible(
                child: Text(
                  l.searchRecent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => ref.read(recentSearchesProvider.notifier).clear(),
                child: Text(
                  l.searchClearRecent,
                  style: TextStyle(
                    color: ink.withAlpha(170),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: recents
                .map((q) => _RecentChip(query: q, onTap: () => onRecentTap(q)))
                .toList(),
          ),
          const SizedBox(height: 28),
        ],
        const SizedBox(height: 8),
        Center(child: Icon(Icons.search, size: 56, color: ink.withAlpha(120))),
        const SizedBox(height: 12),
        Text(
          l.searchPrompt,
          textAlign: TextAlign.center,
          style: QuestTypography.headlineSmall.copyWith(
            color: ink,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l.searchPromptSubtitle,
          textAlign: TextAlign.center,
          style: QuestTypography.bodyMedium.copyWith(color: ink.withAlpha(160)),
        ),
      ],
    );
  }
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({required this.query, required this.onTap});
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: QuestColors.cardBg(context),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: ink, width: 1.5),
          boxShadow: [
            BoxShadow(color: ink, offset: const Offset(1, 1.5)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 14, color: ink.withAlpha(170)),
            const SizedBox(width: 6),
            Text(
              query,
              style: QuestTypography.bodySmall.copyWith(
                color: ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResultsState extends ConsumerWidget {
  const _NoResultsState({required this.ink});
  final Color ink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(QuestSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 56, color: ink.withAlpha(140)),
            const SizedBox(height: 12),
            Text(
              l.searchNoMatches,
              style: QuestTypography.headlineSmall.copyWith(
                color: ink,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l.searchNoMatchesSubtitle,
              textAlign: TextAlign.center,
              style: QuestTypography.bodyMedium
                  .copyWith(color: ink.withAlpha(160)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends ConsumerWidget {
  const _ErrorState({required this.ink, required this.onRetry});
  final Color ink;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(QuestSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: QuestColors.softRed),
            const SizedBox(height: 12),
            Text(
              l.searchFailed,
              style: QuestTypography.headlineSmall.copyWith(
                color: ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                decoration: BoxDecoration(
                  color: QuestColors.accentYellow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ink, width: 2),
                  boxShadow: [
                    BoxShadow(color: ink, offset: const Offset(3, 3)),
                  ],
                ),
                child: Text(
                  l.retry.toUpperCase(),
                  style: TextStyle(
                    color: ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
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

// ── Video thumbnail (paused first frame) ─────────────────────────────────────
//
// Search hits are limited to ~24 results, so spinning up a controller per
// video tile is acceptable. The controller initializes, seeks to frame 0,
// and stays paused — VideoPlayer renders that single frame as the
// thumbnail without ever calling .play().
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
    final ink = QuestColors.text(context);
    if (!_ready || _controller == null) {
      return ColoredBox(
        color: QuestColors.surfaceBg(context),
        child: Center(
          child: Icon(Icons.play_circle_outline,
              size: 32, color: ink.withAlpha(150)),
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
              color: QuestColors.pureBlack.withAlpha(110),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: QuestColors.textPrimary, size: 22),
          ),
        ),
      ],
    );
  }
}
