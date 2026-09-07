import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_core/app_core.dart';
import 'core/backend/backend_config.dart';
import 'core/backend/mobile_nest_backend.dart';
import 'core/config/env.dart';
import 'core/router/app_router.dart' show primeSplashShownFlag;
import 'core/services/analytics_service.dart';
import 'core/services/device_token_service.dart';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

const _androidChannel = AndroidNotificationChannel(
  'bitsheel_push',
  'Bsheel Notifications',
  description: 'Push notifications from Bsheel',
  importance: Importance.high,
  sound: RawResourceAndroidNotificationSound('quest_notification'),
);

Future<AndroidNotificationDetails> _androidNotificationDetailsFor(
  RemoteMessage message,
) async {
  final imageUrl = message.data['actor_avatar_url'] as String?;
  BigPictureStyleInformation? styleInformation;
  ByteArrayAndroidBitmap? largeIcon;

  if (imageUrl != null && imageUrl.startsWith('https://')) {
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final bitmap = ByteArrayAndroidBitmap(response.bodyBytes);
        largeIcon = bitmap;
        styleInformation = BigPictureStyleInformation(
          bitmap,
          largeIcon: bitmap,
          hideExpandedLargeIcon: false,
        );
      }
    } catch (e) {
      AppLogger.info('[Push] Could not load actor image: $e');
    }
  }

  return AndroidNotificationDetails(
    _androidChannel.id,
    _androidChannel.name,
    channelDescription: _androidChannel.description,
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
    largeIcon: largeIcon,
    styleInformation: styleInformation,
    sound: const RawResourceAndroidNotificationSound('quest_notification'),
  );
}

/// Handle background messages (must be top-level function).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
  AppLogger.info('[Push] Background message: ${message.messageId}');
}

/// Critical init — blocks runApp(). Keep this as small as possible to avoid
/// the native launch screen staying up while we do background-safe work.
Future<void> bootstrap() async {
  // Load the persisted "splash already shown" flag in parallel with
  // Supabase init — both finish before runApp() so GoRouter can pick the
  // right initialLocation synchronously (no extra splash on cold start
  // after the first install).
  final splashFuture = primeSplashShownFlag();

  if (BackendConfig.usesNest) {
    await MobileNestBackend.initialize();
    AppLogger.info('[Bootstrap] Nest backend initialized successfully');
  } else {
    await _initializeLegacyBackend();
  }

  await splashFuture;
}

Future<void> _initializeLegacyBackend() async {
  try {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: true,
        // F-006 (pentest 2026-05-20): force PKCE. With the implicit /
        // token-fragment flow, an intercepted reset-password deep link
        // hands an attacker the access_token directly. With PKCE the
        // email link only carries a one-shot `code` that must be
        // exchanged using the code_verifier we generated and stored on
        // THIS device — so even an intercepted link is useless to a
        // foreign app. supabase_flutter >= 2.0 defaults to PKCE; we
        // pin it explicitly here so a future SDK default flip can't
        // silently regress us.
        authFlowType: AuthFlowType.pkce,
        localStorage: kIsWeb
            ? SharedPreferencesLocalStorage(
                persistSessionKey: 'sb-4hoursonly-mobile-web-auth-v2',
              )
            : null,
      ),
    );
    AppLogger.info('[Bootstrap] Supabase initialized successfully');
  } on Exception catch (e) {
    AppLogger.info('[Bootstrap] Supabase init auth event: ${e.toString()}');
  }
}

/// Everything else — Firebase, Mixpanel, FCM, notification channels, badge
/// clear, topic subscribe. Runs in the background after the first frame.
Future<void> initDeferredServices() async {
  // Analytics
  try {
    await AnalyticsService.instance.init();
    AnalyticsService.instance.appOpened();
    final existingUser = _currentUser;
    if (existingUser != null) {
      AnalyticsService.instance.identify(
        existingUser.id,
        username: existingUser.userMetadata?['username'] as String?,
      );
    }
  } catch (e) {
    AppLogger.info('[Bootstrap] Analytics init failed: $e');
  }

  if (kIsWeb) {
    AppLogger.info('[Push] Skipping Firebase Messaging setup on web.');
    return;
  }

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    await _localNotifications.initialize(
      const InitializationSettings(
        iOS: DarwinInitializationSettings(defaultPresentSound: true),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );

    final token = await messaging.getToken();
    AppLogger.info(
        '[Bootstrap] FCM token: ${token != null ? "${token.substring(0, 20)}..." : "NULL"}');
    final user = _currentUser;
    if (token != null && user != null) {
      try {
        await DeviceTokenService.register(token);
        AppLogger.info('[Bootstrap] FCM token saved successfully');
      } catch (e) {
        AppLogger.info('[Bootstrap] ERROR saving FCM token: $e');
      }
    }

    messaging.onTokenRefresh.listen((newToken) async {
      final user = _currentUser;
      if (user != null) {
        try {
          await DeviceTokenService.register(newToken);
        } catch (e) {
          AppLogger.info('[Push] Could not save refreshed FCM token: $e');
        }
      }
    });

    try {
      await _localNotifications.show(
        0,
        null,
        null,
        const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: true,
            presentSound: false,
            badgeNumber: 0,
          ),
        ),
      );
      await _localNotifications.cancel(0);
    } catch (e) {
      AppLogger.info('[Push] Badge clear failed (non-fatal): $e');
    }

    await messaging.subscribeToTopic('all_users');

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final title =
          message.notification?.title ?? message.data['title'] as String?;
      final body =
          message.notification?.body ?? message.data['body'] as String?;
      if (title == null || body == null) return;

      _localNotifications.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'quest_notification.caf',
          ),
          android: await _androidNotificationDetailsFor(message),
        ),
      );
    });
  } catch (e) {
    AppLogger.info('[Bootstrap] Deferred init failed: $e');
  }
}

User? get _currentUser => BackendConfig.usesNest
    ? MobileNestBackend.repositories.auth.currentUser
    : Supabase.instance.client.auth.currentUser;
