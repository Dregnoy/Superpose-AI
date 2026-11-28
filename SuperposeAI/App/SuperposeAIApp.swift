import SwiftUI

@main
struct SuperposeAIApp: App {
    @State private var appState = AppState()
    @State private var libraryStore = LibraryStore()
    @State private var shotPackStore = ShotPackStore()

    init() {
        if ProcessInfo.processInfo.arguments.contains("-UITestingSkipOnboarding") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        } else if ProcessInfo.processInfo.arguments.contains("-UITestingResetOnboarding") {
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(libraryStore)
                .environment(shotPackStore)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    guard url.scheme == "superpose", url.host == "import-pose" else { return }
                    Task { await importSharedPoseFromExtension() }
                }
                .task {
                    await importSharedPoseFromExtension()
                }
        }
    }

    @MainActor
    private func importSharedPoseFromExtension() async {
        guard let image = SharedPoseImportStore.consumeSharedImage() else { return }
        let vision = PoseVisionService()
        async let extractedTask = vision.extractPose(from: image)
        async let silhouetteTask = vision.extractPersonSilhouette(from: image)
        let (extractedPose, ghostMask) = await (extractedTask, silhouetteTask)

        appState.hasCompletedOnboarding = true
        appState.pinnedReferencePhoto = image
        appState.pinnedGhostMask = ghostMask
        appState.pinnedPose = extractedPose ?? MockPoseCatalog.quickOfflinePoses.first
        appState.overlayMode = (ghostMask != nil) ? .ghost : .fastSilhouette
        appState.selectedTab = .camera
        appState.pendingCameraTip = "Paylaşılan fotoğraftan poz sabitlendi"
    }
}
