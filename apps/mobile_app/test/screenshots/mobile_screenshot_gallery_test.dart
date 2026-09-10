@Tags(['screenshots'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/core/providers/account_status_provider.dart';
import 'package:mobile_app/core/providers/auth_repository_provider.dart';
import 'package:mobile_app/core/providers/auth_session_provider.dart';
import 'package:mobile_app/core/providers/current_profile_provider.dart';
import 'package:mobile_app/core/providers/connectivity_provider.dart';
import 'package:mobile_app/core/router/route_names.dart';
import 'package:app_core/app_core.dart' show QuestTheme;
import 'package:mobile_app/features/admin/presentation/pages/admin_page.dart';
import 'package:mobile_app/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:mobile_app/features/auth/presentation/pages/login_page.dart';
import 'package:mobile_app/features/auth/presentation/pages/reset_password_page.dart';
import 'package:mobile_app/features/auth/presentation/pages/signup_page.dart';
import 'package:mobile_app/features/collab/data/collab_providers.dart';
import 'package:mobile_app/features/collab/presentation/pages/collab_page.dart';
import 'package:mobile_app/features/collab/presentation/pages/join_collab_page.dart';
import 'package:mobile_app/features/comments/presentation/widgets/comments_section.dart';
import 'package:mobile_app/features/feed/presentation/pages/feed_page.dart';
import 'package:mobile_app/features/feed/presentation/pages/feed_post_details_page.dart';
import 'package:mobile_app/features/feed/presentation/providers/feed_post_details_provider.dart';
import 'package:mobile_app/features/feed/presentation/providers/feed_provider.dart';
import 'package:mobile_app/features/leaderboard/presentation/pages/leaderboard_page.dart';
import 'package:mobile_app/features/leaderboard/presentation/providers/leaderboard_provider.dart';
import 'package:mobile_app/features/legal/presentation/pages/privacy_policy_page.dart';
import 'package:mobile_app/features/legal/presentation/pages/terms_page.dart';
import 'package:mobile_app/features/notifications/presentation/pages/notifications_page.dart';
import 'package:mobile_app/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:mobile_app/features/onboarding/presentation/pages/onboarding_walkthrough_page.dart';
import 'package:mobile_app/features/profile/presentation/pages/edit_profile_page.dart';
import 'package:mobile_app/features/profile/presentation/pages/profile_page.dart';
import 'package:mobile_app/features/quests/data/quest_providers.dart';
import 'package:mobile_app/features/quests/presentation/pages/home_page.dart';
import 'package:mobile_app/features/quests/presentation/pages/quest_details_page.dart';
import 'package:mobile_app/features/quests/presentation/pages/quest_history_page.dart';
import 'package:mobile_app/features/reactions/presentation/providers/reaction_controller.dart';
import 'package:mobile_app/features/settings/presentation/pages/settings_page.dart';
import 'package:mobile_app/features/submissions/data/submission_providers.dart';
import 'package:mobile_app/features/submissions/presentation/pages/submission_status_page.dart';
import 'package:mobile_app/features/submissions/presentation/pages/submit_proof_page.dart';
import 'package:mobile_app/l10n/app_localizations.dart';
import 'package:mobile_app/shared/navigation/bottom_nav_shell.dart';
import 'package:app_contracts/app_contracts.dart';

void main() {
  // Dev utility: every repository is faked, so this needs no backend — but
  // it writes PNGs to disk, so it stays opt-in rather than running in CI.
  const enabled = bool.fromEnvironment('SCREENSHOTS');
  if (!enabled) {
    test(
      'screenshot gallery',
      () {},
      skip: 'Pass --dart-define=SCREENSHOTS=true to generate the gallery.',
    );
    return;
  }

  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final outputDir = Directory('screenshots/mobile_app');

  setUpAll(() async {
    await outputDir.create(recursive: true);
  });

  tearDownAll(() {
    binding.platformDispatcher.clearAllTestValues();
  });

  testWidgets('captures the mobile app screenshot gallery', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final manifest = <String>[];
    final failures = <String>[];

    for (final screen in _screens) {
      try {
        final key = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: _overrides(),
            child: _ScreenshotApp(
              repaintKey: key,
              initialLocation: screen.path,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();

        final exception = tester.takeException();
        if (exception != null) {
          failures.add('${screen.name}: $exception');
        }

        // Engine image encoding and filesystem I/O complete outside the
        // widget test's fake clock. Awaiting them there can hang the gallery.
        await tester
            .runAsync(() => _saveScreenshot(key, outputDir, screen.name));
        manifest.add('${screen.name}.png -> ${screen.path}');
      } catch (error, stackTrace) {
        failures.add('${screen.name}: $error\n$stackTrace');
      }
    }

    await tester.runAsync(() => File('${outputDir.path}/manifest.txt')
        .writeAsString('${manifest.join('\n')}\n'));

    if (failures.isNotEmpty) {
      fail('Screenshot capture failures:\n${failures.join('\n\n')}');
    }
  });
}

Future<void> _saveScreenshot(
  GlobalKey key,
  Directory outputDir,
  String name,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = byteData!.buffer.asUint8List();
  await File('${outputDir.path}/$name.png').writeAsBytes(bytes);
  image.dispose();
}

class _ScreenshotApp extends StatelessWidget {
  const _ScreenshotApp({
    required this.repaintKey,
    required this.initialLocation,
  });

  final GlobalKey repaintKey;
  final String initialLocation;

  @override
  Widget build(BuildContext context) {
    final router = _buildRouter(initialLocation);
    return MaterialApp.router(
      title: 'Bit Sheel?',
      theme: QuestTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => RepaintBoundary(
        key: repaintKey,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

GoRouter _buildRouter(String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: RoutePaths.login,
        name: RouteNames.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: RoutePaths.signup,
        name: RouteNames.signup,
        builder: (context, state) => const SignupPage(),
      ),
      GoRoute(
        path: RoutePaths.forgotPassword,
        name: RouteNames.forgotPassword,
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: RoutePaths.resetPassword,
        name: RouteNames.resetPassword,
        builder: (context, state) => const ResetPasswordPage(),
      ),
      GoRoute(
        path: RoutePaths.onboardingWalkthrough,
        name: RouteNames.onboardingWalkthrough,
        builder: (context, state) => const OnboardingWalkthroughPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => BottomNavShell(child: child),
        routes: [
          GoRoute(
            path: RoutePaths.home,
            name: RouteNames.home,
            builder: (context, state) => const HomePage(),
          ),
          GoRoute(
            path: RoutePaths.feed,
            name: RouteNames.feed,
            builder: (context, state) => const FeedPage(),
          ),
          GoRoute(
            path: RoutePaths.collab,
            name: RouteNames.collab,
            builder: (context, state) => const CollabPage(),
          ),
          GoRoute(
            path: RoutePaths.leaderboard,
            name: RouteNames.leaderboard,
            builder: (context, state) => const LeaderboardPage(),
          ),
          GoRoute(
            path: RoutePaths.profile,
            name: RouteNames.profile,
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.questDetails,
        name: RouteNames.questDetails,
        builder: (context, state) =>
            QuestDetailsPage(questId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePaths.questHistory,
        name: RouteNames.questHistory,
        builder: (context, state) => const QuestHistoryPage(),
      ),
      GoRoute(
        path: RoutePaths.submitProof,
        name: RouteNames.submitProof,
        builder: (context, state) =>
            SubmitProofPage(userQuestId: state.pathParameters['userQuestId']!),
      ),
      GoRoute(
        path: RoutePaths.submissionStatus,
        name: RouteNames.submissionStatus,
        builder: (context, state) =>
            SubmissionStatusPage(submissionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePaths.feedPostDetails,
        name: RouteNames.feedPostDetails,
        builder: (context, state) =>
            FeedPostDetailsPage(postId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: RoutePaths.editProfile,
        name: RouteNames.editProfile,
        builder: (context, state) => const EditProfilePage(),
      ),
      GoRoute(
        path: RoutePaths.userProfile,
        name: RouteNames.userProfile,
        builder: (context, state) => const ProfilePage(),
      ),
      GoRoute(
        path: RoutePaths.notifications,
        name: RouteNames.notifications,
        builder: (context, state) => const NotificationsPage(),
      ),
      GoRoute(
        path: RoutePaths.settings,
        name: RouteNames.settings,
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: RoutePaths.admin,
        name: RouteNames.admin,
        builder: (context, state) => const AdminPage(),
      ),
      GoRoute(
        path: RoutePaths.joinCollab,
        name: RouteNames.joinCollab,
        builder: (context, state) =>
            JoinCollabPage(code: state.pathParameters['code']!),
      ),
      GoRoute(
        path: RoutePaths.privacyPolicy,
        name: RouteNames.privacyPolicy,
        builder: (context, state) => const PrivacyPolicyPage(),
      ),
      GoRoute(
        path: RoutePaths.terms,
        name: RouteNames.terms,
        builder: (context, state) => const TermsPage(),
      ),
    ],
  );
}

List<Override> _overrides() {
  return [
    authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
    authSessionProvider.overrideWith((ref) => null),
    currentProfileProvider.overrideWith((ref) async => _profile),
    accountStatusProvider.overrideWith((ref) async => 'active'),
    connectivityProvider.overrideWith((ref) => Stream.value(true)),
    isAdminProvider.overrideWith((ref) async => false),
    questsRepositoryProvider.overrideWithValue(_FakeQuestsRepository()),
    activeQuestProvider.overrideWith((ref) async => _activeUserQuest),
    questHistoryProvider.overrideWith((ref) async => _questHistory),
    questHistoryByUserProvider(_otherProfile.id)
        .overrideWith((ref) async => _questHistory),
    questDetailsProvider(_quest.id).overrideWith((ref) async => _quest),
    submissionsRepositoryProvider
        .overrideWithValue(_FakeSubmissionsRepository()),
    userSubmissionsProvider.overrideWith((ref) async => _submissions),
    userSubmissionsByUserProvider(_otherProfile.id)
        .overrideWith((ref) async => _submissions),
    submissionByIdProvider(_approvedSubmission.id)
        .overrideWith((ref) async => _approvedSubmission),
    feedRepositoryProvider.overrideWithValue(_FakeFeedRepository()),
    feedProvider.overrideWith(() => _FakeFeedNotifier()),
    feedPostDetailsProvider(_feedPost.id)
        .overrideWith((ref) async => _feedPost),
    leaderboardRepositoryProvider
        .overrideWithValue(_FakeLeaderboardRepository()),
    leaderboardProvider.overrideWith((ref) async => _leaderboard),
    followingLeaderboardProvider
        .overrideWith((ref) async => _leaderboard.take(2).toList()),
    notificationsRepositoryProvider
        .overrideWithValue(_FakeNotificationsRepository()),
    notificationsProvider.overrideWith((ref) async => _notifications),
    unreadCountProvider.overrideWith((ref) async => 2),
    collabRepositoryProvider.overrideWithValue(_FakeCollabRepository()),
    collabGroupStatusProvider(_activeUserQuest.id)
        .overrideWith((ref) async => _collabStatus),
    collabGroupDetailsProvider(_joinCode)
        .overrideWith((ref) async => _collabPreview),
    reactionsRepositoryProvider.overrideWithValue(_FakeReactionsRepository()),
    commentsProvider(_feedPost.id).overrideWith((ref) async => _comments),
  ];
}

class _Screen {
  const _Screen(this.name, this.path);

  final String name;
  final String path;
}

const _joinCode = 'QUEST42';

final _screens = [
  const _Screen('01_login', RoutePaths.login),
  const _Screen('02_signup', RoutePaths.signup),
  const _Screen('03_forgot_password', RoutePaths.forgotPassword),
  const _Screen('04_reset_password', RoutePaths.resetPassword),
  const _Screen('07_onboarding_walkthrough', RoutePaths.onboardingWalkthrough),
  const _Screen('08_home', RoutePaths.home),
  const _Screen('09_feed', RoutePaths.feed),
  const _Screen('10_collab', RoutePaths.collab),
  const _Screen('11_leaderboard', RoutePaths.leaderboard),
  const _Screen('12_profile', RoutePaths.profile),
  const _Screen('13_quest_details', '/quest/quest-focus'),
  const _Screen('14_quest_history', RoutePaths.questHistory),
  const _Screen('15_submit_proof', '/submit/user-quest-active'),
  const _Screen('16_submission_status', '/submission/submission-approved'),
  const _Screen('18_feed_post_details', '/post/post-1'),
  const _Screen('19_edit_profile', RoutePaths.editProfile),
  const _Screen('20_notifications', RoutePaths.notifications),
  const _Screen('21_settings', RoutePaths.settings),
  const _Screen('22_join_collab', '/join/QUEST42'),
  const _Screen('23_admin_access_denied', RoutePaths.admin),
  const _Screen('24_privacy_policy', RoutePaths.privacyPolicy),
  const _Screen('25_terms', RoutePaths.terms),
];

final _now = DateTime(2026, 4, 12, 12);

final _profile = ProfileModel(
  id: 'user-1',
  username: 'bitsheel',
  displayName: 'Bit Sheel',
  bio: 'Chasing four-hour quests around Beirut.',
  xp: 1480,
  level: 7,
  questsCompleted: 18,
  createdAt: _now.subtract(const Duration(days: 90)),
  profileCompleted: true,
);

final _otherProfile = ProfileModel(
  id: 'user-2',
  username: 'pixelrana',
  displayName: 'Pixel Rana',
  bio: 'Photo walks, coffee, and side quests.',
  xp: 990,
  level: 5,
  questsCompleted: 11,
  createdAt: _now.subtract(const Duration(days: 60)),
  profileCompleted: true,
);

final _quest = QuestModel(
  id: 'quest-focus',
  title: 'Find a quiet corner',
  description:
      'Spend 20 minutes in a quiet place and capture the little detail that made it feel calm.',
  category: 'Mindful',
  difficulty: 'medium',
  xpReward: 75,
  durationHours: 4,
  createdAt: _now.subtract(const Duration(days: 14)),
);

final _questSocial = QuestModel(
  id: 'quest-social',
  title: 'Compliment a stranger',
  description:
      'Give someone a sincere compliment and write down how the moment changed your mood.',
  category: 'Social',
  difficulty: 'easy',
  xpReward: 40,
  durationHours: 4,
  createdAt: _now.subtract(const Duration(days: 12)),
);

final _questAdventure = QuestModel(
  id: 'quest-adventure',
  title: 'Take the long way',
  description:
      'Walk a different route than usual and photograph one thing you have never noticed.',
  category: 'Adventure',
  difficulty: 'hard',
  xpReward: 120,
  durationHours: 4,
  createdAt: _now.subtract(const Duration(days: 10)),
);

final _allQuests = [_questSocial, _quest, _questAdventure];

final _activeUserQuest = UserQuestModel(
  id: 'user-quest-active',
  userId: _profile.id,
  questId: _quest.id,
  status: UserQuestStatus.assigned,
  assignedAt: _now.subtract(const Duration(hours: 1)),
  expiresAt: _now.add(const Duration(hours: 3)),
  quest: _quest,
);

final _approvedUserQuest = UserQuestModel(
  id: 'user-quest-approved',
  userId: _profile.id,
  questId: _questSocial.id,
  status: UserQuestStatus.approved,
  assignedAt: _now.subtract(const Duration(days: 3)),
  completedAt: _now.subtract(const Duration(days: 3, hours: -2)),
  quest: _questSocial,
);

final _rejectedUserQuest = UserQuestModel(
  id: 'user-quest-rejected',
  userId: _profile.id,
  questId: _questAdventure.id,
  status: UserQuestStatus.rejected,
  assignedAt: _now.subtract(const Duration(days: 1)),
  completedAt: _now.subtract(const Duration(hours: 22)),
  quest: _questAdventure,
);

final _questHistory = [
  _activeUserQuest,
  _approvedUserQuest,
  _rejectedUserQuest
];

final _approvedSubmission = SubmissionModel(
  id: 'submission-approved',
  userQuestId: _approvedUserQuest.id,
  userId: _profile.id,
  mediaUrl: '',
  caption: 'Found a tiny mural hiding beside the old stairs.',
  status: SubmissionStatus.approved,
  submittedAt: _now.subtract(const Duration(days: 2)),
  reviewedAt: _now.subtract(const Duration(days: 2, hours: -1)),
);

final _pendingSubmission = SubmissionModel(
  id: 'submission-pending',
  userQuestId: _activeUserQuest.id,
  userId: _profile.id,
  mediaUrl: '',
  caption: 'Uploading proof from the quiet corner.',
  status: SubmissionStatus.pending,
  submittedAt: _now.subtract(const Duration(minutes: 45)),
);

final _rejectedSubmission = SubmissionModel(
  id: 'submission-rejected',
  userQuestId: _rejectedUserQuest.id,
  userId: _profile.id,
  mediaUrl: '',
  caption: 'The proof was too blurry, trying again tomorrow.',
  status: SubmissionStatus.rejected,
  reviewNote: 'Photo is unclear',
  submittedAt: _now.subtract(const Duration(hours: 22)),
  reviewedAt: _now.subtract(const Duration(hours: 20)),
);

final _submissions = [
  _pendingSubmission,
  _approvedSubmission,
  _rejectedSubmission
];

final _feedPost = FeedPostModel(
  id: 'post-1',
  mediaUrl: '',
  mediaType: MediaType.image,
  caption: _approvedSubmission.caption,
  submittedAt: _approvedSubmission.submittedAt,
  userId: _profile.id,
  username: _profile.username,
  displayName: _profile.displayName,
  bio: _profile.bio,
  questId: _questSocial.id,
  questTitle: _questSocial.title,
  questDescription: _questSocial.description,
  questCategory: _questSocial.category,
  xpReward: _questSocial.xpReward,
  upvoteCount: 5,
  downvoteCount: 1,
  netScore: 4,
);

final _collabFeedPost = FeedPostModel(
  id: 'post-collab',
  mediaUrl: '',
  mediaType: MediaType.image,
  caption: 'Team proof is coming together.',
  submittedAt: _now.subtract(const Duration(hours: 6)),
  userId: _otherProfile.id,
  username: _otherProfile.username,
  displayName: _otherProfile.displayName,
  questId: _questAdventure.id,
  questTitle: _questAdventure.title,
  questDescription: _questAdventure.description,
  questCategory: _questAdventure.category,
  xpReward: _questAdventure.xpReward,
  upvoteCount: 7,
  downvoteCount: 2,
  netScore: 5,
  isCollab: true,
  collabGroupId: 'group-1',
  collabMode: CollabMode.versus,
  collabMemberCount: 3,
  collabMembers: [
    CollabFeedMember(
      userId: _profile.id,
      username: _profile.username,
      displayName: _profile.displayName,
      submissionId: 'submission-approved',
      submissionStatus: SubmissionStatus.approved,
      voteCount: 5,
    ),
    CollabFeedMember(
      userId: _otherProfile.id,
      username: _otherProfile.username,
      displayName: _otherProfile.displayName,
      submissionId: 'submission-other',
      submissionStatus: SubmissionStatus.approved,
      voteCount: 3,
    ),
  ],
);

final _feedPosts = [_feedPost, _collabFeedPost];

final _leaderboard = [
  LeaderboardUserModel(
    rank: 1,
    userId: _profile.id,
    username: _profile.username,
    displayName: _profile.displayName,
    xp: _profile.xp,
    level: _profile.level,
    questsCompleted: _profile.questsCompleted,
  ),
  LeaderboardUserModel(
    rank: 2,
    userId: _otherProfile.id,
    username: _otherProfile.username,
    displayName: _otherProfile.displayName,
    xp: _otherProfile.xp,
    level: _otherProfile.level,
    questsCompleted: _otherProfile.questsCompleted,
  ),
  const LeaderboardUserModel(
    rank: 3,
    userId: 'user-3',
    username: 'cedarfox',
    displayName: 'Cedar Fox',
    xp: 760,
    level: 4,
    questsCompleted: 8,
  ),
];

final _notifications = [
  NotificationModel(
    id: 'notification-1',
    userId: _profile.id,
    title: 'Submission approved',
    body: 'Your mural proof was approved. +40 XP landed.',
    type: NotificationType.submissionApproved,
    referenceId: _approvedSubmission.id,
    createdAt: _now.subtract(const Duration(minutes: 20)),
  ),
  NotificationModel(
    id: 'notification-2',
    userId: _profile.id,
    title: 'New quest waiting',
    body: 'Find a quiet corner is live for the next few hours.',
    type: NotificationType.questAssigned,
    referenceId: _activeUserQuest.id,
    createdAt: _now.subtract(const Duration(hours: 1)),
  ),
];

const _collabStatus = CollabGroupStatusModel(
  isCollab: true,
  groupId: 'group-1',
  mode: CollabMode.versus,
  status: CollabGroupStatus.open,
  code: _joinCode,
  maxMembers: 5,
  members: [
    CollabMemberStatus(
      userId: 'user-1',
      username: 'bitsheel',
      displayName: 'Bit Sheel',
      questStatus: UserQuestStatus.assigned,
      submissionStatus: SubmissionStatus.pending,
      voteCount: 5,
    ),
    CollabMemberStatus(
      userId: 'user-2',
      username: 'pixelrana',
      displayName: 'Pixel Rana',
      questStatus: UserQuestStatus.assigned,
      submissionStatus: SubmissionStatus.approved,
      voteCount: 3,
    ),
  ],
);

final _collabPreview = CollabGroupPreviewModel(
  groupId: 'group-1',
  code: _joinCode,
  mode: CollabMode.versus,
  status: CollabGroupStatus.open,
  memberCount: 2,
  maxMembers: 5,
  expiresAt: _now.add(const Duration(hours: 3)),
  members: const [
    CollabGroupPreviewMember(
      userId: 'user-1',
      username: 'bitsheel',
      displayName: 'Bit Sheel',
    ),
    CollabGroupPreviewMember(
      userId: 'user-2',
      username: 'pixelrana',
      displayName: 'Pixel Rana',
    ),
  ],
  questTitle: _quest.title,
  questDescription: _quest.description,
  questCategory: _quest.category,
  questDifficulty: _quest.difficulty,
  questXpReward: _quest.xpReward,
  questDurationHours: _quest.durationHours,
  creatorUsername: _otherProfile.username,
  creatorDisplayName: _otherProfile.displayName,
);

final _reactions = [
  ReactionModel(
    id: 'reaction-1',
    submissionId: _feedPost.id,
    userId: _profile.id,
    type: ReactionType.upvote,
    createdAt: _now.subtract(const Duration(hours: 2)),
  ),
  ReactionModel(
    id: 'reaction-2',
    submissionId: _feedPost.id,
    userId: _otherProfile.id,
    type: ReactionType.downvote,
    createdAt: _now.subtract(const Duration(hours: 1)),
  ),
];

final _comments = [
  CommentModel(
    id: 'comment-1',
    submissionId: _feedPost.id,
    userId: _otherProfile.id,
    body: 'This is such a good hidden detail.',
    username: _otherProfile.username,
    displayName: _otherProfile.displayName,
    createdAt: _now.subtract(const Duration(minutes: 50)),
  ),
  CommentModel(
    id: 'comment-2',
    submissionId: _feedPost.id,
    userId: _profile.id,
    body: 'I almost walked past it.',
    username: _profile.username,
    displayName: _profile.displayName,
    createdAt: _now.subtract(const Duration(minutes: 30)),
  ),
];

class _FakeFeedNotifier extends FeedNotifier {
  @override
  Future<FeedState> build() async {
    return FeedState(posts: _feedPosts, hasMore: false);
  }
}

class _FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthState>.broadcast();

  @override
  Stream<AuthState> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => null;

  @override
  Future<AuthResult> signInWithEmail(String email, String password) async {
    return const AuthResult();
  }

  @override
  Future<AuthResult> signUpWithEmail(
    String email,
    String password, {
    Map<String, dynamic>? data,
  }) async {
    return const AuthResult();
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> resetPassword(String email) async {}

  @override
  Future<void> resendSignupConfirmation(String email) async {}

  @override
  Future<AuthUser> updatePassword(String currentPassword, String newPassword) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResult> signInWithApple() async => const AuthResult();

  @override
  Future<AuthResult> signInWithGoogle() async => const AuthResult();

  @override
  Future<AuthResult> signInWithPhone(String phoneNumber, {String? email}) async =>
      const AuthResult();

  @override
  Future<AuthResult> linkPhone(String phoneNumber) async => const AuthResult();

  @override
  void handlePhoneCallback(Uri uri) {}
}

class _FakeQuestsRepository implements QuestsRepository {
  @override
  Future<QuestModel> getQuest(String questId) async => _allQuests
      .firstWhere((quest) => quest.id == questId, orElse: () => _quest);

  @override
  Future<List<QuestModel>> listAllQuestsAdmin() async => _allQuests;

  @override
  Future<List<QuestModel>> getQuestPickerOptions({int count = 3}) async =>
      _allQuests.take(count).toList();

  @override
  Future<QuestModel> createQuest({
    required String title,
    required String description,
    required String category,
    required String difficulty,
    required int xpReward,
    int durationHours = 4,
    bool isActive = true,
  }) async {
    return QuestModel(
      id: 'created-quest',
      title: title,
      description: description,
      category: category,
      difficulty: difficulty,
      xpReward: xpReward,
      durationHours: durationHours,
      isActive: isActive,
      createdAt: _now,
    );
  }

  @override
  Future<QuestModel> updateQuest(QuestModel quest) async => quest;

  @override
  Future<UserQuestModel?> getActiveUserQuest(String userId) async =>
      _activeUserQuest;

  @override
  Future<UserQuestModel> assignSpecificQuest(
      String userId, String questId) async {
    return _activeUserQuest;
  }

  @override
  Future<void> expireOverdueQuests(String userId) async {}

  @override
  Future<void> markQuestExpired(String userQuestId) async {}

  @override
  Future<List<UserQuestModel>> getUserQuestHistory(String userId) async =>
      _questHistory;
}

class _FakeSubmissionsRepository implements SubmissionsRepository {
  @override
  Future<SubmissionModel> createSubmission(SubmissionModel submission) async =>
      submission;

  @override
  Future<String> uploadSubmissionMedia(
    String userId,
    String submissionId,
    Uint8List fileBytes,
    String fileName,
    String mediaType, {
    int index = 0,
  }) async {
    return '';
  }

  @override
  Future<SubmissionModel?> getSubmission(String submissionId) async {
    return _submissions.firstWhere(
      (submission) => submission.id == submissionId,
      orElse: () => _approvedSubmission,
    );
  }

  @override
  Future<List<SubmissionModel>> getUserSubmissions(String userId) async =>
      _submissions;

  @override
  Future<void> setSubmissionVisibility(
    String submissionId,
    SoftDeleteMode mode,
  ) async {}
}

class _FakeFeedRepository implements FeedRepository {
  @override
  Future<List<FeedPostModel>> getFeed({
    int limit = 20,
    int offset = 0,
    FeedScope scope = FeedScope.all,
    String sort = 'recent',
  }) async =>
      _feedPosts;

  @override
  Future<FeedPostModel> getFeedPostDetails(String submissionId) async =>
      _feedPost;
}

class _FakeLeaderboardRepository implements LeaderboardRepository {
  @override
  Future<List<LeaderboardUserModel>> getLeaderboard({int limit = 50}) async =>
      _leaderboard;

  @override
  Future<List<LeaderboardUserModel>> getFollowingLeaderboard(
      {int limit = 50}) async {
    return _leaderboard.take(2).toList();
  }
}

class _FakeNotificationsRepository implements NotificationsRepository {
  @override
  Future<List<NotificationModel>> getNotifications(String userId) async =>
      _notifications;

  @override
  Future<int> getUnreadCount(String userId) async => 2;

  @override
  Future<void> markAsRead(String notificationId) async {}

  @override
  Future<void> markAllAsRead(String userId) async {}
}

class _FakeCollabRepository implements CollabRepository {
  @override
  Future<Map<String, dynamic>> createGroup(
      String userQuestId, String mode) async {
    return {'code': _joinCode, 'group_id': 'group-1'};
  }

  @override
  Future<CollabGroupPreviewModel> getGroupDetails(String code) async =>
      _collabPreview;

  @override
  Future<Map<String, dynamic>> joinGroup(String code) async {
    return {'ok': true};
  }

  @override
  Future<CollabGroupStatusModel> getGroupStatus(String userQuestId) async =>
      _collabStatus;

  @override
  Future<void> abandonQuest(String userQuestId) async {}

  @override
  Future<void> voteCollab(String groupId, String submissionId) async {}

  @override
  Future<void> unvoteCollab(String groupId, String submissionId) async {}
}

class _FakeReactionsRepository implements ReactionsRepository {
  @override
  Future<ReactionModel?> getMyVote(String submissionId, String userId) async {
    return _reactions.cast<ReactionModel?>().firstWhere(
          (r) => r!.submissionId == submissionId && r.userId == userId,
          orElse: () => null,
        );
  }

  @override
  Future<ReactionModel> vote(
      String submissionId, String userId, String type) async {
    return ReactionModel(
      id: 'reaction-created',
      submissionId: submissionId,
      userId: userId,
      type: type,
      createdAt: _now,
    );
  }

  @override
  Future<void> removeVote(String submissionId, String userId) async {}
}
