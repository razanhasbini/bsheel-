import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';

import '../../../core/providers/auth_session_provider.dart';
import '../presentation/widgets/mention_picker.dart';
import '../../../core/backend/app_backend.dart';

/// Owns the @-mention picker plumbing shared by every comment input
/// (comments sheet + post-detail page): listens to [textController],
/// debounces the suggestion queries (people the user follows first,
/// then a global profile search), tracks which candidates were actually
/// picked from the dropdown, and rewrites the text when a suggestion is
/// tapped.
///
/// The owning widget keeps full control of rendering — it reads
/// [suggestions] / [loading] / [query] after [onSuggestionsChanged]
/// fires (typically a bare `setState`) and feeds picker taps back
/// through [insertMention]. Extracted from the two near-identical
/// private copies that previously lived in the feed's comments sheet (now
/// `comments_page.dart`) and in `feed_post_details_page.dart` —
/// double-maintaining them already caused one production bug.
class MentionInputController {
  MentionInputController({
    required this.textController,
    required this.focusNode,
    required this.ref,
    required this.onSuggestionsChanged,
  }) {
    textController.addListener(_handleTextChanged);
  }

  /// The comment input's controller. Listened to for `@query` detection;
  /// rewritten by [insertMention]. NOT owned — the widget still disposes
  /// it (after calling [dispose] here).
  final TextEditingController textController;

  /// Refocused after a suggestion is inserted so the keyboard stays up.
  final FocusNode focusNode;

  /// Provider accessor for the auth session + Supabase client. All reads
  /// happen synchronously from listener/timer callbacks that [dispose]
  /// cancels, so the ref is never touched after the owning State dies.
  final WidgetRef ref;

  /// Fired whenever [suggestions], [loading] or [query] change so the
  /// widget can rebuild its picker UI.
  final VoidCallback onSuggestionsChanged;

  Timer? _debounce;
  bool _disposed = false;
  List<MentionCandidate> _suggestions = const [];
  bool _loading = false;
  int? _mentionStart;
  String _query = '';
  // Tracks every candidate the user picked from the dropdown — keyed by
  // user id — so we can resolve mentions back to user ids on send even
  // if the typed handle has unusual casing.
  final Map<String, MentionCandidate> _selectedMentions = {};

  /// Current dropdown candidates (already ranked: follows first).
  List<MentionCandidate> get suggestions => _suggestions;

  /// True while a suggestion query is debouncing/in flight.
  bool get loading => _loading;

  /// The text typed after `@`, used for the "NO USERS FOUND" empty state.
  String get query => _query;

  /// Index of the `@` that opened the picker, or null when no mention is
  /// being composed. Lets surfaces gate their panel on "mention active"
  /// (submit-proof caption) rather than "has suggestions" (comments).
  int? get mentionStart => _mentionStart;

  /// Candidates the user explicitly picked from the dropdown, keyed by
  /// user id. Pass to `resolveMentionedUsers` when sending the comment.
  Map<String, MentionCandidate> get selectedMentions =>
      Map.unmodifiable(_selectedMentions);

  /// Forget dropdown picks (call after the comment has been posted).
  void clearSelectedMentions() => _selectedMentions.clear();

  /// Detach from [textController] and cancel any pending query. Call
  /// from the widget's `dispose` BEFORE disposing the text controller.
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    textController.removeListener(_handleTextChanged);
  }

  void _handleTextChanged() {
    final cursor = textController.selection.baseOffset;
    if (cursor < 0) {
      _clearSuggestions();
      return;
    }
    final textBeforeCursor = textController.text.substring(0, cursor);
    final atIndex = textBeforeCursor.lastIndexOf('@');
    if (atIndex == -1) {
      _clearSuggestions();
      return;
    }
    final query = textBeforeCursor.substring(atIndex + 1);
    if (query.contains(RegExp(r'\s')) ||
        query.contains(RegExp(r'[^A-Za-z0-9_]'))) {
      _clearSuggestions();
      return;
    }
    _mentionStart = atIndex;
    _query = query;
    _loading = true;
    onSuggestionsChanged();
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 180),
      () => _loadSuggestions(query),
    );
  }

  void _clearSuggestions() {
    _debounce?.cancel();
    if (_suggestions.isEmpty &&
        !_loading &&
        _mentionStart == null &&
        _query.isEmpty) {
      return;
    }
    _suggestions = const [];
    _loading = false;
    _mentionStart = null;
    _query = '';
    onSuggestionsChanged();
  }

  Future<void> _loadSuggestions(String query) async {
    final user = ref.read(authSessionProvider);
    if (user == null) {
      if (!_disposed) _clearSuggestions();
      return;
    }
    try {
      await _loadNestSuggestions(user.id, query);
    } catch (e) {
      AppLogger.error('[Mentions] Failed to load suggestions', e);
      if (_disposed) return;
      _suggestions = const [];
      _loading = false;
      onSuggestionsChanged();
    }
  }

  Future<void> _loadNestSuggestions(String userId, String query) async {
    final repositories = AppBackend.repositories;
    final connections = await repositories.follows.listConnections(
      userId: userId,
      isFollowers: false,
    );
    final following = connections.map((profile) {
      return MentionCandidate(
        profile: ProfileModel(
          id: profile.id,
          username: profile.username,
          displayName: profile.displayName,
          avatarUrl: profile.avatarUrl,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
        isFollowing: true,
      );
    });

    bool matches(ProfileModel profile) {
      if (query.isEmpty) return true;
      final normalized = query.toLowerCase();
      return profile.username.toLowerCase().contains(normalized) ||
          profile.displayName.toLowerCase().contains(normalized);
    }

    final ordered = <String, MentionCandidate>{
      for (final candidate in following.where((item) => matches(item.profile)))
        candidate.profile.id: candidate,
    };
    if (query.isNotEmpty) {
      final results = await repositories.search.searchUsers(query, limit: 12);
      for (final profile in results) {
        if (profile.id == userId) continue;
        ordered.putIfAbsent(
          profile.id,
          () => MentionCandidate(profile: profile, isFollowing: false),
        );
      }
    }

    if (_disposed || query != _query) return;
    _suggestions = ordered.values.take(8).toList(growable: false);
    _loading = false;
    onSuggestionsChanged();
  }

  /// Replaces the in-progress `@query` with `@username ` for the tapped
  /// [candidate], records the pick, and refocuses the input.
  void insertMention(MentionCandidate candidate) {
    final start = _mentionStart;
    if (start == null) return;
    final text = textController.text;
    final cursor = textController.selection.baseOffset;
    final end = cursor < start ? start : cursor;
    final mention = '@${candidate.profile.username} ';
    final next = text.replaceRange(start, end, mention);
    final nextCursor = start + mention.length;
    _selectedMentions[candidate.profile.id] = candidate;
    textController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: nextCursor),
    );
    _clearSuggestions();
    focusNode.requestFocus();
  }
}
