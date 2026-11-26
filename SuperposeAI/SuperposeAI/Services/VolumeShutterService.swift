import AVFoundation
import MediaPlayer
import SwiftUI

/// Listens for hardware Volume Up / Volume Down presses (including Bluetooth selfie sticks)
/// while suppressing the system volume HUD and restoring volume so shots never hit 0% or 100%.
@MainActor
@Observable
final class VolumeShutterService {
    var onVolumePressed: (() -> Void)?

    @ObservationIgnored private var volumeObservation: NSKeyValueObservation?
    @ObservationIgnored private var initialVolume: Float = 0.5
    @ObservationIgnored private var isResettingVolume = false
    @ObservationIgnored private var lastTriggerTime: CFAbsoluteTime = 0
    @ObservationIgnored weak var hiddenVolumeView: MPVolumeView?

    func start() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Best effort
        }

        initialVolume = session.outputVolume
        // Avoid sitting at exact 0.0 or 1.0 where hardware button might not emit a change
        if initialVolume < 0.1 || initialVolume > 0.9 {
            initialVolume = 0.5
            setSystemVolume(0.5)
        }

        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let newValue = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.handleVolumeChange(newValue)
            }
        }
    }

    func stop() {
        volumeObservation?.invalidate()
        volumeObservation = nil
    }

    private func handleVolumeChange(_ newValue: Float) {
        guard !isResettingVolume else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastTriggerTime >= 0.45 else { return }
        lastTriggerTime = now

        onVolumePressed?()

        // Restore initial volume so user can press Volume Up/Down repeatedly
        isResettingVolume = true
        setSystemVolume(initialVolume)
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            self.isResettingVolume = false
        }
    }

    private func setSystemVolume(_ value: Float) {
        guard let slider = hiddenVolumeView?.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.value = value
    }
}

/// Invisible MPVolumeView that suppresses the system volume overlay when using a selfie stick.
struct HiddenVolumeViewRepresentable: UIViewRepresentable {
    let service: VolumeShutterService

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
        view.alpha = 0.001
        service.hiddenVolumeView = view
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        service.hiddenVolumeView = uiView
    }
}
