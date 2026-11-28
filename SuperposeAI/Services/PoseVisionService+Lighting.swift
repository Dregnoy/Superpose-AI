import CoreVideo
import Foundation

extension PoseVisionService {
    struct LightingMetrics {
        let average: Double
        let leftAverage: Double
        let rightAverage: Double
        let edgeAverage: Double
    }

    nonisolated static func estimateLightingMetrics(from pixelBuffer: CVPixelBuffer) -> LightingMetrics {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return LightingMetrics(average: 0.5, leftAverage: 0.5, rightAverage: 0.5, edgeAverage: 0.5)
        }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var total = 0, count = 0
        var leftTotal = 0, leftCount = 0
        var rightTotal = 0, rightCount = 0
        var edgeTotal = 0, edgeCount = 0
        let step = 16
        let midX = width / 2

        for y in stride(from: 0, to: height, by: step) {
            let row = buffer + y * bytesPerRow
            for x in stride(from: 0, to: width, by: step) {
                let val = Int(row[x])
                total += val
                count += 1
                if x < midX {
                    leftTotal += val
                    leftCount += 1
                } else {
                    rightTotal += val
                    rightCount += 1
                }
                if x < width / 6 || x > (width * 5) / 6 {
                    edgeTotal += val
                    edgeCount += 1
                }
            }
        }

        let avg = count > 0 ? Double(total) / Double(count * 255) : 0.5
        let lAvg = leftCount > 0 ? Double(leftTotal) / Double(leftCount * 255) : avg
        let rAvg = rightCount > 0 ? Double(rightTotal) / Double(rightCount * 255) : avg
        let eAvg = edgeCount > 0 ? Double(edgeTotal) / Double(edgeCount * 255) : avg
        return LightingMetrics(average: avg, leftAverage: lAvg, rightAverage: rAvg, edgeAverage: eAvg)
    }

    nonisolated static func classifyLighting(from metrics: LightingMetrics) -> LightingStatus {
        if metrics.average < 0.20 && metrics.edgeAverage < 0.20 { return .lowContrast }
        if metrics.average < 0.22 { return .tooDark }
        if metrics.average > 0.86 { return .backlitOrHarsh }
        if metrics.leftAverage - metrics.rightAverage > 0.20 { return .turnLeftForLight }
        if metrics.rightAverage - metrics.leftAverage > 0.20 { return .turnRightForLight }
        return .good
    }

    nonisolated static func detectVerticalLineBehindHead(in pixelBuffer: CVPixelBuffer, nose: NormalizedPoint?) -> Bool {
        guard let nose, nose.y > 0.12 else { return false }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return false }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        let centerX = Int(nose.x * Double(width))
        let yStart = max(0, Int((nose.y - 0.14) * Double(height)))
        let yEnd = max(yStart + 2, Int((nose.y - 0.04) * Double(height)))
        let offset = max(6, Int(0.035 * Double(width)))

        let xLeft = max(0, centerX - offset)
        let xMid = max(0, min(width - 1, centerX))
        let xRight = min(width - 1, centerX + offset)

        var sumL = 0, sumM = 0, sumR = 0, rows = 0
        for y in stride(from: yStart, to: min(height, yEnd), by: 4) {
            let row = buffer + y * bytesPerRow
            sumL += Int(row[xLeft])
            sumM += Int(row[xMid])
            sumR += Int(row[xRight])
            rows += 1
        }
        guard rows > 2 else { return false }

        let avgL = Double(sumL) / Double(rows * 255)
        let avgM = Double(sumM) / Double(rows * 255)
        let avgR = Double(sumR) / Double(rows * 255)
        let sideAvg = (avgL + avgR) / 2.0

        // Strong narrow vertical contrast (e.g., pole, doorframe) directly above head
        return abs(avgM - sideAvg) > 0.28 && abs(avgL - avgR) < 0.15
    }
}
