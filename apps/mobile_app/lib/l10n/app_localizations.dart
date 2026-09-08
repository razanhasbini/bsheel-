import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_lb.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('lb')
  ];

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get login;

  /// No description provided for @signup.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signup;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @feed.
  ///
  /// In en, this message translates to:
  /// **'Feed'**
  String get feed;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @leaderboard.
  ///
  /// In en, this message translates to:
  /// **'Leaderboard'**
  String get leaderboard;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @quest.
  ///
  /// In en, this message translates to:
  /// **'Quest'**
  String get quest;

  /// No description provided for @quests.
  ///
  /// In en, this message translates to:
  /// **'Quests'**
  String get quests;

  /// No description provided for @submitProof.
  ///
  /// In en, this message translates to:
  /// **'Submit Proof'**
  String get submitProof;

  /// No description provided for @streak.
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get streak;

  /// No description provided for @level.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get level;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @noNewSignals.
  ///
  /// In en, this message translates to:
  /// **'No new signals'**
  String get noNewSignals;

  /// No description provided for @failedToLoad.
  ///
  /// In en, this message translates to:
  /// **'Failed to load'**
  String get failedToLoad;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @social.
  ///
  /// In en, this message translates to:
  /// **'Social'**
  String get social;

  /// No description provided for @rewards.
  ///
  /// In en, this message translates to:
  /// **'Rewards'**
  String get rewards;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @questDetails.
  ///
  /// In en, this message translates to:
  /// **'Quest details'**
  String get questDetails;

  /// No description provided for @questHistory.
  ///
  /// In en, this message translates to:
  /// **'Quest history'**
  String get questHistory;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfile;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @noAccountYet.
  ///
  /// In en, this message translates to:
  /// **'No account yet?'**
  String get noAccountYet;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get alreadyHaveAccount;

  /// No description provided for @caption.
  ///
  /// In en, this message translates to:
  /// **'Caption'**
  String get caption;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT'**
  String get account;

  /// No description provided for @app.
  ///
  /// In en, this message translates to:
  /// **'APP'**
  String get app;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'ABOUT BSHEEL'**
  String get aboutApp;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version 1.0.0'**
  String get version;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'A gamified quest app that turns real-life challenges into adventures. Complete quests, earn XP, and level up!'**
  String get aboutDescription;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'PRIVACY POLICY'**
  String get privacyPolicy;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'TERMS OF SERVICE'**
  String get termsOfService;

  /// No description provided for @dangerZone.
  ///
  /// In en, this message translates to:
  /// **'DANGER ZONE'**
  String get dangerZone;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'DELETE ACCOUNT'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountWarning.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete your account and all data. This cannot be undone.'**
  String get deleteAccountWarning;

  /// No description provided for @typeDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Type DELETE to confirm:'**
  String get typeDeleteConfirm;

  /// No description provided for @deletionRequested.
  ///
  /// In en, this message translates to:
  /// **'Account deletion request sent. Your data will be removed within 48 hours.'**
  String get deletionRequested;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'LANGUAGE'**
  String get language;

  /// Settings group header for display options.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get display;

  /// Settings row label for the blocked-users list.
  ///
  /// In en, this message translates to:
  /// **'BLOCKED USERS'**
  String get blockedUsers;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'DARK'**
  String get dark;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'LIGHT'**
  String get light;

  /// No description provided for @lebaneseArabizi.
  ///
  /// In en, this message translates to:
  /// **'Lebanese Arabizi'**
  String get lebaneseArabizi;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'CREATE ACCOUNT'**
  String get createAccount;

  /// No description provided for @chooseUsername.
  ///
  /// In en, this message translates to:
  /// **'Choose a username'**
  String get chooseUsername;

  /// No description provided for @enterEmail.
  ///
  /// In en, this message translates to:
  /// **'your@email.com'**
  String get enterEmail;

  /// No description provided for @enterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get enterPassword;

  /// No description provided for @createPassword.
  ///
  /// In en, this message translates to:
  /// **'Create a password'**
  String get createPassword;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'RESET PASSWORD'**
  String get resetPassword;

  /// No description provided for @backToLogin.
  ///
  /// In en, this message translates to:
  /// **'BACK TO LOGIN'**
  String get backToLogin;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'NEW PASSWORD'**
  String get newPassword;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM PASSWORD'**
  String get confirmPassword;

  /// No description provided for @enterNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter new password'**
  String get enterNewPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get confirmNewPassword;

  /// No description provided for @passwordUpdated.
  ///
  /// In en, this message translates to:
  /// **'PASSWORD UPDATED'**
  String get passwordUpdated;

  /// No description provided for @goToLogin.
  ///
  /// In en, this message translates to:
  /// **'GO TO LOGIN'**
  String get goToLogin;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'DISPLAY NAME'**
  String get displayName;

  /// No description provided for @yourDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Your display name'**
  String get yourDisplayName;

  /// No description provided for @bio.
  ///
  /// In en, this message translates to:
  /// **'BIO'**
  String get bio;

  /// No description provided for @maxFourWords.
  ///
  /// In en, this message translates to:
  /// **'Max 4 words...'**
  String get maxFourWords;

  /// No description provided for @usernameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. shadow_hunter'**
  String get usernameHint;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'SKIP'**
  String get skip;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'NEXT'**
  String get next;

  /// No description provided for @letsGo.
  ///
  /// In en, this message translates to:
  /// **'LET\'S GO'**
  String get letsGo;

  /// No description provided for @onboarding1Title.
  ///
  /// In en, this message translates to:
  /// **'WELCOME TO\nBSHEEL'**
  String get onboarding1Title;

  /// No description provided for @onboarding1Subtitle.
  ///
  /// In en, this message translates to:
  /// **'YOUR REAL-LIFE QUEST ENGINE.\nCOMPLETE CHALLENGES.\nLEVEL UP IRL.'**
  String get onboarding1Subtitle;

  /// No description provided for @onboarding2Title.
  ///
  /// In en, this message translates to:
  /// **'HOW QUESTS\nWORK'**
  String get onboarding2Title;

  /// No description provided for @onboarding2Subtitle.
  ///
  /// In en, this message translates to:
  /// **'ROLL FOR A QUEST.\nACCEPT THE CHALLENGE.\nSUBMIT PROOF BEFORE\nTIME RUNS OUT.'**
  String get onboarding2Subtitle;

  /// No description provided for @onboarding3Title.
  ///
  /// In en, this message translates to:
  /// **'EARN XP &\nLEVEL UP'**
  String get onboarding3Title;

  /// No description provided for @onboarding3Subtitle.
  ///
  /// In en, this message translates to:
  /// **'EVERY QUEST COMPLETED\nEARNS YOU XP.\nCLIMB THE LEADERBOARD.\nUNLOCK NEW RANKS.'**
  String get onboarding3Subtitle;

  /// No description provided for @onboarding4Title.
  ///
  /// In en, this message translates to:
  /// **'YOU\'RE\nREADY'**
  String get onboarding4Title;

  /// No description provided for @onboarding4Subtitle.
  ///
  /// In en, this message translates to:
  /// **'YOUR ADVENTURE\nSTARTS NOW.\nGO ROLL YOUR\nFIRST QUEST!'**
  String get onboarding4Subtitle;

  /// No description provided for @activeQuest.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE QUEST'**
  String get activeQuest;

  /// No description provided for @proofSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Proof submitted'**
  String get proofSubmitted;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'PENDING'**
  String get pending;

  /// No description provided for @questExpired.
  ///
  /// In en, this message translates to:
  /// **'QUEST EXPIRED'**
  String get questExpired;

  /// No description provided for @noQuestsYet.
  ///
  /// In en, this message translates to:
  /// **'No quest history yet. Generate and complete quests to see them here.'**
  String get noQuestsYet;

  /// No description provided for @missionBriefing.
  ///
  /// In en, this message translates to:
  /// **'MISSION BRIEFING'**
  String get missionBriefing;

  /// No description provided for @acceptanceCriteria.
  ///
  /// In en, this message translates to:
  /// **'ACCEPTANCE CRITERIA'**
  String get acceptanceCriteria;

  /// No description provided for @submissionRequirements.
  ///
  /// In en, this message translates to:
  /// **'SUBMISSION REQUIREMENTS'**
  String get submissionRequirements;

  /// No description provided for @rewardsLabel.
  ///
  /// In en, this message translates to:
  /// **'REWARDS'**
  String get rewardsLabel;

  /// No description provided for @difficulty.
  ///
  /// In en, this message translates to:
  /// **'DIFFICULTY'**
  String get difficulty;

  /// No description provided for @reward.
  ///
  /// In en, this message translates to:
  /// **'REWARD'**
  String get reward;

  /// No description provided for @timeLeft.
  ///
  /// In en, this message translates to:
  /// **'TIME LEFT'**
  String get timeLeft;

  /// No description provided for @criteriaProof.
  ///
  /// In en, this message translates to:
  /// **'Proof clearly shows you completed the quest action.'**
  String get criteriaProof;

  /// No description provided for @criteriaQuality.
  ///
  /// In en, this message translates to:
  /// **'Submission content matches the quest intent and quality standards.'**
  String get criteriaQuality;

  /// No description provided for @criteriaCaption.
  ///
  /// In en, this message translates to:
  /// **'Caption provides enough context for moderation review.'**
  String get criteriaCaption;

  /// No description provided for @reqCaptureProof.
  ///
  /// In en, this message translates to:
  /// **'Capture photo or video proof before the timer ends.'**
  String get reqCaptureProof;

  /// No description provided for @reqGenerateFirst.
  ///
  /// In en, this message translates to:
  /// **'Generate or accept this quest before submitting proof.'**
  String get reqGenerateFirst;

  /// No description provided for @reqUploadProof.
  ///
  /// In en, this message translates to:
  /// **'Upload your proof to send it for review.'**
  String get reqUploadProof;

  /// No description provided for @activity.
  ///
  /// In en, this message translates to:
  /// **'ACTIVITY'**
  String get activity;

  /// No description provided for @badges.
  ///
  /// In en, this message translates to:
  /// **'BADGES'**
  String get badges;

  /// No description provided for @posts.
  ///
  /// In en, this message translates to:
  /// **'POSTS'**
  String get posts;

  /// No description provided for @followers.
  ///
  /// In en, this message translates to:
  /// **'FOLLOWERS'**
  String get followers;

  /// No description provided for @following.
  ///
  /// In en, this message translates to:
  /// **'FOLLOWING'**
  String get following;

  /// No description provided for @completedQuests.
  ///
  /// In en, this message translates to:
  /// **'COMPLETED QUESTS'**
  String get completedQuests;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @noFollowersYet.
  ///
  /// In en, this message translates to:
  /// **'No followers yet'**
  String get noFollowersYet;

  /// No description provided for @notFollowingAnyone.
  ///
  /// In en, this message translates to:
  /// **'Not following anyone'**
  String get notFollowingAnyone;

  /// No description provided for @changePhoto.
  ///
  /// In en, this message translates to:
  /// **'CHANGE PHOTO'**
  String get changePhoto;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'REMOVE'**
  String get remove;

  /// No description provided for @savingChanges.
  ///
  /// In en, this message translates to:
  /// **'SAVING...'**
  String get savingChanges;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'SAVE CHANGES'**
  String get saveChanges;

  /// No description provided for @usernameLength.
  ///
  /// In en, this message translates to:
  /// **'Username must be 3-30 characters.'**
  String get usernameLength;

  /// No description provided for @usernameFormat.
  ///
  /// In en, this message translates to:
  /// **'Username can only contain letters, numbers, and underscores.'**
  String get usernameFormat;

  /// No description provided for @noPostsYet.
  ///
  /// In en, this message translates to:
  /// **'NO POSTS YET'**
  String get noPostsYet;

  /// No description provided for @completeToAppear.
  ///
  /// In en, this message translates to:
  /// **'Complete quests to appear here.'**
  String get completeToAppear;

  /// No description provided for @addComment.
  ///
  /// In en, this message translates to:
  /// **'Add a comment...'**
  String get addComment;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'SHARE'**
  String get share;

  /// No description provided for @comments.
  ///
  /// In en, this message translates to:
  /// **'COMMENTS'**
  String get comments;

  /// No description provided for @noCommentsYet.
  ///
  /// In en, this message translates to:
  /// **'No comments yet. Be the first!'**
  String get noCommentsYet;

  /// No description provided for @couldNotLoadComments.
  ///
  /// In en, this message translates to:
  /// **'Could not load comments.'**
  String get couldNotLoadComments;

  /// No description provided for @said.
  ///
  /// In en, this message translates to:
  /// **'said:'**
  String get said;

  /// No description provided for @video.
  ///
  /// In en, this message translates to:
  /// **'VIDEO'**
  String get video;

  /// No description provided for @submissions.
  ///
  /// In en, this message translates to:
  /// **'SUBMISSIONS'**
  String get submissions;

  /// No description provided for @captionHint.
  ///
  /// In en, this message translates to:
  /// **'Describe how you completed the quest...'**
  String get captionHint;

  /// No description provided for @sessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Please log in again.'**
  String get sessionExpired;

  /// No description provided for @addMedia.
  ///
  /// In en, this message translates to:
  /// **'Add at least one image or video.'**
  String get addMedia;

  /// No description provided for @proofSubmittedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Proof submitted! Waiting for approval.'**
  String get proofSubmittedSuccess;

  /// No description provided for @submissionTitle.
  ///
  /// In en, this message translates to:
  /// **'SUBMISSION'**
  String get submissionTitle;

  /// No description provided for @submissionNotFound.
  ///
  /// In en, this message translates to:
  /// **'Submission not found'**
  String get submissionNotFound;

  /// No description provided for @yourProof.
  ///
  /// In en, this message translates to:
  /// **'YOUR PROOF'**
  String get yourProof;

  /// No description provided for @moderatorFeedback.
  ///
  /// In en, this message translates to:
  /// **'MODERATOR FEEDBACK'**
  String get moderatorFeedback;

  /// No description provided for @rejectionReasons.
  ///
  /// In en, this message translates to:
  /// **'REJECTION REASONS'**
  String get rejectionReasons;

  /// No description provided for @sendRequest.
  ///
  /// In en, this message translates to:
  /// **'SEND REQUEST'**
  String get sendRequest;

  /// No description provided for @revalidationHint.
  ///
  /// In en, this message translates to:
  /// **'Write your revalidation request here...'**
  String get revalidationHint;

  /// No description provided for @noRankingsYet.
  ///
  /// In en, this message translates to:
  /// **'NO RANKINGS YET'**
  String get noRankingsYet;

  /// No description provided for @rank.
  ///
  /// In en, this message translates to:
  /// **'Rank'**
  String get rank;

  /// No description provided for @notAuthorized.
  ///
  /// In en, this message translates to:
  /// **'You are not authorized.'**
  String get notAuthorized;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'GO BACK'**
  String get goBack;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'ADMIN'**
  String get admin;

  /// No description provided for @pendingReview.
  ///
  /// In en, this message translates to:
  /// **'PENDING REVIEW'**
  String get pendingReview;

  /// No description provided for @allClear.
  ///
  /// In en, this message translates to:
  /// **'ALL CLEAR'**
  String get allClear;

  /// No description provided for @noPendingSubmissions.
  ///
  /// In en, this message translates to:
  /// **'No pending submissions.'**
  String get noPendingSubmissions;

  /// No description provided for @submissionApproved.
  ///
  /// In en, this message translates to:
  /// **'Submission approved'**
  String get submissionApproved;

  /// No description provided for @rejectSubmission.
  ///
  /// In en, this message translates to:
  /// **'REJECT SUBMISSION'**
  String get rejectSubmission;

  /// No description provided for @reasonOptional.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional):'**
  String get reasonOptional;

  /// No description provided for @rejectHint.
  ///
  /// In en, this message translates to:
  /// **'Why is this being rejected?'**
  String get rejectHint;

  /// No description provided for @submissionRejected.
  ///
  /// In en, this message translates to:
  /// **'Submission rejected'**
  String get submissionRejected;

  /// No description provided for @broadcastTitle.
  ///
  /// In en, this message translates to:
  /// **'BROADCAST TO ALL USERS'**
  String get broadcastTitle;

  /// No description provided for @notificationTitle.
  ///
  /// In en, this message translates to:
  /// **'NOTIFICATION TITLE'**
  String get notificationTitle;

  /// No description provided for @notificationTitleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. NEW QUESTS DROPPED'**
  String get notificationTitleHint;

  /// No description provided for @messageBody.
  ///
  /// In en, this message translates to:
  /// **'MESSAGE BODY'**
  String get messageBody;

  /// No description provided for @messageBodyHint.
  ///
  /// In en, this message translates to:
  /// **'What do you want to tell your players?'**
  String get messageBodyHint;

  /// No description provided for @titleAndBodyRequired.
  ///
  /// In en, this message translates to:
  /// **'Title and body are required'**
  String get titleAndBodyRequired;

  /// No description provided for @pushSent.
  ///
  /// In en, this message translates to:
  /// **'Push notification sent to all users'**
  String get pushSent;

  /// No description provided for @recentlySent.
  ///
  /// In en, this message translates to:
  /// **'RECENTLY SENT'**
  String get recentlySent;

  /// No description provided for @failedToLoadHistory.
  ///
  /// In en, this message translates to:
  /// **'Failed to load history'**
  String get failedToLoadHistory;

  /// No description provided for @completeToSeeHistory.
  ///
  /// In en, this message translates to:
  /// **'Complete quests to see them here'**
  String get completeToSeeHistory;

  /// No description provided for @tapToRetry.
  ///
  /// In en, this message translates to:
  /// **'Tap to retry'**
  String get tapToRetry;

  /// No description provided for @follow.
  ///
  /// In en, this message translates to:
  /// **'FOLLOW'**
  String get follow;

  /// No description provided for @followed.
  ///
  /// In en, this message translates to:
  /// **'FOLLOWED'**
  String get followed;

  /// No description provided for @showInFeed.
  ///
  /// In en, this message translates to:
  /// **'SHOW IN FEED'**
  String get showInFeed;

  /// No description provided for @showInFeedOn.
  ///
  /// In en, this message translates to:
  /// **'Everyone can see this quest in the feed'**
  String get showInFeedOn;

  /// No description provided for @showInFeedOff.
  ///
  /// In en, this message translates to:
  /// **'Only visible on your profile'**
  String get showInFeedOff;

  /// No description provided for @deleteFromFeed.
  ///
  /// In en, this message translates to:
  /// **'DELETE FROM FEED'**
  String get deleteFromFeed;

  /// No description provided for @deleteFromProfile.
  ///
  /// In en, this message translates to:
  /// **'DELETE FROM PROFILE'**
  String get deleteFromProfile;

  /// No description provided for @deleteFromFeedDesc.
  ///
  /// In en, this message translates to:
  /// **'This will remove the post from the feed. It will still be visible on your profile.'**
  String get deleteFromFeedDesc;

  /// No description provided for @deleteFromProfileDesc.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete the post from the feed and your profile. This cannot be undone.'**
  String get deleteFromProfileDesc;

  /// No description provided for @addToFeed.
  ///
  /// In en, this message translates to:
  /// **'ADD TO FEED'**
  String get addToFeed;

  /// No description provided for @postAddedToFeed.
  ///
  /// In en, this message translates to:
  /// **'Post added to feed'**
  String get postAddedToFeed;

  /// No description provided for @hideFromFeed.
  ///
  /// In en, this message translates to:
  /// **'HIDE FROM FEED'**
  String get hideFromFeed;

  /// No description provided for @permanentlyDelete.
  ///
  /// In en, this message translates to:
  /// **'PERMANENTLY DELETE'**
  String get permanentlyDelete;

  /// No description provided for @postRemovedFromFeed.
  ///
  /// In en, this message translates to:
  /// **'Post removed from feed'**
  String get postRemovedFromFeed;

  /// No description provided for @postDeletedPermanently.
  ///
  /// In en, this message translates to:
  /// **'Post deleted permanently'**
  String get postDeletedPermanently;

  /// No description provided for @deletedPosts.
  ///
  /// In en, this message translates to:
  /// **'DELETED POSTS'**
  String get deletedPosts;

  /// No description provided for @noDeletedPosts.
  ///
  /// In en, this message translates to:
  /// **'NO DELETED POSTS'**
  String get noDeletedPosts;

  /// No description provided for @noDeletedPostsDesc.
  ///
  /// In en, this message translates to:
  /// **'No posts have been deleted yet.'**
  String get noDeletedPostsDesc;

  /// No description provided for @hiddenFromFeed.
  ///
  /// In en, this message translates to:
  /// **'HIDDEN FROM FEED'**
  String get hiddenFromFeed;

  /// No description provided for @deletedFromProfile.
  ///
  /// In en, this message translates to:
  /// **'DELETED PERMANENTLY'**
  String get deletedFromProfile;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'SEARCH PEOPLE OR QUESTS'**
  String get searchHint;

  /// No description provided for @searchPeople.
  ///
  /// In en, this message translates to:
  /// **'PEOPLE'**
  String get searchPeople;

  /// No description provided for @searchQuests.
  ///
  /// In en, this message translates to:
  /// **'QUESTS'**
  String get searchQuests;

  /// No description provided for @searchPosts.
  ///
  /// In en, this message translates to:
  /// **'POSTS'**
  String get searchPosts;

  /// No description provided for @searchPrompt.
  ///
  /// In en, this message translates to:
  /// **'FIND PEOPLE & QUESTS'**
  String get searchPrompt;

  /// No description provided for @searchPromptSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Type a username, display name, or quest keyword to begin.'**
  String get searchPromptSubtitle;

  /// No description provided for @searchNoMatches.
  ///
  /// In en, this message translates to:
  /// **'NO MATCHES'**
  String get searchNoMatches;

  /// No description provided for @searchNoMatchesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Try a different keyword.'**
  String get searchNoMatchesSubtitle;

  /// No description provided for @searchFailed.
  ///
  /// In en, this message translates to:
  /// **'SEARCH FAILED'**
  String get searchFailed;

  /// No description provided for @searchRecent.
  ///
  /// In en, this message translates to:
  /// **'RECENT'**
  String get searchRecent;

  /// No description provided for @searchClearRecent.
  ///
  /// In en, this message translates to:
  /// **'CLEAR'**
  String get searchClearRecent;

  /// No description provided for @homeHeadline.
  ///
  /// In en, this message translates to:
  /// **'Bsheel?'**
  String get homeHeadline;

  /// No description provided for @homeHeadlineTagline.
  ///
  /// In en, this message translates to:
  /// **'ONE QUEST · LIMITED TIME · BSHEEL?'**
  String get homeHeadlineTagline;

  /// No description provided for @generateAQuest.
  ///
  /// In en, this message translates to:
  /// **'GENERATE A QUEST'**
  String get generateAQuest;

  /// No description provided for @inReviewTapToSeeAll.
  ///
  /// In en, this message translates to:
  /// **'IN REVIEW · TAP TO SEE ALL'**
  String get inReviewTapToSeeAll;

  /// No description provided for @questHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'QUEST HISTORY'**
  String get questHistoryTitle;

  /// No description provided for @savedToBsheeel.
  ///
  /// In en, this message translates to:
  /// **'Saved to BSHEEEL'**
  String get savedToBsheeel;

  /// No description provided for @removedFromBsheeel.
  ///
  /// In en, this message translates to:
  /// **'Removed from BSHEEEL'**
  String get removedFromBsheeel;

  /// No description provided for @noSavedPostsYet.
  ///
  /// In en, this message translates to:
  /// **'NO SAVED POSTS YET'**
  String get noSavedPostsYet;

  /// No description provided for @savedPostsHint.
  ///
  /// In en, this message translates to:
  /// **'Tap BSHEEEL on posts to save them here'**
  String get savedPostsHint;

  /// No description provided for @passwordKeepCurrent.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to keep current'**
  String get passwordKeepCurrent;

  /// No description provided for @sending.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get sending;

  /// No description provided for @sendResetLink.
  ///
  /// In en, this message translates to:
  /// **'SEND RESET LINK'**
  String get sendResetLink;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @setNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Set new password'**
  String get setNewPassword;

  /// No description provided for @questsDone.
  ///
  /// In en, this message translates to:
  /// **'QUESTS DONE'**
  String get questsDone;

  /// No description provided for @xpEarnedLabel.
  ///
  /// In en, this message translates to:
  /// **'XP EARNED'**
  String get xpEarnedLabel;

  /// No description provided for @allTime.
  ///
  /// In en, this message translates to:
  /// **'ALL TIME'**
  String get allTime;

  /// No description provided for @usernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Username is required.'**
  String get usernameRequired;

  /// No description provided for @usernameLengthError.
  ///
  /// In en, this message translates to:
  /// **'Must be 3–30 characters.'**
  String get usernameLengthError;

  /// No description provided for @usernameFormatError.
  ///
  /// In en, this message translates to:
  /// **'Letters, numbers, and underscores only.'**
  String get usernameFormatError;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required.'**
  String get emailRequired;

  /// No description provided for @emailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid email address.'**
  String get emailInvalid;

  /// No description provided for @pleaseEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password.'**
  String get pleaseEnterPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get passwordsDoNotMatch;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'lb'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'lb':
      return AppLocalizationsLb();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
