import 'deep_link_config.dart';

/// The one wording every share in Bsheel uses.
///
/// It lives here because it was previously written out at each call site —
/// the feed card, the post detail page, the profile, the collab invite —
/// and four copies of a sentence drift the moment anybody improves one of
/// them. Issue #5 asked for a finalised template; this is it, in one place
/// so it stays finalised.
///
/// The shape is deliberately small. A share lands in WhatsApp or Instagram
/// as plain text next to a link preview, so it has to say what the thing is
/// in about two lines and then get out of the way.
abstract final class ShareTemplate {
  /// A completed quest someone is showing off.
  ///
  /// ```
  /// BSHEEL
  ///
  /// "Fold a manoushe with the baker" · Lebanon
  /// Did it before the bakery even opened.
  ///
  /// https://…
  /// ```
  ///
  /// [country] is the quest's reviewed destination country and is simply
  /// left out when the quest has none — most quests can be done anywhere,
  /// and "· null" reads worse than nothing. [caption] is the player's own
  /// words, which is the part that actually makes somebody click.
  static String quest({
    required String postId,
    required String questTitle,
    String? country,
    String? caption,
    String? username,
  }) {
    final title = questTitle.trim();
    final place = (country ?? '').trim();
    final words = (caption ?? '').trim();

    final headline = [
      if (title.isNotEmpty) '"$title"',
      if (place.isNotEmpty) place,
    ].join(' · ');

    return [
      'BSHEEL',
      '',
      // A post whose quest title somehow did not load still shares
      // sensibly, crediting whoever did it.
      if (headline.isNotEmpty)
        headline
      else if ((username ?? '').isNotEmpty)
        'A quest by @$username'
      else
        'A quest',
      if (words.isNotEmpty) words,
      '',
      DeepLinkConfig.postLink(postId),
    ].join('\n');
  }

  /// Someone's profile.
  static String profile({required String profileId, required String username}) {
    return [
      'BSHEEL',
      '',
      '@$username',
      '',
      DeepLinkConfig.profileLink(profileId)
    ].join('\n');
  }

  /// An invitation to join a collab quest.
  static String collabInvite({
    required String link,
    required String modeLabel,
    String? questTitle,
  }) {
    final title = (questTitle ?? '').trim();
    return [
      'BSHEEL',
      '',
      title.isEmpty
          ? 'Join my $modeLabel quest'
          : 'Join my $modeLabel quest: "$title"',
      '',
      link,
    ].join('\n');
  }
}
