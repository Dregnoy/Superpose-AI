import SwiftUI

@MainActor
@Observable
final class AppState {
    var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }

    var preferredUseCase: PoseUseCase {
        didSet {
            UserDefaults.standard.set(preferredUseCase.rawValue, forKey: "preferredUseCase")
        }
    }

    var selectedTab: AppTab = .camera
    var pinnedPose: PoseIdea? {
        didSet {
            if pinnedPose == nil { pinnedGhostMask = nil }
        }
    }
    var pinnedGhostMask: UIImage?
    var overlayMode: OverlayMode = .fastSilhouette
    var isAutoShutterEnabled: Bool = false
    var isVoiceCoachEnabled: Bool = false
    var isGridEnabled: Bool = false
    var latestGeneratedPoses: [PoseIdea] = []
    var isResultsSheetPresented: Bool = false
    var coachingPose: PoseIdea?

    enum AppTab: Hashable {
        case camera
        case library
        case shotPacks
    }

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if let saved = UserDefaults.standard.string(forKey: "preferredUseCase"),
           let parsed = PoseUseCase(rawValue: saved) {
            self.preferredUseCase = parsed
        } else {
            self.preferredUseCase = .travel
        }
    }

    func pinPoseAndSwitchToCamera(_ pose: PoseIdea) {
        pinnedPose = pose
        if overlayMode == .off {
            overlayMode = .fastSilhouette
        }
        isResultsSheetPresented = false
        selectedTab = .camera
    }
}
