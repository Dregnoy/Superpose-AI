import CoreMotion
import Foundation

@MainActor
@Observable
final class HorizonLevelService {
    var rollDegrees: Double = 0.0
    var isLevel: Bool { abs(rollDegrees) <= 1.5 }

    private let motionManager = CMMotionManager()

    func start() {
        guard motionManager.isAccelerometerAvailable, !motionManager.isAccelerometerActive else { return }
        motionManager.accelerometerUpdateInterval = 0.08
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let accel = data?.acceleration else { return }
            let angle = atan2(accel.x, -accel.y) * (180.0 / .pi)
            Task { @MainActor in
                self.rollDegrees = angle
            }
        }
    }

    func stop() {
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }
    }
}
