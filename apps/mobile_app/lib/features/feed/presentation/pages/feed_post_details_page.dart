import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart'
    show CollabFeedMember, CommentModel, FeedPostModel;
import 'package:shared_ui/shared_ui.dart';
import 'package:app_contracts/app_contracts.dart';
import '../../../../design/bs_widgets.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/backend/app_backend.dart';
import '../../../../core/config/deep_link_config.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/providers/current_profile_provider.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../providers/feed_provider.dart';
import '../providers/feed_post_details_provider.dart';
import '../providers/post_realtime_provider.dart';
import '../../../quests/data/quest_providers.dart';
import '../../../submissions/data/submission_providers.dart';
import '../../../leaderboard/presentation/providers/leaderboard_provider.dart';
import '../widgets/collab_vote_button.dart';
import '../../../reactions/presentation/providers/reaction_controller.dart';
import '../../../comments/application/mention_controller.dart';
import '../../../comments/presentation/widgets/comments_section.dart';
import '../../../comments/presentation/widgets/mention_picker.dart';
import '../../../../l10n/app_localizations.dart';
import 'package:app_repositories/app_repositories.dart' show SoftDeleteMode;

class FeedPostDetailsPage extends ConsumerStatefulWidget {
  final String postId;
  const FeedPostDetailsPage({super.key, required this.postId});

  @override
  ConsumerState<FeedPostDetailsPage> createState() =>
      _FeedPostDetailsPageState();
}

class _FeedPostDetailsPageState extends ConsumerState<FeedPostDetailsPage> {
  final _commentController = MentionTextEditingController();
  final _commentFocus = FocusNode();
  bool _submitting = false;
  bool _keyboardVisible = false;
  CommentModel? _replyingTo;
  // Shared @-mention plumbing (debounce, suggestion queries, insert
  // logic) lives in MentionInputController; this page only renders the
  // picker UI.
  late final MentionInputController _mention;

  @override
  void initState() {
    super.initState();
    AppLogger.info('[PostDetails] initState postId=${widget.postId}');
    _commentFocus.addListener(() {
      if (mounted) setState(() => _keyboardVisible = _commentFocus.hasFocus);
    });
    _mention = MentionInputController(
      textController: _commentController,
      focusNode: _commentFocus,
      ref: ref,
      onSuggestionsChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _mention.dispose();
    _commentController.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    if (_submitting) {
      HapticFeedback.lightImpact();
      return;
    }
    final body = _commentController.text.trim();
    if (body.isEmpty) return;
    if (guardAccountAction(context, ref)) return;

    final parentId = _replyingTo?.id;
    AppLogger.info(
        '[PostDetails] Submitting comment on ${widget.postId} (reply=$parentId)');
    setState(() => _submitting = true);
    try {
      final repo = ref.read(commentsRepositoryProvider);
      await repo.addComment(widget.postId, body, parentId: parentId);
      AppLogger.info('[PostDetails] Comment posted successfully');
      ref.read(analyticsProvider).commentAdded(widget.postId);
      _commentController.clear();
      _commentFocus.unfocus();
      setState(() => _replyingTo = null);
      // Invalidate then await the new fetch so the comment list visibly
      // re-renders with the new row before the input bar reactivates.
      ref.invalidate(commentsProvider(widget.postId));
      await ref.read(commentsProvider(widget.postId).future);
    } catch (e) {
      AppLogger.error('[PostDetails] Failed to post comment', e);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(mapDbError(e, action: 'post comment'))),
          );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmAddToFeed(
      BuildContext ctx, WidgetRef ref, String postId) async {
    try {
      await ref
          .read(submissionsRepositoryProvider)
          .setSubmissionVisibility(postId, SoftDeleteMode.visible);
      ref.invalidate(feedProvider);
      ref.invalidate(feedPostDetailsProvider(postId));
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(ctx)!.postAddedToFeed)),
          );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx)
          ..clearSnackBars()
          ..showSnackBar(
              SnackBar(content: Text(mapDbError(e, action: 'restore post'))));
      }
    }
  }

  Future<void> _confirmDeleteFromFeed(
      BuildContext ctx, WidgetRef ref, String postId) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        backgroundColor: QuestColors.cardBg(ctx),
        title: Text(AppLocalizations.of(ctx)!.deleteFromFeed,
            style: QuestTypography.headlineSmall
                .copyWith(color: QuestColors.accentYellow)),
        content: Text(
          AppLocalizations.of(ctx)!.deleteFromFeedDesc,
          style: QuestTypography.bodyMedium
              .copyWith(color: QuestColors.textDim(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(AppLocalizations.of(ctx)!.cancel,
                style: QuestTypography.labelSmall
                    .copyWith(color: QuestColors.textDim(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(AppLocalizations.of(ctx)!.confirm,
                style: QuestTypography.labelSmall
                    .copyWith(color: QuestColors.accentYellow)),
          ),
        ],
      ),
    );
    if (confirmed != true || !ctx.mounted) return;
    try {
      await ref
          .read(submissionsRepositoryProvider)
          .setSubmissionVisibility(postId, SoftDeleteMode.hiddenFromFeed);
      ref.invalidate(feedProvider);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
                content: Text(AppLocalizations.of(ctx)!.postRemovedFromFeed)),
          );
        ctx.pop();
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text(mapDbError(e, action: 'remove from feed'))));
      }
    }
  }

  Future<void> _confirmDeleteFromProfile(
      BuildContext ctx, WidgetRef ref, String postId) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        backgroundColor: QuestColors.cardBg(ctx),
        title: Text(AppLocalizations.of(ctx)!.deleteFromProfile,
            style: QuestTypography.headlineSmall
                .copyWith(color: QuestColors.osRed)),
        content: Text(
          AppLocalizations.of(ctx)!.deleteFromProfileDesc,
          style: QuestTypography.bodyMedium
              .copyWith(color: QuestColors.textDim(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(AppLocalizations.of(ctx)!.cancel,
                style: QuestTypography.labelSmall
                    .copyWith(color: QuestColors.textDim(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(AppLocalizations.of(ctx)!.delete,
                style: QuestTypography.labelSmall
                    .copyWith(color: QuestColors.osRed)),
          ),
        ],
      ),
    );
    if (confirmed != true || !ctx.mounted) return;
    try {
      // Capture the post's owner BEFORE updating, so we can invalidate
      // the per-user submissions cache too (used when other people view
      // this profile). Otherwise their cache holds the deleted post
      // until they pull-to-refresh.
      final ownerId =
          ref.read(feedPostDetailsProvider(postId)).valueOrNull?.userId;
      await ref
          .read(submissionsRepositoryProvider)
          .setSubmissionVisibility(postId, SoftDeleteMode.deleted);
      // The DB trigger revokes XP / decrements quests_completed; refresh
      // every UI that surfaces those derived values so the leaderboard,
      // profile XP pill, and badges drop immediately rather than waiting
      // for the next manual pull-to-refresh.
      ref.invalidate(feedProvider);
      ref.invalidate(currentProfileProvider);
      ref.invalidate(questHistoryProvider);
      ref.invalidate(userSubmissionsProvider);
      if (ownerId != null) {
        ref.invalidate(userSubmissionsByUserProvider(ownerId));
        ref.invalidate(questHistoryByUserProvider(ownerId));
      }
      ref.invalidate(leaderboardProvider);
      ref.invalidate(followingLeaderboardProvider);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
                content:
                    Text(AppLocalizations.of(ctx)!.postDeletedPermanently)),
          );
        ctx.pop();
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(mapDbError(e))));
      }
    }
  }

  Future<void> _showReportDialog(
      BuildContext ctx, String type, String id) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: ctx,
      builder: (c) => AlertDialog(
        backgroundColor: QuestColors.cardBg(ctx),
        title: Text('REPORT CONTENT',
            style: QuestTypography.headlineSmall
                .copyWith(color: QuestColors.accentYellow)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          style: QuestTypography.bodyMedium,
          decoration: const InputDecoration(
            hintText: 'Why are you reporting this?',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('CANCEL',
                style: QuestTypography.labelSmall
                    .copyWith(color: QuestColors.textDim(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: Text('REPORT',
                style: QuestTypography.labelSmall
                    .copyWith(color: QuestColors.accentYellow)),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
    if (reason == null || reason.isEmpty || !ctx.mounted) return;
    try {
      await AppBackend.repositories.account.reportContent(
        type: type,
        id: id,
        reason: reason,
      );
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(content: Text('Report submitted. Thank you.')),
          );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(mapDbError(e, action: 'report'))),
          );
      }
    }
  }

  Future<void> _showBlockDialog(
      BuildContext ctx, String userId, String username) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        backgroundColor: QuestColors.cardBg(ctx),
        title: Text('BLOCK @$username',
            style: QuestTypography.headlineSmall
                .copyWith(color: QuestColors.osRed)),
        content: Text(
          'Blocking will:\n'
          '- Hide their posts from your feed\n'
          '- Remove follows between you\n'
          '- Notify our moderation team\n\n'
          'You can unblock from Settings.',
          style: QuestTypography.bodyMedium
              .copyWith(color: QuestColors.textDim(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('CANCEL',
                style: QuestTypography.labelSmall
                    .copyWith(color: QuestColors.textDim(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('BLOCK',
                style: QuestTypography.labelSmall
                    .copyWith(color: QuestColors.osRed)),
          ),
        ],
      ),
    );
    if (confirmed != true || !ctx.mounted) return;
    try {
      await AppBackend.repositories.account.blockUser(userId);
      ref.invalidate(feedProvider);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text('@$username has been blocked.')),
          );
        ctx.pop();
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(mapDbError(e, action: 'block user'))),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Subscribes to reactions/comments changes on this post and invalidates
    // the data providers so vote/comment counts refresh live without the
    // viewer having to leave and re-enter the page.
    ref.watch(postRealtimeProvider(widget.postId));
    final postAsync = ref.watch(feedPostDetailsProvider(widget.postId));
    final currentUser = ref.watch(authSessionProvider);

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: postAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (e, st) {
            AppLogger.error(
                '[PostDetails] Failed to load post ${widget.postId}', e);
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      color: QuestColors.textDim(context), size: 48),
                  const SizedBox(height: QuestSpacing.md),
                  Text('FAILED TO LOAD', style: QuestTypography.headlineSmall),
                  const SizedBox(height: QuestSpacing.sm),
                  GestureDetector(
                    onTap: () =>
                        ref.invalidate(feedPostDetailsProvider(widget.postId)),
                    child: Text(
                      'TAP TO RETRY',
                      style: QuestTypography.labelSmall
                          .copyWith(color: QuestColors.accent(context)),
                    ),
                  ),
                ],
              ),
            );
          },
          data: (post) {
            AppLogger.info(
                '[PostDetails] Loaded post ${post.id} — ${post.questTitle}');
            final counts = getEffectiveVoteCounts(ref, post.id, post);
            final upvotes = counts[ReactionType.upvote] ?? 0;
            final downvotes = counts[ReactionType.downvote] ?? 0;

            final myVoteType = currentUser == null
                ? null
                : getEffectiveVoteType(ref, post.id, currentUser.id);

            final isSaved = currentUser == null
                ? false
                : getEffectiveSaved(ref, post.id, currentUser.id);

            void vote(String type) {
              if (currentUser == null) return;
              AppLogger.info('[PostDetails] Voting $type on ${post.id}');
              toggleVote(
                ref: ref,
                submissionId: post.id,
                userId: currentUser.id,
                voteType: type,
                baseCounts: counts,
              );
            }

            final (catColor, catLabel) = _categoryStyle(post.questCategory);

            return Column(
              children: [
                // ── Top bar ──────────────────────────────────────────────
                _TopBar(
                  username: post.username,
                  displayName: post.displayName,
                  bio: post.bio,
                  avatarUrl: post.avatarUrl,
                  catColor: catColor,
                  userId: post.userId,
                  currentUserId: currentUser?.id,
                  isOwner: currentUser?.id == post.userId,
                  collabLabel: post.isCollab
                      ? (post.collabMode == CollabMode.versus
                          ? 'VERSUS QUEST · ${post.collabMemberCount} PLAYERS'
                          : 'COOP QUEST · ${post.collabMemberCount} PLAYERS')
                      : null,
                  collabAccent: post.isCollab
                      ? (post.collabMode == CollabMode.versus
                          ? QuestColors.osRed
                          : QuestColors.osSuccess)
                      : null,
                  // Deep-link cold-start: there's nothing to pop, so fall
                  // back to /home so the user is never stranded.
                  onBack: () => context.canPop()
                      ? context.pop()
                      : context.goNamed(RouteNames.home),
                  onShare: () {
                    ref.read(analyticsProvider).postShared(post.id);
                    SharePlus.instance.share(
                      ShareParams(
                        text:
                            'Check out this quest by @${post.username} on BSHEEL!\n\n${DeepLinkConfig.postLink(post.id)}',
                      ),
                    );
                  },
                  showInFeed: post.showInFeed,
                  visibility: post.visibility,
                  onAddToFeed: () => _confirmAddToFeed(context, ref, post.id),
                  onDeleteFromFeed: () =>
                      _confirmDeleteFromFeed(context, ref, post.id),
                  onDeleteFromProfile: () =>
                      _confirmDeleteFromProfile(context, ref, post.id),
                  onReport: () =>
                      _showReportDialog(context, 'submission', post.id),
                  onBlock: () =>
                      _showBlockDialog(context, post.userId, post.username),
                ),

                // ── Scrollable body ──────────────────────────────────────
                Expanded(
                  child: RefreshIndicator(
                    color: QuestColors.osRed,
                    onRefresh: () async {
                      // Pull to refresh: force-reload the post + its comments.
                      ref.invalidate(feedPostDetailsProvider(widget.postId));
                      ref.invalidate(commentsProvider(widget.postId));
                      // Wait for the new data so the spinner doesn't vanish
                      // before the fresh values arrive.
                      await Future.wait([
                        ref.read(feedPostDetailsProvider(widget.postId).future),
                        ref.read(commentsProvider(widget.postId).future),
                      ]);
                    },
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        // Mode banner moved INTO the top bar (red pill between
                        // the back button and the three-dots menu) so it shares
                        // the same row as the navigation chrome.

                        // Collab participants header (avatar = vote button + name + bio + follow)
                        if (post.isCollab && post.collabMembers.isNotEmpty)
                          SliverToBoxAdapter(
                            child: _CollabParticipantsHeader(
                              members: post.collabMembers,
                              groupId: post.collabGroupId ?? '',
                              mode: post.collabMode,
                              currentUserId: currentUser?.id,
                            ),
                          ),

                        // ── Media card with category + collab overlay ───
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                            child: _PostMediaCard(post: post),
                          ),
                        ),

                        // ── Reaction bar (chunky pills) ─────────────────
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                            child: _PostActionBar(
                              upvotes: upvotes,
                              downvotes: downvotes,
                              myVoteType: myVoteType,
                              isSaved: isSaved,
                              // Collab/versus posts use per-member voting in
                              // the participants header above; hide global up/down.
                              showVotes: !post.isCollab,
                              onUpvote: currentUser == null
                                  ? null
                                  : () => vote(ReactionType.upvote),
                              onDownvote: currentUser == null
                                  ? null
                                  : () => vote(ReactionType.downvote),
                              onSave: currentUser == null
                                  ? null
                                  : () => toggleSavePost(
                                        ref: ref,
                                        submissionId: post.id,
                                        userId: currentUser.id,
                                      ),
                              onShare: () {
                                ref.read(analyticsProvider).postShared(post.id);
                                SharePlus.instance.share(
                                  ShareParams(
                                    text:
                                        'Check out this quest by @${post.username} on BSHEEL!\n\n${DeepLinkConfig.postLink(post.id)}',
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        // ── Quest info card (title, desc, captions, xp, time) ──
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                            child: _PostInfoCard(
                              post: post,
                              timeAgo: _timeAgo(post.submittedAt),
                            ),
                          ),
                        ),

                        // ── Comments section header ─────────────────────
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 22, 14, 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 2,
                                  color: QuestColors.text(context),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    AppLocalizations.of(context)!
                                        .comments
                                        .toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        QuestTypography.headlineSmall.copyWith(
                                      color: QuestColors.text(context),
                                      fontSize: 14,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Container(
                                    height: 2,
                                    color: QuestColors.text(context)
                                        .withAlpha(QuestColors.alphaWhisper),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Comments list
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                            child: CommentsSection(
                              submissionId: post.id,
                              onReplyTap: (comment) {
                                setState(() => _replyingTo = comment);
                                _commentFocus.requestFocus();
                              },
                            ),
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 80)),
                      ],
                    ),
                  ),
                ),

                // ── Fixed bottom comment input ────────────────────────────
                _CommentInputBar(
                  controller: _commentController,
                  focusNode: _commentFocus,
                  submitting: _submitting,
                  keyboardVisible: _keyboardVisible,
                  onSend: _addComment,
                  onDismiss: () {
                    _commentFocus.unfocus();
                    setState(() => _replyingTo = null);
                  },
                  currentUser: currentUser,
                  replyingTo: _replyingTo,
                  onCancelReply: () => setState(() => _replyingTo = null),
                  mentionSuggestions: _mention.suggestions,
                  mentionLoading: _mention.loading,
                  mentionQuery: _mention.query,
                  onMentionTap: _mention.insertMention,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    // Past 30 days → fall back to a fixed date for the post-detail
    // header. Everything shorter delegates to the shared formatter.
    if (diff.inDays >= 30) return DateFormat('d MMM yyyy').format(dt);
    return timeAgoLong(dt);
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.username,
    required this.displayName,
    this.bio,
    required this.avatarUrl,
    required this.catColor,
    required this.userId,
    required this.currentUserId,
    required this.onBack,
    required this.onShare,
    required this.isOwner,
    this.showInFeed = true,
    this.visibility = 'visible',
    this.onAddToFeed,
    this.onDeleteFromFeed,
    this.onDeleteFromProfile,
    this.onReport,
    this.onBlock,
    this.collabLabel,
    this.collabAccent,
  });

  final String username;
  final String displayName;
  final String? bio;
  final String? avatarUrl;
  final Color catColor;
  final String userId;
  final String? currentUserId;
  final VoidCallback onBack;
  final VoidCallback onShare;
  final bool isOwner;
  final bool showInFeed;
  final String visibility;
  final VoidCallback? onAddToFeed;
  final VoidCallback? onDeleteFromFeed;
  final VoidCallback? onDeleteFromProfile;
  final VoidCallback? onReport;
  final VoidCallback? onBlock;
  final String? collabLabel;
  final Color? collabAccent;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    // The collab pill's ground is either an accent fill (coral / jade,
    // which take ink) or the ink panel colour used when there is no
    // collab accent (which takes white).
    final collabPillAccent = collabAccent;
    final onCollabPill = collabPillAccent == null
        ? QuestColors.pureWhite
        : QuestColors.onAccent(collabPillAccent);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: QuestColors.bg(context),
        border: Border(
          bottom: BorderSide(color: ink, width: 2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            GestureDetector(
              onTap: onBack,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: QuestColors.cardBg(context),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: ink, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: ink,
                      offset: const Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(Icons.arrow_back_rounded, size: 18, color: ink),
              ),
            ),
            const SizedBox(width: 10),
            if (collabLabel != null) ...[
              // Compact arcade-pop mode pill — fills the slot between the
              // back button and the three-dots menu. Replaces the previous
              // green-text label and the full-width banner that lived
              // under the top bar.
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: collabAccent ?? QuestColors.text(context),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: ink, width: 2),
                    boxShadow: [
                      BoxShadow(color: ink, offset: const Offset(2, 2)),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        (collabAccent == QuestColors.osRed)
                            ? Icons.bolt_rounded
                            : Icons.handshake_rounded,
                        size: 16,
                        color: onCollabPill,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          collabLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onCollabPill,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.pushNamed(
                  RouteNames.userProfile,
                  pathParameters: {'userId': userId},
                ),
                child: PixelAvatar(
                  imageUrl: avatarUrl,
                  username: username,
                  size: 42,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.pushNamed(
                    RouteNames.userProfile,
                    pathParameters: {'userId': userId},
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FitText(
                        displayName.isNotEmpty ? displayName : username,
                        minFontSize: 11,
                        style: QuestTypography.headlineSmall.copyWith(
                          fontSize: 16,
                          color: QuestColors.text(context),
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (bio != null && bio!.isNotEmpty)
                        Text(
                          bio!,
                          style: QuestTypography.bodySmall.copyWith(
                            color: QuestColors.text(context).withAlpha(160),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ),
            ],
            Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(left: 6),
              decoration: BoxDecoration(
                color: QuestColors.cardBg(context),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: ink, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: ink,
                    offset: const Offset(2, 2),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, size: 18, color: ink),
                padding: EdgeInsets.zero,
                iconSize: 18,
                splashRadius: 18,
                color: QuestColors.cardBg(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: ink, width: 2),
                ),
                onSelected: (value) {
                  if (value == 'add_feed') onAddToFeed?.call();
                  if (value == 'delete_feed') onDeleteFromFeed?.call();
                  if (value == 'delete_profile') onDeleteFromProfile?.call();
                  if (value == 'report') onReport?.call();
                  if (value == 'block') onBlock?.call();
                },
                itemBuilder: (ctx) {
                  final l = AppLocalizations.of(ctx)!;
                  final isInFeed = showInFeed && visibility == 'visible';
                  return [
                    if (isOwner && !isInFeed) ...[
                      PopupMenuItem(
                        value: 'add_feed',
                        child: Row(
                          children: [
                            const Icon(Icons.visibility_outlined,
                                size: 16, color: QuestColors.osSuccessText),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l.addToFeed,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: QuestTypography.labelLarge.copyWith(
                                  color: QuestColors.osSuccessText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (isOwner && isInFeed) ...[
                      PopupMenuItem(
                        value: 'delete_feed',
                        child: Row(
                          children: [
                            const Icon(Icons.visibility_off_outlined,
                                size: 16, color: QuestColors.accentYellow),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l.hideFromFeed,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: QuestTypography.labelLarge.copyWith(
                                  color: QuestColors.osAccentText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (isOwner) ...[
                      PopupMenuItem(
                        value: 'delete_profile',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_forever_outlined,
                                size: 16, color: QuestColors.osRed),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l.permanentlyDelete,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: QuestTypography.labelLarge.copyWith(
                                  color: QuestColors.osRedText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (!isOwner) ...[
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'report',
                        child: Row(
                          children: [
                            const Icon(Icons.flag_outlined,
                                size: 16, color: QuestColors.accentYellow),
                            const SizedBox(width: 8),
                            Text(
                              'REPORT',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: QuestTypography.labelLarge.copyWith(
                                color: QuestColors.osAccentText,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'block',
                        child: Row(
                          children: [
                            const Icon(Icons.block,
                                size: 16, color: QuestColors.osRed),
                            const SizedBox(width: 8),
                            Text(
                              'BLOCK USER',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: QuestTypography.labelLarge.copyWith(
                                color: QuestColors.osRedText,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ];
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Fixed bottom comment input ────────────────────────────────────────────────

class _CommentInputBar extends StatelessWidget {
  const _CommentInputBar({
    required this.controller,
    required this.focusNode,
    required this.submitting,
    required this.keyboardVisible,
    required this.onSend,
    required this.onDismiss,
    required this.currentUser,
    this.replyingTo,
    this.onCancelReply,
    this.mentionSuggestions = const [],
    this.mentionLoading = false,
    this.mentionQuery = '',
    this.onMentionTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitting;
  final bool keyboardVisible;
  final VoidCallback onSend;
  final VoidCallback onDismiss;
  final dynamic currentUser;
  final CommentModel? replyingTo;
  final VoidCallback? onCancelReply;
  final List<MentionCandidate> mentionSuggestions;
  final bool mentionLoading;
  final String mentionQuery;
  final ValueChanged<MentionCandidate>? onMentionTap;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    if (currentUser == null) return SizedBox(height: bottomPad);

    final ink = QuestColors.text(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        bottom: keyboardHeight > 0 ? 10 : bottomPad + 10,
        top: 10,
        left: 12,
        right: 12,
      ),
      decoration: BoxDecoration(
        color: QuestColors.bg(context),
        border: Border(top: BorderSide(color: ink, width: 2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mentionLoading || mentionSuggestions.isNotEmpty)
            MentionSuggestionsPanel(
              suggestions: mentionSuggestions,
              loading: mentionLoading,
              query: mentionQuery,
              onTap: onMentionTap,
            ),
          if (replyingTo != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color:
                    QuestColors.osPrimary.withAlpha(QuestColors.alphaWhisper),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: QuestColors.osPrimary, width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.reply_rounded,
                      size: 14, color: QuestColors.osPrimary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Replying to ${replyingTo!.displayName.isNotEmpty ? replyingTo!.displayName : replyingTo!.username}',
                      style: QuestTypography.labelSmall.copyWith(
                        color: QuestColors.osPrimary,
                        fontSize: 11,
                        letterSpacing: 0.4,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: onCancelReply,
                    behavior: HitTestBehavior.opaque,
                    child: const Icon(Icons.close_rounded,
                        size: 16, color: QuestColors.osPrimary),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: QuestColors.cardBg(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ink, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: ink,
                        offset: const Offset(3, 3),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: QuestTypography.bodyMedium.copyWith(color: ink),
                    cursorColor: QuestColors.osPrimary,
                    maxLength: 500,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      hintText:
                          replyingTo != null ? 'Reply…' : 'Add a comment…',
                      hintStyle: QuestTypography.bodyMedium.copyWith(
                        color: ink.withAlpha(QuestColors.alphaInkWeak),
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      counterText: '',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (keyboardVisible) ...[
                GestureDetector(
                  onTap: onDismiss,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: QuestColors.cardBg(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ink, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: ink,
                          offset: const Offset(3, 3),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child:
                        Icon(Icons.keyboard_hide_rounded, size: 18, color: ink),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              GestureDetector(
                onTap: submitting ? null : onSend,
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: submitting
                        ? QuestColors.cardBg(context)
                        : QuestColors.accentYellow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ink, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: ink,
                        offset: const Offset(3, 3),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: submitting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(ink),
                          ),
                        )
                      : const Icon(Icons.send_rounded,
                          size: 18, color: QuestColors.accentYellowInk),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Category helpers ──────────────────────────────────────────────────────────

(Color, String) _categoryStyle(String category) {
  return switch (category.toLowerCase()) {
    'fitness' => (QuestColors.osSuccess, 'FITNESS'),
    'creativity' => (QuestColors.accentYellow, 'CREATE'),
    'social' => (QuestColors.osSuccess, 'SOCIAL'),
    'learning' => (QuestColors.violet, 'LEARN'),
    'adventure' => (QuestColors.osSuccess, 'ADVENTURE'),
    _ => (QuestColors.textMuted, category.toUpperCase()),
  };
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text, this.maxLines = 2});
  final String text;
  final int maxLines;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = QuestTypography.bodySmall.copyWith(
      color: QuestColors.text(context),
      fontSize: 12,
      height: 1.5,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: widget.maxLines,
          textDirection: ui.TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        final overflows = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _expanded ? null : widget.maxLines,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (overflows && !_expanded)
              GestureDetector(
                onTap: () => setState(() => _expanded = true),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Read more',
                    style: QuestTypography.labelSmall.copyWith(
                      color: QuestColors.text(context).withAlpha(140),
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Media block ───────────────────────────────────────────────────────────────

class _MediaBlock extends StatefulWidget {
  const _MediaBlock({required this.post, required this.urls});
  final dynamic post;
  final List<String> urls;

  @override
  State<_MediaBlock> createState() => _MediaBlockState();
}

class _MediaBlockState extends State<_MediaBlock> {
  final _pageController = PageController();
  int _page = 0;

  /// Source aspect ratios reported by `_VideoSlide` after each video's
  /// controller initializes. Used so single-video posts adopt the natural
  /// aspect for the media frame instead of being letterboxed inside 4:5.
  final Map<String, double> _videoAspects = {};

  /// Same idea for single-image posts — landscape and tall-portrait
  /// uploads adopt their source aspect (clamped) instead of being
  /// centre-cropped to 4:5. Multi-asset posts stay on 4:5.
  final Map<String, double> _imageAspects = {};

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _isVideo(String url) =>
      isVideoUrl(url) ||
      (widget.post.mediaType == MediaType.video && widget.urls.length == 1);

  void _reportVideoAspect(String url, double aspect) {
    if (_videoAspects[url] == aspect) return;
    if (!mounted) return;
    setState(() => _videoAspects[url] = aspect);
  }

  void _reportImageAspect(String url, double aspect) {
    if (_imageAspects[url] == aspect) return;
    if (!mounted) return;
    setState(() => _imageAspects[url] = aspect);
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls.where((u) => u.isNotEmpty).toList();

    if (urls.isEmpty) {
      return SizedBox(
        height: 280,
        child: ColoredBox(
          color: QuestColors.surfaceBg(context),
          child: Center(
            child: Icon(Icons.image_outlined,
                size: 56, color: QuestColors.textDim(context)),
          ),
        ),
      );
    }

    // Single-video posts adopt the source aspect ratio (clamped to a sane
    // band) so the video fills its frame edge-to-edge. Images and
    // multi-media posts keep the 4:5 portrait frame.
    final isSingleAsset = urls.length == 1;
    final isSingleVideo = isSingleAsset && _isVideo(urls[0]);
    final isSingleImage = isSingleAsset && !_isVideo(urls[0]);
    double? reportedAspect;
    if (isSingleVideo) {
      reportedAspect = _videoAspects[urls[0]];
    } else if (isSingleImage) {
      reportedAspect = _imageAspects[urls[0]];
    }
    final frameAspect =
        reportedAspect == null ? 4 / 5 : reportedAspect.clamp(9 / 16, 16 / 9);
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: frameAspect,
          child: ColoredBox(
            color: QuestColors.surfaceBg(context),
            child: PageView.builder(
              controller: _pageController,
              itemCount: urls.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final url = urls[i];
                if (_isVideo(url)) {
                  return _VideoSlide(
                    url: url,
                    allUrls: urls,
                    indexInAll: i,
                    onAspectKnown: (a) => _reportVideoAspect(url, a),
                  );
                }
                return _ImageSlide(
                  url: url,
                  allUrls: urls,
                  indexInAll: i,
                  useContain: isSingleImage,
                  onAspectKnown:
                      isSingleImage ? (a) => _reportImageAspect(url, a) : null,
                );
              },
            ),
          ),
        ),
        if (urls.length > 1) ...[
          Positioned(
            top: QuestSpacing.sm,
            right: QuestSpacing.sm,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: QuestColors.pureBlack.withAlpha(160),
                borderRadius: BorderRadius.circular(QuestSpacing.radiusFull),
                border: Border.all(color: QuestColors.pureWhite.withAlpha(60)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  '${_page + 1} / ${urls.length}',
                  style: TextStyle(
                      color: QuestColors.text(context),
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: QuestSpacing.sm,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(urls.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: active ? 16 : 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: active
                        ? QuestColors.textPrimary
                        : QuestColors.textPrimary.withAlpha(80),
                    borderRadius:
                        BorderRadius.circular(QuestSpacing.radiusFull),
                  ),
                );
              }),
            ),
          ),
        ],
      ],
    );
  }
}

class _ImageSlide extends StatefulWidget {
  const _ImageSlide({
    required this.url,
    required this.allUrls,
    required this.indexInAll,
    this.useContain = false,
    this.onAspectKnown,
  });
  final String url;
  // Whole post media list + this slide's index, so the fullscreen viewer
  // opens as a swipeable carousel rather than just this single image.
  final List<String> allUrls;
  final int indexInAll;
  final bool useContain;
  final ValueChanged<double>? onAspectKnown;

  @override
  State<_ImageSlide> createState() => _ImageSlideState();
}

class _ImageSlideState extends State<_ImageSlide> {
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _resolveAspect();
  }

  @override
  void didUpdateWidget(covariant _ImageSlide old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _detach();
      _resolveAspect();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  void _resolveAspect() {
    final cb = widget.onAspectKnown;
    if (cb == null) return;
    final provider = CachedNetworkImageProvider(widget.url);
    _stream = provider.resolve(const ImageConfiguration());
    _listener = ImageStreamListener((info, _) {
      final w = info.image.width;
      final h = info.image.height;
      if (w > 0 && h > 0 && mounted) cb(w / h);
    }, onError: (_, __) {/* ignore */});
    _stream!.addListener(_listener!);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openPostMediaFullscreen(
        context,
        urls: widget.allUrls,
        initialIndex: widget.indexInAll,
      ),
      child: CachedNetworkImage(
        imageUrl: widget.url,
        // contain when the parent frame already matches source aspect
        // (single-image posts) so off-aspect images aren't cropped;
        // cover for the multi-image carousel where the frame is fixed.
        fit: widget.useContain ? BoxFit.contain : BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.medium,
        // Decode at physical pixels so high-DPI devices get a sharp bitmap.
        memCacheWidth: (MediaQuery.of(context).size.width *
                MediaQuery.of(context).devicePixelRatio)
            .round(),
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, __) => ColoredBox(
          color: QuestColors.surfaceBg(context),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => ColoredBox(
          color: QuestColors.surfaceBg(context),
          child: Center(
            child: Icon(Icons.image_outlined,
                size: 56, color: QuestColors.textDim(context)),
          ),
        ),
      ),
    );
  }
}

class _VideoSlide extends StatefulWidget {
  const _VideoSlide({
    required this.url,
    required this.allUrls,
    required this.indexInAll,
    this.onAspectKnown,
  });
  final String url;
  final List<String> allUrls;
  final int indexInAll;
  final ValueChanged<double>? onAspectKnown;

  @override
  State<_VideoSlide> createState() => _VideoSlideState();
}

class _VideoSlideState extends State<_VideoSlide> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    // Default volume = 1.0 (audio on). We don't call setVolume(0).
    _videoController.initialize().then((_) {
      if (!mounted) return;
      final aspect = _videoController.value.aspectRatio;
      if (aspect > 0) widget.onAspectKnown?.call(aspect);
      setState(() {
        _chewieController = ChewieController(
          videoPlayerController: _videoController,
          // Reels-style: start playing as soon as the player is ready and
          // loop so the user doesn't have to tap "play" — fixes the
          // perceived "two taps to start" issue.
          autoPlay: true,
          looping: true,
          showControlsOnInitialize: false,
          aspectRatio: _videoController.value.aspectRatio,
          errorBuilder: (context, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 48, color: QuestColors.textDim(context)),
                const SizedBox(height: 8),
                Text('Could not load video',
                    style: TextStyle(
                        color: QuestColors.textDim(context), fontSize: 12)),
              ],
            ),
          ),
        );
      });
    }).catchError((_) {
      if (mounted) setState(() => _hasError = true);
    });
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return ColoredBox(
        color: QuestColors.surfaceBg(context),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off,
                  size: 56, color: QuestColors.textDim(context)),
              const SizedBox(height: 8),
              Text('Failed to load video',
                  style: TextStyle(
                      color: QuestColors.textDim(context), fontSize: 12)),
            ],
          ),
        ),
      );
    }
    if (_chewieController == null) {
      return ColoredBox(
        color: QuestColors.surfaceBg(context),
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    // Honest aspect ratio: letterbox onto a black surface so the full video
    // frame is visible. A small "expand" button opens our unified
    // fullscreen viewer, which works as a swipeable carousel across the
    // post's other media too.
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: QuestColors.pureBlack,
          child: Center(
            child: AspectRatio(
              aspectRatio: _videoController.value.aspectRatio == 0
                  ? 1
                  : _videoController.value.aspectRatio,
              child: Chewie(controller: _chewieController!),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openPostMediaFullscreen(
              context,
              urls: widget.allUrls,
              initialIndex: widget.indexInAll,
            ),
            child: BsMinTouch(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: QuestColors.pureBlack.withAlpha(140),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: QuestColors.pureWhite.withAlpha(80), width: 1),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.fullscreen_rounded,
                    color: QuestColors.textPrimary, size: 18),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Vertical list of collab participants. Each row's avatar IS the
/// arcade-pop vote button (tap to toggle vote, long-press to open profile);
/// name + bio sit beside it, and a follow button trails on the right.
/// Local state mirrors `widget.members` so optimistic vote updates land
/// without a feed refetch.
class _CollabParticipantsHeader extends ConsumerStatefulWidget {
  final List<CollabFeedMember> members;
  final String groupId;
  final String? mode;
  final String? currentUserId;

  const _CollabParticipantsHeader({
    required this.members,
    required this.groupId,
    required this.mode,
    required this.currentUserId,
  });

  @override
  ConsumerState<_CollabParticipantsHeader> createState() =>
      _CollabParticipantsHeaderState();
}

class _CollabParticipantsHeaderState
    extends ConsumerState<_CollabParticipantsHeader> {
  late List<CollabFeedMember> _members;

  @override
  void initState() {
    super.initState();
    _members = List.of(widget.members);
  }

  @override
  void didUpdateWidget(covariant _CollabParticipantsHeader old) {
    super.didUpdateWidget(old);
    if (!identical(old.members, widget.members)) {
      _members = List.of(widget.members);
    }
  }

  void _applyVote(int index, {required bool nowVoted, required int newCount}) {
    setState(() {
      _members[index] = _members[index].copyWith(
        viewerVoted: nowVoted,
        voteCount: newCount,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final navyColor = QuestColors.text(context);
    final isVersus = widget.mode == CollabMode.versus;
    final accent = isVersus ? QuestColors.osRed : QuestColors.osSuccess;

    int maxVotes = 0;
    if (isVersus) {
      for (final m in _members) {
        if (m.voteCount > maxVotes) maxVotes = m.voteCount;
      }
    }

    final visibleIndices = <int>[];
    for (var i = 0; i < _members.length; i++) {
      if (_members[i].showInFeed) visibleIndices.add(i);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var idx = 0; idx < visibleIndices.length; idx++) ...[
            _ParticipantRow(
              key: ValueKey('row_${_members[visibleIndices[idx]].userId}'),
              member: _members[visibleIndices[idx]],
              groupId: widget.groupId,
              accent: accent,
              navyColor: navyColor,
              isLeader: isVersus &&
                  maxVotes > 0 &&
                  _members[visibleIndices[idx]].voteCount == maxVotes,
              onVoteApplied: ({
                required bool nowVoted,
                required int newCount,
              }) =>
                  _applyVote(visibleIndices[idx],
                      nowVoted: nowVoted, newCount: newCount),
            ),
            if (idx < visibleIndices.length - 1)
              Container(
                height: 1,
                margin: const EdgeInsets.only(left: 36),
                color: navyColor.withAlpha(20),
              ),
          ],
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatefulWidget {
  const _ParticipantRow({
    super.key,
    required this.member,
    required this.groupId,
    required this.accent,
    required this.navyColor,
    required this.isLeader,
    required this.onVoteApplied,
  });

  final CollabFeedMember member;
  final String groupId;
  final Color accent;
  final Color navyColor;
  final bool isLeader;
  final void Function({required bool nowVoted, required int newCount})
      onVoteApplied;

  @override
  State<_ParticipantRow> createState() => _ParticipantRowState();
}

class _ParticipantRowState extends State<_ParticipantRow> {
  // GlobalKey on the avatar's CollabVoteButton so the right-side vote
  // chip can fire the same toggle the avatar tap does, sharing all the
  // optimistic + RPC + animation logic in one place.
  final _voteKey = GlobalKey<CollabVoteButtonState>();

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    final accent = widget.accent;
    final navyColor = widget.navyColor;
    final voted = member.viewerVoted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Tap-to-vote avatar. Smaller (24) so the row stays tight.
          CollabVoteButton(
            key: _voteKey,
            member: member,
            groupId: widget.groupId,
            accentColor: accent,
            isLeader: widget.isLeader,
            avatarSize: 24,
            tapBoxWidth: kMinTouchTarget,
            tapBoxHeight: kMinTouchTarget,
            showCountChip: false,
            onLongPress: () => context.pushNamed(
              RouteNames.userProfile,
              pathParameters: {'userId': member.userId},
            ),
            onVoteApplied: widget.onVoteApplied,
          ),
          const SizedBox(width: 8),
          // Name + handle stacked, so a long display name doesn't push
          // the count chip off-row.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.pushNamed(
                RouteNames.userProfile,
                pathParameters: {'userId': member.userId},
              ),
              child: Text(
                member.displayName.isNotEmpty
                    ? member.displayName
                    : member.username,
                style: QuestTypography.labelLarge.copyWith(
                  fontSize: 12,
                  color: navyColor,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.1,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Compact vote chip — tappable, fires the same toggle as the
          // avatar tap so the user can hit either control to vote.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _voteKey.currentState?.triggerToggle(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              constraints: const BoxConstraints(
                  minWidth: kMinTouchTarget, minHeight: kMinTouchTarget),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: voted ? accent : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: voted ? accent : navyColor.withAlpha(80),
                  width: 1.4,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    voted
                        ? Icons.thumb_up_alt_rounded
                        : Icons.thumb_up_alt_outlined,
                    size: 12,
                    color: voted ? QuestColors.onAccent(accent) : navyColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    member.voteCount.toString(),
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Syne',
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      height: 1.0,
                      letterSpacing: 0.2,
                      color: voted ? QuestColors.onAccent(accent) : navyColor,
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

/// Swipeable gallery showing all collab group members' submissions.
class _CollabMediaGallery extends StatefulWidget {
  final FeedPostModel post;
  const _CollabMediaGallery({required this.post});

  @override
  State<_CollabMediaGallery> createState() => _CollabMediaGalleryState();
}

class _CollabMediaGalleryState extends State<_CollabMediaGallery> {
  int _currentIndex = 0;

  /// All visible team members. Members who haven't uploaded yet (no media
  /// or not yet approved) are kept in the list and rendered as a "waiting
  /// for @user" placeholder slide so the user can swipe to see who's
  /// missing.
  List<CollabFeedMember> get _visibleMembers =>
      widget.post.collabMembers.where((m) => m.showInFeed).toList();

  bool _isWaitingMember(CollabFeedMember m) {
    if (m.mediaUrl == null || m.mediaUrl!.isEmpty) return true;
    if (m.submissionStatus != SubmissionStatus.approved) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final members = _visibleMembers;
    final navyColor = QuestColors.text(context);
    final isVersus = widget.post.collabMode == CollabMode.versus;

    if (members.isEmpty) {
      return AspectRatio(
        aspectRatio: 1,
        child: Container(
          color: navyColor.withAlpha(10),
          child: Center(
            child: Text('NO SUBMISSIONS YET',
                style: QuestTypography.labelSmall.copyWith(
                    color: navyColor.withAlpha(80), letterSpacing: 2)),
          ),
        ),
      );
    }

    return Column(
      children: [
        // Swipeable media + bottom-overlay page indicator (no white strip).
        AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                itemCount: members.length,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (context, index) {
                  final m = members[index];
                  if (_isWaitingMember(m)) {
                    final exp = widget.post.expiresAt;
                    final hasExpired =
                        exp != null && DateTime.now().isAfter(exp);
                    return _WaitingForMemberPanel(
                      member: m,
                      hasExpired: hasExpired,
                    );
                  }
                  return _CollabSlideItem(
                    member: m,
                    isVersus: isVersus,
                    navyColor: navyColor,
                  );
                },
              ),
              if (members.length > 1)
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: QuestColors.pureBlack.withAlpha(140),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_currentIndex + 1}/${members.length}',
                            style: const TextStyle(
                              color: QuestColors.textPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ...List.generate(members.length, (i) {
                            final active = i == _currentIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              width: active ? 14 : 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: active
                                    ? QuestColors.textPrimary
                                    : QuestColors.textPrimary.withAlpha(110),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// Helper widget extracted so the gallery's PageView itemBuilder stays small.
// Holds a single member's media slide + the existing name / crown overlays.
class _CollabSlideItem extends StatelessWidget {
  const _CollabSlideItem({
    required this.member,
    required this.isVersus,
    required this.navyColor,
  });

  final CollabFeedMember member;
  final bool isVersus;
  final Color navyColor;

  @override
  Widget build(BuildContext context) {
    final urls = member.mediaUrls;
    final firstUrl = urls.isNotEmpty ? urls.first : '';
    return Stack(
      fit: StackFit.expand,
      children: [
        // Image (tap opens the unified fullscreen carousel for this
        // member's media — matches the solo-post tap behaviour).
        if (firstUrl.isNotEmpty)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openPostMediaFullscreen(context, urls: urls),
            child: CachedNetworkImage(
              imageUrl: firstUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: navyColor.withAlpha(10)),
              errorWidget: (_, __, ___) => Container(
                color: navyColor.withAlpha(10),
                child: const Icon(Icons.broken_image,
                    color: QuestColors.osTextMuted),
              ),
            ),
          )
        else
          Container(color: navyColor.withAlpha(10)),

        // Multi-image badge stays where it was.
        if (urls.length > 1)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: QuestColors.pureBlack.withAlpha(153),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${urls.length}',
                style: const TextStyle(
                    color: QuestColors.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),

        // Bottom-left: member name pill.
        Positioned(
          left: 12,
          bottom: 12,
          child: Text(
            member.displayName.isNotEmpty
                ? member.displayName
                : member.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: QuestColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              shadows: [
                Shadow(
                  color:
                      QuestColors.pureBlack.withAlpha(QuestColors.alphaInkSoft),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),

        // Bottom-right: leader crown for versus.
        if (isVersus && member.voteCount > 0)
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                // Solid gold plate rather than a 24% wash: the chip sits on
                // arbitrary user media, so it needs its own ground before
                // ink type on it can be relied on.
                color: QuestColors.xpGold,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: QuestColors.osTextPrimary, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LeaderCrown(size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${member.voteCount}',
                    maxLines: 1,
                    style: TextStyle(
                      color: QuestColors.onAccent(QuestColors.xpGold),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Arcade Pop post widgets ──────────────────────────────────────────────────

/// Chunky ink-bordered card around the post media. Shows the category chip
/// and (for collab posts) the mode chip as overlays anchored to the top.
class _PostMediaCard extends StatelessWidget {
  const _PostMediaCard({required this.post});

  final FeedPostModel post;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final isCollab = post.isCollab && post.collabMembers.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink, width: 2),
        boxShadow: [
          BoxShadow(color: ink, offset: const Offset(4, 4), blurRadius: 0),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: isCollab
            ? _CollabMediaGallery(post: post)
            : _MediaBlock(post: post, urls: post.mediaUrls),
      ),
    );
  }
}

/// Chunky action-row: up / down vote on the left, BSHEEEL save + share on
/// the right. All four are pill buttons with ink border + hard shadow;
/// the active state flips fill colour.
class _PostActionBar extends StatelessWidget {
  const _PostActionBar({
    required this.upvotes,
    required this.downvotes,
    required this.myVoteType,
    required this.isSaved,
    this.showVotes = true,
    this.onUpvote,
    this.onDownvote,
    this.onSave,
    this.onShare,
  });

  final int upvotes;
  final int downvotes;
  final String? myVoteType;
  final bool isSaved;

  /// When false, the up/down arrow pills are hidden (used on collab/versus
  /// posts where voting happens per-member in the participants header).
  final bool showVotes;
  final VoidCallback? onUpvote;
  final VoidCallback? onDownvote;
  final VoidCallback? onSave;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final upActive = myVoteType == ReactionType.upvote;
    final downActive = myVoteType == ReactionType.downvote;

    return Row(
      // With votes shown: up/down on the left, Save+Share pushed right
      // by Spacer. With votes hidden (collab/versus): Save+Share aligned
      // to the right edge of the row.
      mainAxisAlignment:
          showVotes ? MainAxisAlignment.start : MainAxisAlignment.end,
      children: [
        if (showVotes) ...[
          _ActionPill(
            icon: Icons.arrow_upward_rounded,
            label: '$upvotes',
            active: upActive,
            activeFill: QuestColors.osRed,
            activeFg: QuestColors.onAccent(QuestColors.osRed),
            onTap: onUpvote,
          ),
          const SizedBox(width: 8),
          _ActionPill(
            icon: Icons.arrow_downward_rounded,
            label: '$downvotes',
            active: downActive,
            activeFill: QuestColors.text(context),
            activeFg: QuestColors.osTextOnPrimary,
            onTap: onDownvote,
          ),
          const Spacer(),
        ],
        _ActionPill(
          icon: isSaved ? Icons.bookmark : Icons.bookmark_border_rounded,
          label: null,
          active: isSaved,
          activeFill: QuestColors.accentYellow,
          activeFg: QuestColors.accentYellowInk,
          onTap: onSave,
        ),
        const SizedBox(width: 6),
        _ActionPill(
          icon: Icons.ios_share_rounded,
          label: null,
          active: false,
          activeFill: QuestColors.osPrimary,
          activeFg: QuestColors.osTextOnPrimary,
          onTap: onShare,
        ),
      ],
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeFill,
    required this.activeFg,
    this.onTap,
  });

  final IconData icon;
  final String? label;
  final bool active;
  final Color activeFill;
  final Color activeFg;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final bg = active ? activeFill : QuestColors.cardBg(context);
    final fg = active ? activeFg : ink;
    final hasLabel = label != null && label!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        // Tighter pill visually, but never below the 44pt touch floor.
        constraints: const BoxConstraints(
            minWidth: kMinTouchTarget, minHeight: kMinTouchTarget),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(
          horizontal: hasLabel ? 9 : 8,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: ink, width: 1.5),
          boxShadow: [
            BoxShadow(color: ink, offset: const Offset(0, 1.5), blurRadius: 0),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            if (hasLabel) ...[
              const SizedBox(width: 4),
              Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.labelMedium.copyWith(
                  color: fg,
                  fontSize: 11,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Quest title + description + caption(s) + XP and time, all inside a single
/// chunky ink-bordered card.
class _PostInfoCard extends StatelessWidget {
  const _PostInfoCard({required this.post, required this.timeAgo});
  final FeedPostModel post;
  final String timeAgo;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final l = AppLocalizations.of(context)!;
    final captionRows = <Widget>[];

    if (post.isCollab && post.collabMembers.isNotEmpty) {
      for (final m in post.collabMembers) {
        if (!m.showInFeed) continue;
        final caption = m.caption?.trim();
        if (caption == null || caption.isEmpty) continue;
        captionRows.add(
          _CaptionLine(
            author: m.displayName.isNotEmpty ? m.displayName : m.username,
            said: l.said,
            caption: caption,
          ),
        );
      }
    } else if (post.caption != null && post.caption!.isNotEmpty) {
      captionRows.add(
        _CaptionLine(
          author:
              post.displayName.isNotEmpty ? post.displayName : post.username,
          said: l.said,
          caption: post.caption!,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ink, width: 2),
        boxShadow: [
          BoxShadow(color: ink, offset: const Offset(3, 3), blurRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            post.questTitle,
            style: QuestTypography.headlineLarge.copyWith(
              color: ink,
              fontSize: 18,
              height: 1.2,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (post.questDescription.isNotEmpty) ...[
            const SizedBox(height: 6),
            _ExpandableText(text: post.questDescription, maxLines: 2),
          ],
          if (captionRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...captionRows,
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: QuestColors.cardBg(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ink, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 12,
                        color: ink.withAlpha(QuestColors.alphaInkMuted)),
                    const SizedBox(width: 4),
                    Text(
                      timeAgo,
                      style: QuestTypography.labelSmall.copyWith(
                        color: ink.withAlpha(QuestColors.alphaInkMuted),
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CaptionLine extends StatelessWidget {
  const _CaptionLine({
    required this.author,
    required this.said,
    required this.caption,
  });
  final String author;
  final String said;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    // Render the caption flat (no border, no background) to match the
    // quest description block above it. Author label sits inline as a
    // small uppercase prefix in the brand violet.
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '${author.toUpperCase()} ${said.toUpperCase()}  ',
              style: QuestTypography.labelSmall.copyWith(
                color: QuestColors.osPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            TextSpan(
              text: caption,
              style: QuestTypography.bodySmall.copyWith(
                color: ink,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Waiting-for-member panel (post details gallery) ────────────────────────

/// Placeholder slide shown in the collab media gallery for a member who
/// hasn't uploaded yet (or whose submission is still pending review).
/// The user can swipe to see who in the team is still missing.
class _WaitingForMemberPanel extends StatelessWidget {
  const _WaitingForMemberPanel({
    required this.member,
    required this.hasExpired,
  });
  final CollabFeedMember member;
  final bool hasExpired;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final name =
        member.username.isNotEmpty ? member.username : member.displayName;
    final headline = hasExpired ? "DIDN'T POST" : 'WAITING FOR';
    final subline =
        hasExpired ? 'ran out of time on this quest' : "hasn't posted yet";
    return Container(
      color: ink.withAlpha(8),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PixelAvatar(
                username: member.username,
                imageUrl: member.avatarUrl,
                size: 64,
                borderColor: hasExpired ? QuestColors.osRed : null,
              ),
              const SizedBox(height: 14),
              Text(
                headline,
                style: QuestTypography.labelSmall.copyWith(
                  color: hasExpired ? QuestColors.osRed : ink.withAlpha(140),
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '@$name',
                textAlign: TextAlign.center,
                style: QuestTypography.headlineSmall.copyWith(
                  color: ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subline,
                style: QuestTypography.bodySmall.copyWith(
                  color: ink.withAlpha(150),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Unified fullscreen viewer (image + video carousel) ─────────────────────

/// Opens [urls] full-screen in a horizontal carousel starting at
/// [initialIndex]. Auto-detects images vs videos by URL extension. Tap
/// outside or swipe down to dismiss.
void openPostMediaFullscreen(
  BuildContext context, {
  required List<String> urls,
  int initialIndex = 0,
}) {
  if (urls.isEmpty) return;
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: QuestColors.pureBlack,
      pageBuilder: (_, __, ___) => _PostMediaFullscreen(
        urls: urls,
        initialIndex: initialIndex.clamp(0, urls.length - 1),
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

class _PostMediaFullscreen extends StatefulWidget {
  const _PostMediaFullscreen({
    required this.urls,
    required this.initialIndex,
  });
  final List<String> urls;
  final int initialIndex;

  @override
  State<_PostMediaFullscreen> createState() => _PostMediaFullscreenState();
}

class _PostMediaFullscreenState extends State<_PostMediaFullscreen> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QuestColors.pureBlack,
      body: SafeArea(
        child: Stack(
          children: [
            // Drag-down to dismiss.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragEnd: (d) {
                if (d.velocity.pixelsPerSecond.dy.abs() > 300) {
                  Navigator.of(context).maybePop();
                }
              },
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.urls.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) {
                  final url = widget.urls[i];
                  if (isVideoUrl(url)) {
                    return _FullscreenVideoSlide(
                      url: url,
                      isActive: i == _index,
                    );
                  }
                  return _FullscreenImageSlide(url: url);
                },
              ),
            ),
            // Top-left close button.
            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: Colors.transparent,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: QuestColors.pureBlack.withAlpha(140),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: QuestColors.pureWhite.withAlpha(80), width: 1),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.close_rounded,
                        color: QuestColors.textPrimary, size: 22),
                  ),
                ),
              ),
            ),
            // Top-right index pill, shown only when there are multiple.
            if (widget.urls.length > 1)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: QuestColors.pureBlack.withAlpha(140),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: QuestColors.pureWhite.withAlpha(60), width: 1),
                  ),
                  child: Text(
                    '${_index + 1} / ${widget.urls.length}',
                    style: const TextStyle(
                      color: QuestColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
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

class _FullscreenImageSlide extends StatelessWidget {
  const _FullscreenImageSlide({required this.url});
  final String url;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: InteractiveViewer(
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (_, __) => const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          errorWidget: (_, __, ___) => Center(
            child: Icon(Icons.broken_image_outlined,
                color:
                    QuestColors.pureWhite.withAlpha(QuestColors.alphaOverlay),
                size: 64),
          ),
        ),
      ),
    );
  }
}

class _FullscreenVideoSlide extends StatefulWidget {
  const _FullscreenVideoSlide({
    required this.url,
    required this.isActive,
  });
  final String url;
  final bool isActive;

  @override
  State<_FullscreenVideoSlide> createState() => _FullscreenVideoSlideState();
}

class _FullscreenVideoSlideState extends State<_FullscreenVideoSlide> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _hasError = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(_muted ? 0 : 1);
      if (!mounted) {
        c.dispose();
        return;
      }
      _controller = c;
      setState(() => _ready = true);
      if (widget.isActive) await c.play();
    } catch (_) {
      c.dispose();
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void didUpdateWidget(covariant _FullscreenVideoSlide old) {
    super.didUpdateWidget(old);
    final c = _controller;
    if (c == null || !_ready) return;
    if (widget.isActive) {
      c.play();
    } else {
      c.pause();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null) return;
    setState(() => _muted = !_muted);
    c.setVolume(_muted ? 0 : 1);
  }

  void _togglePlayPause() {
    final c = _controller;
    if (c == null || !_ready) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Icon(Icons.videocam_off_rounded,
            color: QuestColors.pureWhite.withAlpha(QuestColors.alphaOverlay),
            size: 64),
      );
    }
    final c = _controller;
    if (c == null || !_ready) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlayPause,
          child: Center(
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio == 0 ? 1 : c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          ),
        ),
        Positioned(
          top: 16,
          right: 64,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleMute,
            child: BsMinTouch(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: QuestColors.pureBlack.withAlpha(140),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: QuestColors.pureWhite.withAlpha(80), width: 1),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: QuestColors.textPrimary,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
