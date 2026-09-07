import ActivityKit
import Foundation

// Shared data model between the host app and the Widget Extension.
// `Attributes` is fixed for the lifetime of the activity (set on start);
// `ContentState` is what we update — most often just the deadline.
@available(iOS 16.1, *)
public struct QuestActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    // Deadline of the active quest. Driving the Dynamic Island countdown
    // off `Date` (with `Text(timerInterval:)`) means iOS ticks the widget
    // every second without needing the app awake or a push.
    public var expiresAt: Date
    // Optional status badge — "submitted" / "active" / "expired". Lets us
    // show "AWAITING REVIEW" without ending + restarting the activity.
    public var status: String

    public init(expiresAt: Date, status: String) {
      self.expiresAt = expiresAt
      self.status = status
    }
  }

  // Static fields. Set once when the activity starts; never change.
  public var questId: String
  public var questTitle: String
  public var xpReward: Int

  public init(questId: String, questTitle: String, xpReward: Int) {
    self.questId = questId
    self.questTitle = questTitle
    self.xpReward = xpReward
  }
}
