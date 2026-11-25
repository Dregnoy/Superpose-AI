import Foundation

/// Converts floating-point touch/gyro deltas into integer HID pointer & scroll steps
/// while retaining sub-pixel remainders across frames.
struct MouseMotionProcessor: Sendable {
    private(set) var remainderX: Double = 0
    private(set) var remainderY: Double = 0
    private(set) var remainderScrollX: Double = 0
    private(set) var remainderScrollY: Double = 0

    mutating func reset() {
        remainderX = 0
        remainderY = 0
        remainderScrollX = 0
        remainderScrollY = 0
    }

    mutating func processMove(
        rawDX: Double,
        rawDY: Double,
        sensitivity: Double,
        acceleration: Bool
    ) -> (dx: Int, dy: Int) {
        let speed = hypot(rawDX, rawDY)
        let accelGain: Double
        if acceleration {
            // Smooth curve: fine precision at slow speeds, agile reach on quick flicks.
            accelGain = 0.85 + min(1.85, pow(speed * 0.14, 0.72))
        } else {
            accelGain = 1.0
        }

        let totalX = remainderX + rawDX * sensitivity * accelGain
        let totalY = remainderY + rawDY * sensitivity * accelGain

        let stepX = Int(totalX.rounded(.towardZero))
        let stepY = Int(totalY.rounded(.towardZero))

        remainderX = totalX - Double(stepX)
        remainderY = totalY - Double(stepY)

        return (stepX, stepY)
    }

    mutating func processScroll(
        rawDX: Double,
        rawDY: Double,
        sensitivity: Double,
        naturalScrolling: Bool
    ) -> (wheel: Int, hWheel: Int) {
        let sign = naturalScrolling ? 1.0 : -1.0
        // Trackpad drag points are roughly 14-18 pt per scroll notch.
        let scale = 0.085 * sensitivity * sign

        let totalV = remainderScrollY + rawDY * scale
        let totalH = remainderScrollX - rawDX * scale

        let stepV = Int(totalV.rounded(.towardZero))
        let stepH = Int(totalH.rounded(.towardZero))

        remainderScrollY = totalV - Double(stepV)
        remainderScrollX = totalH - Double(stepH)

        return (stepV, stepH)
    }
}

/// Coalesces high-frequency relative mouse motion when the BLE notification buffer is busy,
/// preventing cursor lag while keeping button states authoritative.
struct PendingMouseAccumulator: Sendable {
    private(set) var buttons: HIDMouseButton = []
    private(set) var dx: Int = 0
    private(set) var dy: Int = 0
    private(set) var wheel: Int = 0
    private(set) var hWheel: Int = 0
    private(set) var hasPendingMotion: Bool = false

    mutating func accumulate(
        buttons: HIDMouseButton,
        dx: Int,
        dy: Int,
        wheel: Int = 0,
        hWheel: Int = 0
    ) {
        self.buttons = buttons
        self.dx += dx
        self.dy += dy
        self.wheel += wheel
        self.hWheel += hWheel
        if dx != 0 || dy != 0 || wheel != 0 || hWheel != 0 {
            hasPendingMotion = true
        }
    }

    mutating func clear() {
        dx = 0
        dy = 0
        wheel = 0
        hWheel = 0
        hasPendingMotion = false
    }

    mutating func popNextPacket(protocolMode: HIDProtocolMode) -> Data? {
        guard hasPendingMotion else { return nil }

        let stepX = HIDReportBuilder.clampToHIDSignedByte(dx)
        let stepY = HIDReportBuilder.clampToHIDSignedByte(dy)
        let stepW = HIDReportBuilder.clampToHIDSignedByte(wheel)
        let stepH = HIDReportBuilder.clampToHIDSignedByte(hWheel)

        dx -= Int(stepX)
        dy -= Int(stepY)
        wheel -= Int(stepW)
        hWheel -= Int(stepH)

        if dx == 0 && dy == 0 && wheel == 0 && hWheel == 0 {
            hasPendingMotion = false
        }

        switch protocolMode {
        case .boot:
            return HIDReportBuilder.bootMouseReport(buttons: buttons, dx: stepX, dy: stepY)
        case .report:
            return HIDReportBuilder.mouseReport(
                buttons: buttons,
                dx: stepX,
                dy: stepY,
                wheel: stepW,
                hWheel: stepH
            )
        }
    }
}
