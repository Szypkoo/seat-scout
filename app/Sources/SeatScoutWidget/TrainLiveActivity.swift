import ActivityKit
import SeatScoutShared
import SwiftUI
import WidgetKit

@main
struct SeatScoutWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrainLiveActivity()
    }
}

struct TrainLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.trainLabel).font(.caption.weight(.bold))
                        Text(context.state.nextStop).font(.subheadline.weight(.semibold)).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        DelayBadge(minutes: context.state.delayMinutes)
                        if let d = context.state.nextDate, context.state.phase != "finished" {
                            Text(d, style: .timer).font(.subheadline.monospacedDigit().weight(.semibold)).multilineTextAlignment(.trailing)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.headline).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: context.state.progress).tint(.blue)
                        if let c = context.state.changeText {
                            Label(c, systemImage: "arrow.left.arrow.right").font(.caption).lineLimit(2)
                        } else if let s = context.state.seatText {
                            Label(s, systemImage: "chair.lounge.fill").font(.caption)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "tram.fill")
            } compactTrailing: {
                if let d = context.state.nextDate, context.state.phase != "finished" {
                    Text(d, style: .timer)
                        .font(.caption2.monospacedDigit())
                        .frame(maxWidth: 46)
                        .multilineTextAlignment(.trailing)
                } else {
                    Image(systemName: "checkmark")
                }
            } minimal: {
                Image(systemName: "tram.fill")
            }
        }
    }
}

private struct DelayBadge: View {
    let minutes: Int?

    var body: some View {
        if let m = minutes {
            Text(m > 0 ? "+\(m) min" : (m == 0 ? "o czasie" : "\(m) min"))
                .font(.caption.weight(.bold))
                .foregroundStyle(m > 0 ? Color.orange : Color.green)
        }
    }
}

private struct LockScreenView: View {
    let attributes: TrainActivityAttributes
    let state: TrainActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(attributes.trainLabel, systemImage: "tram.fill").font(.subheadline.weight(.bold))
                Spacer()
                DelayBadge(minutes: state.delayMinutes)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(state.headline).font(.headline).lineLimit(1)
                Spacer()
                if let d = state.nextDate, state.phase != "finished" {
                    Text(d, style: .timer).font(.headline.monospacedDigit())
                }
            }
            ProgressView(value: state.progress).tint(.blue)
            if let c = state.changeText {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                    Text(c).font(.footnote)
                    if let cd = state.changeDate {
                        Spacer()
                        Text(cd, style: .relative).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            if let s = state.seatText {
                Label(s, systemImage: "chair.lounge.fill").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
