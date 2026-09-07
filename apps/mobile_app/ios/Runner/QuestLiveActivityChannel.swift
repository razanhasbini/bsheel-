import Flutter
import ActivityKit
import Foundation

/// Bridge between the Flutter side and `ActivityKit`. Lives only on iOS
/// 16.1+; older devices receive `available_no` from every method so the
/// Dart side can no-op without crashing.
///
/// The Widget Extension target consumes `QuestActivityAttributes` from
/// shared source, so this file must be added to *both* the Runner target
/// and the QuestLiveActivity target (or `QuestActivityAttributes.swift`
/// must be a member of both). We rely on Xcode's "Target Membership"
/// checkbox for that — see the setup README.
enum QuestLiveActivityChannel {

  // Persist the latest activity id keyed by quest id so a backgrounded
  // app, or one killed by the OS, can resolve "end this activity" calls
  // without keeping the Activity<...> handle in memory.
  private static let storageKey = "quest_live_activity_ids_v1"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "app/live_activity",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler(handle)
  }

  // MARK: - Method dispatch

  private static func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    if #available(iOS 16.2, *) {
      switch call.method {
      case "isSupported":
        result(ActivityAuthorizationInfo().areActivitiesEnabled)
      case "start":
        start(call.arguments, result: result)
      case "update":
        update(call.arguments, result: result)
      case "end":
        end(call.arguments, result: result)
      case "endAll":
        endAll(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    } else {
      // Live Activities require 16.1+. Return a sentinel so Dart knows
      // the call was acknowledged but is a no-op on this device.
      result("available_no")
    }
  }

  // MARK: - Operations

  @available(iOS 16.2, *)
  private static func start(
    _ rawArgs: Any?,
    result: @escaping FlutterResult
  ) {
    guard let args = rawArgs as? [String: Any],
          let questId = args["questId"] as? String,
          let questTitle = args["questTitle"] as? String,
          let xpReward = args["xpReward"] as? Int,
          let expiresAtMs = args["expiresAtEpochMs"] as? NSNumber else {
      result(FlutterError(
        code: "bad_args",
        message: "start requires questId/questTitle/xpReward/expiresAtEpochMs",
        details: nil
      ))
      return
    }

    let status = (args["status"] as? String) ?? "active"
    let expiresAt = Date(timeIntervalSince1970: expiresAtMs.doubleValue / 1000.0)

    // System-level toggle (Settings → Bsheel → Live Activities). If the
    // user disabled it, do nothing rather than throw — Dart should treat
    // this the same as an old iOS device.
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      result("disabled")
      return
    }

    // De-dupe: if there's already a running activity for this questId,
    // update it in place rather than spinning up a duplicate (which would
    // leave two competing widgets in the Dynamic Island).
    if let existingId = activityId(forQuest: questId),
       let existing = Activity<QuestActivityAttributes>.activities
        .first(where: { $0.id == existingId }) {
      Task {
        await existing.update(
          ActivityContent(
            state: QuestActivityAttributes.ContentState(
              expiresAt: expiresAt,
              status: status
            ),
            staleDate: expiresAt.addingTimeInterval(60 * 60)
          )
        )
        result(existing.id)
      }
      return
    }

    let attributes = QuestActivityAttributes(
      questId: questId,
      questTitle: questTitle,
      xpReward: xpReward
    )
    let state = QuestActivityAttributes.ContentState(
      expiresAt: expiresAt,
      status: status
    )

    do {
      let activity = try Activity.request(
        attributes: attributes,
        content: ActivityContent(
          state: state,
          // Keep the activity alive for an hour past the expiry so users
          // can see "ENDED" / "REVIEW" rather than having it vanish.
          staleDate: expiresAt.addingTimeInterval(60 * 60)
        ),
        pushType: nil
      )
      setActivityId(activity.id, forQuest: questId)
      result(activity.id)
    } catch {
      result(FlutterError(
        code: "start_failed",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  @available(iOS 16.2, *)
  private static func update(
    _ rawArgs: Any?,
    result: @escaping FlutterResult
  ) {
    guard let args = rawArgs as? [String: Any],
          let questId = args["questId"] as? String,
          let expiresAtMs = args["expiresAtEpochMs"] as? NSNumber else {
      result(FlutterError(
        code: "bad_args",
        message: "update requires questId/expiresAtEpochMs",
        details: nil
      ))
      return
    }
    let status = (args["status"] as? String) ?? "active"
    let expiresAt = Date(timeIntervalSince1970: expiresAtMs.doubleValue / 1000.0)

    guard let activityId = activityId(forQuest: questId),
          let activity = Activity<QuestActivityAttributes>.activities
            .first(where: { $0.id == activityId }) else {
      result("missing")
      return
    }

    Task {
      await activity.update(
        ActivityContent(
          state: QuestActivityAttributes.ContentState(
            expiresAt: expiresAt,
            status: status
          ),
          staleDate: expiresAt.addingTimeInterval(60 * 60)
        )
      )
      result(activity.id)
    }
  }

  @available(iOS 16.2, *)
  private static func end(
    _ rawArgs: Any?,
    result: @escaping FlutterResult
  ) {
    guard let args = rawArgs as? [String: Any],
          let questId = args["questId"] as? String else {
      result(FlutterError(
        code: "bad_args",
        message: "end requires questId",
        details: nil
      ))
      return
    }

    guard let activityId = activityId(forQuest: questId) else {
      result("missing")
      return
    }

    // Look up the live handle. If the OS already tore the activity down
    // (e.g. > 8h since start), there's nothing to end — just clear our
    // bookkeeping.
    let activity = Activity<QuestActivityAttributes>.activities
      .first(where: { $0.id == activityId })

    clearActivityId(forQuest: questId)

    guard let activity else {
      result("already_ended")
      return
    }

    Task {
      await activity.end(
        ActivityContent(
          state: activity.content.state,
          staleDate: nil
        ),
        dismissalPolicy: .immediate
      )
      result(activityId)
    }
  }

  @available(iOS 16.2, *)
  private static func endAll(result: @escaping FlutterResult) {
    let activities = Activity<QuestActivityAttributes>.activities
    UserDefaults.standard.removeObject(forKey: storageKey)
    Task {
      for activity in activities {
        await activity.end(
          ActivityContent(state: activity.content.state, staleDate: nil),
          dismissalPolicy: .immediate
        )
      }
      result(activities.count)
    }
  }

  // MARK: - id ↔ questId bookkeeping

  @available(iOS 16.2, *)
  private static func activityId(forQuest questId: String) -> String? {
    let map = UserDefaults.standard
      .dictionary(forKey: storageKey) as? [String: String] ?? [:]
    return map[questId]
  }

  @available(iOS 16.2, *)
  private static func setActivityId(_ activityId: String, forQuest questId: String) {
    var map = UserDefaults.standard
      .dictionary(forKey: storageKey) as? [String: String] ?? [:]
    map[questId] = activityId
    UserDefaults.standard.set(map, forKey: storageKey)
  }

  @available(iOS 16.2, *)
  private static func clearActivityId(forQuest questId: String) {
    var map = UserDefaults.standard
      .dictionary(forKey: storageKey) as? [String: String] ?? [:]
    map.removeValue(forKey: questId)
    UserDefaults.standard.set(map, forKey: storageKey)
  }
}
