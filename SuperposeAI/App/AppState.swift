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

    var autoSaveToApplePhotos: Bool {
        didSet {
            UserDefaults.standard.set(autoSaveToApplePhotos, forKey: "autoSaveToApplePhotos")
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
    var savedCustomPoses: [PoseIdea] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(savedCustomPoses) {
                UserDefaults.standard.set(data, forKey: "savedCustomPoses")
            }
        }
    }
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
        self.autoSaveToApplePhotos = UserDefaults.standard.bool(forKey: "autoSaveToApplePhotos")
        if let data = UserDefaults.standard.data(forKey: "savedCustomPoses"),
           let decoded = try? JSONDecoder().decode([PoseIdea].self, from: data) {
            self.savedCustomPoses = decoded
        }
    }

    func isPoseSaved(_ pose: PoseIdea) -> Bool {
        savedCustomPoses.contains { $0.id == pose.id }
    }

    func toggleSavePose(_ pose: PoseIdea) {
        if let idx = savedCustomPoses.firstIndex(where: { $0.id == pose.id }) {
            savedCustomPoses.remove(at: idx)
        } else {
            savedCustomPoses.insert(pose, at: 0)
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
