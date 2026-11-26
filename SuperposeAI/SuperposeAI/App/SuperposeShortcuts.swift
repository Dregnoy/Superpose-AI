import AppIntents
import Foundation

extension Notification.Name {
    static let superposeStartAutoShoot = Notification.Name("superposeStartAutoShoot")
}

struct StartSuperposeShootIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Superpose Shoot"
    static let description = IntentDescription("Opens Superpose directly on the Camera tab with Auto-Shutter enabled.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .superposeStartAutoShoot, object: nil)
        return .result()
    }
}

struct SuperposeShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSuperposeShootIntent(),
            phrases: [
                "Start \(.applicationName) shoot",
                "Open \(.applicationName) camera"
            ],
            shortTitle: "Start Shoot",
            systemImageName: "camera.aperture"
        )
    }
}
