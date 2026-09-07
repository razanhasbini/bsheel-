import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Color tokens
// Match the Flutter app's Arcade Pop palette so the Live Activity feels
// like a piece of the app, not a system widget. Kept in one place so we
// can tweak without grepping across SwiftUI views.
@available(iOS 16.1, *)
fileprivate enum BsColors {
  static let cream      = Color(red: 1.0,    green: 0.976, blue: 0.933) // #FFF9EE
  static let ink        = Color(red: 0.102,  green: 0.075, blue: 0.188) // #1A1330
  static let violet     = Color(red: 0.420,  green: 0.231, blue: 1.0)   // #6B3BFF
  static let coral      = Color(red: 1.0,    green: 0.353, blue: 0.431) // #FF5A6E
  static let gold       = Color(red: 1.0,    green: 0.761, blue: 0.141) // #FFC224
  static let green      = Color(red: 0.090,  green: 0.761, blue: 0.482) // #17C27B
}

// MARK: - Helpers

@available(iOS 16.1, *)
fileprivate func urgencyColor(expiresAt: Date) -> Color {
  let remaining = expiresAt.timeIntervalSinceNow
  if remaining <= 0 { return BsColors.coral }
  if remaining < 30 * 60 { return BsColors.coral }
  if remaining < 60 * 60 { return BsColors.gold }
  return BsColors.violet
}

@available(iOS 16.1, *)
fileprivate struct Countdown: View {
  let expiresAt: Date
  let status: String
  let font: Font

  var body: some View {
    let isExpired = expiresAt.timeIntervalSinceNow <= 0
    let isSubmitted = status.lowercased() == "submitted"

    if isSubmitted {
      Text("REVIEW")
        .font(font)
        .fontWeight(.heavy)
        .foregroundColor(BsColors.gold)
    } else if isExpired {
      Text("ENDED")
        .font(font)
        .fontWeight(.heavy)
        .foregroundColor(BsColors.coral)
    } else {
      // Apple's built-in live countdown — iOS re-renders the timer every
      // second from the Date alone, no push or background fetch needed.
      Text(timerInterval: Date()...expiresAt,
           countsDown: true,
           showsHours: true)
        .font(font)
        .fontWeight(.heavy)
        .monospacedDigit()
        .foregroundColor(urgencyColor(expiresAt: expiresAt))
        .multilineTextAlignment(.trailing)
    }
  }
}

// MARK: - Lock Screen view

@available(iOS 16.1, *)
struct QuestLockScreenView: View {
  let context: ActivityViewContext<QuestActivityAttributes>

  var body: some View {
    HStack(spacing: 14) {
      // Actual Bsheel app-icon mark, rounded-rect clipped + ink-outlined
      // so it visually belongs to the Lock Screen card rather than
      // floating like a sticker.
      Image("BsheelMark")
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fill)
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(BsColors.ink, lineWidth: 2)
        )

      VStack(alignment: .leading, spacing: 4) {
        Text("ACTIVE QUEST")
          .font(.system(size: 10, weight: .heavy))
          .tracking(1.3)
          .foregroundColor(BsColors.ink.opacity(0.55))
        Text(context.attributes.questTitle)
          .font(.system(size: 15, weight: .heavy))
          .foregroundColor(BsColors.ink)
          .lineLimit(2)
        HStack(spacing: 6) {
          Image(systemName: "bolt.fill")
            .font(.system(size: 9, weight: .heavy))
            .foregroundColor(BsColors.violet)
          Text("+\(context.attributes.xpReward) XP")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(BsColors.ink.opacity(0.7))
        }
      }

      Spacer(minLength: 8)

      Countdown(
        expiresAt: context.state.expiresAt,
        status: context.state.status,
        font: .system(size: 22)
      )
      .frame(minWidth: 78)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(BsColors.cream)
  }
}

// MARK: - Activity Widget

@available(iOS 16.1, *)
struct QuestLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: QuestActivityAttributes.self) { context in
      QuestLockScreenView(context: context)

    } dynamicIsland: { context in
      DynamicIsland {
        // Expanded — long-press the Dynamic Island, or system shows when
        // there's space (e.g. AOD on supported devices).
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 8) {
            Image("BsheelMark")
              .resizable()
              .interpolation(.high)
              .aspectRatio(contentMode: .fill)
              .frame(width: 30, height: 30)
              .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text("BSHEEL")
              .font(.system(size: 13, weight: .heavy))
              .tracking(1.1)
              .foregroundColor(.white)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          Countdown(
            expiresAt: context.state.expiresAt,
            status: context.state.status,
            font: .system(size: 17)
          )
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 4) {
            Text(context.attributes.questTitle)
              .font(.system(size: 14, weight: .heavy))
              .foregroundColor(.white)
              .lineLimit(2)
            HStack(spacing: 6) {
              Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(BsColors.gold)
              Text("+\(context.attributes.xpReward) XP")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
            }
          }
        }

      } compactLeading: {
        // Tiny app-icon mark. At 20pt the BSHEEL wordmark inside the
        // icon will read as a vague shape — that's fine, the brand cue
        // is the rounded square + cream/violet palette, not the letters.
        Image("BsheelMark")
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fill)
          .frame(width: 20, height: 20)
          .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

      } compactTrailing: {
        // Live ticking countdown, color shifts to gold/coral as time runs out.
        Countdown(
          expiresAt: context.state.expiresAt,
          status: context.state.status,
          font: .system(size: 13)
        )
        .frame(minWidth: 56)

      } minimal: {
        // App icon, masked to a circle so the urgency colour can ring it
        // and still read as "Bsheel" even when sharing the island.
        Image("BsheelMark")
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fill)
          .clipShape(Circle())
          .overlay(
            Circle().stroke(urgencyColor(expiresAt: context.state.expiresAt), lineWidth: 1.5)
          )
      }
      .keylineTint(BsColors.violet)
    }
  }
}

// MARK: - Widget bundle entry point

@available(iOS 16.1, *)
@main
struct QuestLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    QuestLiveActivity()
  }
}
