import WidgetKit
import SwiftUI
import AppIntents

@main
struct SuperposeWidgetBundle: WidgetBundle {
    var body: some Widget {
        SuperposeCameraControl()
    }
}

struct SuperposeCameraControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.superposelabs.superpose.cameraControl") {
            ControlWidgetButton(action: OpenSuperposeControlIntent()) {
                Label("Superpose", systemImage: "camera.aperture")
            }
        }
        .displayName("Superpose Kamera")
        .description("Kilit ekranından veya Denetim Merkezi'nden tek dokunuşla kamerayı açar.")
    }
}

struct OpenSuperposeControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Superpose Kamerayı Aç"
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
