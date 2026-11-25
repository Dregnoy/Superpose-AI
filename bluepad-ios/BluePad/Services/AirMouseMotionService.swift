import CoreMotion
import Foundation

/// Gyroscope-based Air Mouse motion provider using CoreMotion (`CMMotionManager`).
@MainActor
final class AirMouseMotionService {
    private let motionManager = CMMotionManager()
    private(set) var isRunning: Bool = false

    private var filteredX: Double = 0
    private var filteredY: Double = 0
    private let deadzone: Double = 0.045
    private let smoothingAlpha: Double = 0.45

    var isAvailable: Bool {
        motionManager.isDeviceMotionAvailable
    }

    func start(
        sensitivityProvider: @escaping @MainActor () -> Double,
        onDelta: @escaping @MainActor (Double, Double) -> Void
    ) {
        guard isAvailable else { return }
        guard !isRunning else { return }

        filteredX = 0
        filteredY = 0
        isRunning = true

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, self.isRunning, let motion else { return }
            let rate = motion.rotationRate
            // Holding phone upright: yaw around Z rotates horizontally, pitch around X tilts vertically.
            let rawX = abs(rate.z) > self.deadzone ? -rate.z : 0
            let rawY = abs(rate.x) > self.deadzone ? -rate.x : 0

            self.filteredX = self.smoothingAlpha * rawX + (1.0 - self.smoothingAlpha) * self.filteredX
            self.filteredY = self.smoothingAlpha * rawY + (1.0 - self.smoothingAlpha) * self.filteredY

            let gain = 11.5 * sensitivityProvider()
            let dx = self.filteredX * gain
            let dy = self.filteredY * gain

            if abs(dx) > 0.05 || abs(dy) > 0.05 {
                onDelta(dx, dy)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        motionManager.stopDeviceMotionUpdates()
        filteredX = 0
        filteredY = 0
    }
}
