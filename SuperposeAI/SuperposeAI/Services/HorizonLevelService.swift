import CoreMotion
import Foundation

@MainActor
@Observable
final class HorizonLevelService {
    var rollDegrees: Double = 0.0
    var isLevel: Bool { abs(rollDegrees) <= 1.5 }

    /// For flat-lay / overhead shots (e.g. cafe table): tracks X/Y tilt when phone faces down/up.
    var flatLayOffsetX: Double = 0.0
    var flatLayOffsetY: Double = 0.0
    var isFlatLayOrientation: Bool = false
    var isFlatLayAligned: Bool {
        isFlatLayOrientation && hypot(flatLayOffsetX, flatLayOffsetY) < 0.06
    }

    @ObservationIgnored private let motionManager = CMMotionManager()

    func start() {
        guard motionManager.isAccelerometerAvailable, !motionManager.isAccelerometerActive else { return }
        motionManager.accelerometerUpdateInterval = 0.08
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let accel = data?.acceleration else { return }
            let angle = atan2(accel.x, -accel.y) * (180.0 / .pi)
            let isFlat = abs(accel.z) > 0.78
            let ox = accel.x
            let oy = accel.y
            Task { @MainActor in
                self.rollDegrees = angle
                self.isFlatLayOrientation = isFlat
                self.flatLayOffsetX = ox
                self.flatLayOffsetY = oy
            }
        }
    }

    func stop() {
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }
    }
}
