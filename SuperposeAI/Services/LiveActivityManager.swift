import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<SuperposeShootAttributes>?

    private init() {}

    func startOrUpdate(
        modeTitle: String,
        detailText: String,
        shotCount: Int = 0,
        countdownSeconds: Int? = nil,
        matchScore: Int? = nil
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = SuperposeShootAttributes.ContentState(
            modeTitle: modeTitle,
            detailText: detailText,
            shotCount: shotCount,
            countdownSeconds: countdownSeconds,
            matchScore: matchScore
        )
        let content = ActivityContent(state: state, staleDate: nil)

        if let activity = currentActivity {
            Task {
                await activity.update(content)
            }
        } else {
            let attributes = SuperposeShootAttributes(sessionName: "Superpose Çekim")
            currentActivity = try? Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        }
    }

    func end() {
        guard let activity = currentActivity else { return }
        currentActivity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
