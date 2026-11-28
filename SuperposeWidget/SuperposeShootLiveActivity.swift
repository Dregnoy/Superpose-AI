import ActivityKit
import WidgetKit
import SwiftUI

struct SuperposeShootLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SuperposeShootAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "camera.aperture")
                    .font(.title2)
                    .foregroundStyle(.cyan)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.modeTitle)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text(context.state.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let countdown = context.state.countdownSeconds {
                    Text("\(countdown)s")
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(.cyan)
                } else {
                    Text("\(context.state.shotCount) kare")
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(.green)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.88))
            .activitySystemActionForegroundColor(.cyan)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.modeTitle, systemImage: "camera.aperture")
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let countdown = context.state.countdownSeconds {
                        Text("\(countdown) sn")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.cyan)
                    } else {
                        Text("\(context.state.shotCount) kare")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let match = context.state.matchScore {
                            Text("Poz %\(match)")
                                .font(.caption.bold())
                                .foregroundStyle(match >= 85 ? .green : .cyan)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "camera.aperture")
                    .foregroundStyle(.cyan)
            } compactTrailing: {
                if let countdown = context.state.countdownSeconds {
                    Text("\(countdown)s")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.cyan)
                } else {
                    Text("\(context.state.shotCount)")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.green)
                }
            } minimal: {
                Image(systemName: "camera.aperture")
                    .foregroundStyle(.cyan)
            }
        }
    }
}
