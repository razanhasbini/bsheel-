import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()

    // Register for remote notifications
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)

    // Tiny method channel so Flutter can clear the app icon badge +
    // delivered notifications when the user opens the notifications page.
    if let controller = window?.rootViewController as? FlutterViewController {
      let badgeChannel = FlutterMethodChannel(
        name: "app/badge",
        binaryMessenger: controller.binaryMessenger)
      badgeChannel.setMethodCallHandler { (call, result) in
        if call.method == "clear" {
          UIApplication.shared.applicationIconBadgeNumber = 0
          UNUserNotificationCenter.current().removeAllDeliveredNotifications()
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

      // Dynamic Island / Lock Screen Live Activity bridge for the
      // currently-active quest. Channel and method names mirror the Dart
      // side in `core/services/live_activity_service.dart`.
      QuestLiveActivityChannel.register(with: controller.binaryMessenger)

      // Rate-the-app + bundle-version channels used by the admin-driven
      // rate prompt and force-update overlay (see core/widgets/
      // app_prompts_listener.dart on the Dart side).
      AppPromptsChannel.register(with: controller.binaryMessenger)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
}
