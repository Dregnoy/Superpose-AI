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

    var autoEnhancePhotos: Bool {
        didSet {
            UserDefaults.standard.set(autoEnhancePhotos, forKey: "autoEnhancePhotos")
        }
    }

    var geminiAPIKey: String {
        didSet {
            UserDefaults.standard.set(geminiAPIKey, forKey: "geminiAPIKey")
        }
    }

    var selectedTab: AppTab = .camera
    var pinnedPose: PoseIdea? {
        didSet {
            if pinnedPose == nil { pinnedGhostMask = nil }
        }
    }
    var pinnedGhostMask: UIImage?
    var pinnedReferencePhoto: UIImage?
    var isOverlayMirrored: Bool = false
    var ghostOpacity: Double = 0.28
    var overlayMode: OverlayMode = .fastSilhouette
    var aspectGuideMode: AspectGuideMode = .full
    var isAutoShutterEnabled: Bool = false
    var isVoiceCoachEnabled: Bool = false
    var gridMode: GridMode = .off
    var isNightHudEnabled: Bool = false
    var isHapticsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isHapticsEnabled, forKey: "isHapticsEnabled")
        }
    }
    var voiceCoachFast: Bool {
        didSet {
            UserDefaults.standard.set(voiceCoachFast, forKey: "voiceCoachFast")
        }
    }
    var isSmileShutterEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSmileShutterEnabled, forKey: "isSmileShutterEnabled")
        }
    }
    var isSilentModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSilentModeEnabled, forKey: "isSilentModeEnabled")
        }
    }
    var pendingCameraTip: String? = nil
    var requestedZoomFactor: Double? = nil
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
        if UserDefaults.standard.object(forKey: "autoEnhancePhotos") == nil {
            self.autoEnhancePhotos = true
        } else {
            self.autoEnhancePhotos = UserDefaults.standard.bool(forKey: "autoEnhancePhotos")
        }
        if UserDefaults.standard.object(forKey: "isHapticsEnabled") == nil {
            self.isHapticsEnabled = true
        } else {
            self.isHapticsEnabled = UserDefaults.standard.bool(forKey: "isHapticsEnabled")
        }
        self.voiceCoachFast = UserDefaults.standard.bool(forKey: "voiceCoachFast")
        self.isSmileShutterEnabled = UserDefaults.standard.bool(forKey: "isSmileShutterEnabled")
        self.isSilentModeEnabled = UserDefaults.standard.bool(forKey: "isSilentModeEnabled")
        self.geminiAPIKey = UserDefaults.standard.string(forKey: "geminiAPIKey") ?? ""
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

    func reshotFromLibrary(_ item: LibraryItem) {
        pinnedPose = item.poseIdea
        if let raw = item.overlayModeRaw, let mode = OverlayMode(rawValue: raw) {
            overlayMode = mode
        } else if item.poseIdea != nil && overlayMode == .off {
            overlayMode = .fastSilhouette
        }
        requestedZoomFactor = item.zoomFactor
        selectedTab = .camera
    }

    func startGhostReference(_ image: UIImage, item: LibraryItem) {
        pinnedReferencePhoto = image
        requestedZoomFactor = item.zoomFactor
        selectedTab = .camera
    }

    func swapCouplesPose() {
        guard let current = pinnedPose, let second = current.secondarySkeleton else { return }
        pinnedPose = PoseIdea(
            id: current.id,
            title: current.title,
            angleLabel: current.angleLabel,
            confidenceTag: current.confidenceTag,
            category: current.category,
            skeleton: second,
            secondarySkeleton: current.skeleton,
            coaching: current.coaching,
            previewImageFilename: current.previewImageFilename,
            createdAt: current.createdAt
        )
    }

    func cyclePinnedPose(step: Int) {
        let pool = latestGeneratedPoses.isEmpty ? (savedCustomPoses + MockPoseCatalog.quickOfflinePoses) : latestGeneratedPoses
        guard !pool.isEmpty else { return }
        if let current = pinnedPose, let idx = pool.firstIndex(where: { $0.id == current.id }) {
            let nextIdx = (idx + step + pool.count) % pool.count
            pinnedPose = pool[nextIdx]
        } else {
            pinnedPose = pool.first
        }
    }
}
