import SwiftUI

@main
struct SuperposeAIApp: App {
    @State private var appState = AppState()
    @State private var libraryStore = LibraryStore()
    @State private var shotPackStore = ShotPackStore()

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
