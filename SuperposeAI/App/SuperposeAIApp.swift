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
        }
    }
}
