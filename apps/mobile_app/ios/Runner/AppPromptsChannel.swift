import Flutter
import StoreKit
import UIKit

/// Two tiny method channels used by the rate-app + force-update flows:
///
///   `app/rate`  → requestReview (SKStoreReviewController.requestReview)
///   `app/info`  → getBuildNumber / getMarketingVersion (Info.plist read)
///
/// Hand-rolled instead of pulling in `in_app_review` / `package_info_plus`
/// to keep the dependency surface tight (no supply-chain risk).
enum AppPromptsChannel {

  static func register(with messenger: FlutterBinaryMessenger) {
    let rate = FlutterMethodChannel(name: "app/rate", binaryMessenger: messenger)
    rate.setMethodCallHandler(handleRate)

    let info = FlutterMethodChannel(name: "app/info", binaryMessenger: messenger)
    info.setMethodCallHandler(handleInfo)
  }

  private static func handleRate(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "requestReview":
      DispatchQueue.main.async {
        if #available(iOS 14.0, *) {
          // iOS 14+: scoped to the foreground window scene. Prefer this
          // over the deprecated `requestReview()` static so iPad
          // multi-window apps prompt in the right place.
          guard
            let scene = UIApplication.shared.connectedScenes
              .first(where: { $0.activationState == .foregroundActive })
              as? UIWindowScene
          else {
            result("no_scene")
            return
          }
          SKStoreReviewController.requestReview(in: scene)
          result(true)
        } else {
          SKStoreReviewController.requestReview()
          result(true)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func handleInfo(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    let info = Bundle.main.infoDictionary ?? [:]
    switch call.method {
    case "getBuildNumber":
      // CFBundleVersion is the integer build number Xcode injects; we
      // return it as Int so the Dart side gets a typed primitive.
      let raw = info["CFBundleVersion"] as? String ?? ""
      result(Int(raw))
    case "getMarketingVersion":
      result(info["CFBundleShortVersionString"] as? String ?? "")
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
