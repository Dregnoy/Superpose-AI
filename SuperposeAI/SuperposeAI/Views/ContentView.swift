import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var bindableState = appState

        Group {
            if !appState.hasCompletedOnboarding {
                OnboardingView()
            } else {
                TabView(selection: $bindableState.selectedTab) {
                    CameraView()
                        .tabItem {
                            Label("Camera", systemImage: "camera.aperture")
                        }
                        .tag(AppState.AppTab.camera)

                    LibraryView()
                        .tabItem {
                            Label("Library", systemImage: "photo.stack")
                        }
                        .tag(AppState.AppTab.library)

                    ShotPacksView()
                        .tabItem {
                            Label("Shot Packs", systemImage: "sparkles")
                        }
                        .tag(AppState.AppTab.shotPacks)
                }
                .tint(.white)
            }
        }
        .sheet(isPresented: $bindableState.isResultsSheetPresented) {
            PoseResultsSheet(poses: appState.latestGeneratedPoses)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $bindableState.coachingPose) { pose in
            CoachingSheet(pose: pose)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .superposeStartAutoShoot)) { _ in
            appState.hasCompletedOnboarding = true
            appState.selectedTab = .camera
            appState.isAutoShutterEnabled = true
        }
    }
}
