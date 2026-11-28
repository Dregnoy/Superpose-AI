import Vision
import CoreImage
import Metal
import UIKit
import Foundation

/// Runs 100% on-device using Apple Vision and CoreVideo luma analysis
/// to provide zero-latency lighting, framing, and pose-match feedback.
@MainActor
@Observable
final class PoseVisionService {
    var guidance = LiveGuidanceState()
    var focusPeakingImage: UIImage? = nil
    var isPowerSavingActive: Bool {
        let lowBattery = UIDevice.current.batteryLevel >= 0 && UIDevice.current.batteryLevel <= 0.20
        return lowBattery || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    let visionQueue = DispatchQueue(label: "com.superposelabs.vision", qos: .userInitiated)
    private var isProcessing = false
    private var lastProcessedTime: CFAbsoluteTime = 0
    @ObservationIgnored private var smileStreak: Int = 0
    @ObservationIgnored private var analysisTick: Int = 0
    @ObservationIgnored nonisolated static let sharedCIContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device)
        }
        return CIContext()
    }()

    /// Adapts frame analysis rate based on device thermal state, low power mode, and <20% battery.
    private var minimumInterval: CFAbsoluteTime {
        if isPowerSavingActive { return 0.35 }
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return 0.12      // ~8 fps
        case .fair: return 0.20         // 5 fps
        case .serious, .critical: return 0.35 // ~3 fps
        @unknown default: return 0.15
        }
    }

    func analyzeFrame(_ pixelBuffer: CVPixelBuffer, targetPose: PoseIdea?, enableFocusPeaking: Bool = false) {
        let now = CFAbsoluteTimeGetCurrent()
        let effectiveInterval = (targetPose == nil && guidance.framing == .noSubject && !enableFocusPeaking)
            ? max(minimumInterval, 0.25)
            : minimumInterval
        guard !isProcessing, now - lastProcessedTime >= effectiveInterval else { return }

        if !enableFocusPeaking && focusPeakingImage != nil {
            focusPeakingImage = nil
        }

        isProcessing = true
        lastProcessedTime = now

        let metrics = Self.estimateLightingMetrics(from: pixelBuffer)
        let lighting: LightingStatus = {
            if metrics.average < 0.20 && metrics.edgeAverage < 0.20 { return .lowContrast }
            if metrics.average < 0.22 { return .tooDark }
            if metrics.average > 0.86 { return .backlitOrHarsh }
            if metrics.leftAverage - metrics.rightAverage > 0.20 { return .turnLeftForLight }
            if metrics.rightAverage - metrics.leftAverage > 0.20 { return .turnRightForLight }
            return .good
        }()
        let luma = metrics.average

        let isUpperBodyMode = (targetPose?.category == .cafe || targetPose?.category == .portrait)
        let shouldDetectPose = (targetPose != nil)
        let currentTick = analysisTick
        analysisTick &+= 1
        let runRect = (currentTick % 2 == 0)
        let runFace = (currentTick % 2 == 1) || (currentTick == 0)
        let prevGuidance = guidance

        visionQueue.async { [weak self] in
            let rectRequest: VNDetectHumanRectanglesRequest? = runRect ? {
                let r = VNDetectHumanRectanglesRequest()
                r.upperBodyOnly = isUpperBodyMode
                return r
            }() : nil
            let faceRequest: VNDetectFaceLandmarksRequest? = runFace ? VNDetectFaceLandmarksRequest() : nil
            let poseRequest = shouldDetectPose ? VNDetectHumanBodyPoseRequest() : nil

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                var requests: [VNRequest] = []
                if let rectRequest { requests.append(rectRequest) }
                if let faceRequest { requests.append(faceRequest) }
                if let poseRequest { requests.append(poseRequest) }
                if !requests.isEmpty {
                    try handler.perform(requests)
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.isProcessing = false
                }
                return
            }

            let detectedAll = (poseRequest?.results ?? []).prefix(2).compactMap { Self.extractSkeleton(from: $0) }
            let detectedSkeleton = detectedAll.first
            let detectedSecondary = detectedAll.count > 1 ? detectedAll[1] : nil
            let framing: FramingStatus = {
                if let rectRequest {
                    return Self.evaluateFraming(
                        from: rectRequest.results?.first,
                        skeleton: detectedSkeleton,
                        upperBodyOnly: isUpperBodyMode
                    )
                }
                return prevGuidance.framing
            }()
            let eyesClosed = faceRequest.map { Self.areEyesClosed(in: $0.results) } ?? prevGuidance.eyesClosed
            let rawSmile: Bool? = faceRequest.map { !eyesClosed && Self.isSmiling(in: $0.results) }
            let faceAngleHint = faceRequest.map { Self.faceAngleHint(in: $0.results) } ?? prevGuidance.faceAngleHint
            let faceBox: CGRect? = faceRequest.map { req in
                req.results?.first.map { obs in
                    let b = obs.boundingBox
                    return CGRect(x: b.minX, y: 1.0 - b.maxY, width: b.width, height: b.height)
                }
            } ?? prevGuidance.detectedFaceBox
            let couplesHint = Self.evaluateCouplesBalance(first: detectedSkeleton, second: detectedSecondary)
            let poleWarning = Self.detectVerticalLineBehindHead(in: pixelBuffer, nose: detectedSkeleton?.joints[.nose])
            let contrastDiff = abs(metrics.average - metrics.edgeAverage)
            let subjectContrastHint: String? = (detectedSkeleton != nil && contrastDiff < 0.06)
                ? "Arka plan karışık — Portre Bokeh dene"
                : nil
            let matchScore: Int? = {
                guard let targetPose, let detectedSkeleton else { return nil }
                let primary = Self.computePoseMatchScore(live: detectedSkeleton, target: targetPose.skeleton)
                if let targetSecond = targetPose.secondarySkeleton, let detectedSecondary {
                    let secondary = Self.computePoseMatchScore(live: detectedSecondary, target: targetSecond)
                    return (primary + secondary) / 2
                }
                return primary
            }()

            let peakingCG: CGImage? = enableFocusPeaking ? self?.renderFocusPeakingMask(from: pixelBuffer) : nil

            Task { @MainActor [weak self] in
                guard let self else { return }
                if let rawSmile {
                    self.smileStreak = rawSmile ? (self.smileStreak + 1) : 0
                }
                let isGoodSmile = self.smileStreak >= 3
                self.focusPeakingImage = peakingCG.map { UIImage(cgImage: $0) }
                self.guidance = LiveGuidanceState(
                    lighting: lighting,
                    framing: framing,
                    lumaScore: luma,
                    poseMatchScore: matchScore,
                    eyesClosed: eyesClosed,
                    isGoodSmile: isGoodSmile,
                    backgroundPoleWarning: poleWarning,
                    couplesBalanceHint: couplesHint,
                    faceAngleHint: faceAngleHint,
                    subjectContrastHint: subjectContrastHint,
                    detectedFaceBox: faceBox,
                    detectedSkeleton: detectedSkeleton,
                    detectedSecondarySkeleton: detectedSecondary
                )
                self.isProcessing = false
            }
        }
    }

    nonisolated private func renderFocusPeakingMask(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let scaled = CIImage(cvPixelBuffer: pixelBuffer)
            .transformed(by: CGAffineTransform(scaleX: 0.35, y: 0.35))
        guard let edges = CIFilter(name: "CIEdges") else { return nil }
        edges.setValue(scaled, forKey: kCIInputImageKey)
        edges.setValue(4.0, forKey: kCIInputIntensityKey)
        guard let edgeOut = edges.outputImage else { return nil }

        guard let contrast = CIFilter(name: "CIColorControls") else { return nil }
        contrast.setValue(edgeOut, forKey: kCIInputImageKey)
        contrast.setValue(2.0, forKey: kCIInputContrastKey)
        contrast.setValue(-0.25, forKey: kCIInputBrightnessKey)
        contrast.setValue(0.0, forKey: kCIInputSaturationKey)
        guard let contrastOut = contrast.outputImage else { return nil }

        guard let alphaMask = CIFilter(name: "CIMaskToAlpha") else { return nil }
        alphaMask.setValue(contrastOut, forKey: kCIInputImageKey)
        guard let finalCI = alphaMask.outputImage else { return nil }

        return Self.sharedCIContext.createCGImage(finalCI, from: scaled.extent)
    }

    // MARK: - On-Device Luma, Directional Light & Contrast Estimation

    private struct LightingMetrics {
        let average: Double
        let leftAverage: Double
        let rightAverage: Double
        let edgeAverage: Double
    }

    nonisolated private static func estimateLightingMetrics(from pixelBuffer: CVPixelBuffer) -> LightingMetrics {
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

    // MARK: - Vision Body Pose Extraction

    nonisolated static func extractSkeleton(from observation: VNHumanBodyPoseObservation?) -> PoseSkeleton? {
        guard let observation else { return nil }

        let mapping: [(BodyJoint, VNHumanBodyPoseObservation.JointName)] = [
            (.nose, .nose),
            (.neck, .neck),
            (.leftShoulder, .leftShoulder),
            (.rightShoulder, .rightShoulder),
            (.leftElbow, .leftElbow),
            (.rightElbow, .rightElbow),
            (.leftWrist, .leftWrist),
            (.rightWrist, .rightWrist),
            (.root, .root),
            (.leftHip, .leftHip),
            (.rightHip, .rightHip),
            (.leftKnee, .leftKnee),
            (.rightKnee, .rightKnee),
            (.leftAnkle, .leftAnkle),
            (.rightAnkle, .rightAnkle)
        ]

        var joints: [BodyJoint: NormalizedPoint] = [:]
        for (joint, vnName) in mapping {
            if let point = try? observation.recognizedPoint(vnName), point.confidence > 0.25 {
                // Vision origin is bottom-left; SwiftUI origin is top-left.
                joints[joint] = NormalizedPoint(x: point.location.x, y: 1.0 - point.location.y)
            }
        }

        return joints.isEmpty ? nil : PoseSkeleton(joints: joints)
    }

    // MARK: - Framing & Composition Rules

    nonisolated private static func evaluateFraming(
        from rectObservation: VNHumanObservation?,
        skeleton: PoseSkeleton?,
        upperBodyOnly: Bool = false
    ) -> FramingStatus {
        guard let rect = rectObservation?.boundingBox else {
            return skeleton == nil ? .noSubject : .great
        }

        // Vision rect origin is bottom-left
        let area = rect.width * rect.height
        let centerX = rect.midX
        let topEdge = 1.0 - rect.maxY // distance from top of frame

        let maxArea = upperBodyOnly ? 0.86 : 0.72
        if area > maxArea { return .tooClose }
        if area < 0.08 { return .tooFar }
        if centerX < 0.34 { return .moveRight }
        if centerX > 0.66 { return .moveLeft }
        if topEdge > 0.28 { return .tiltDown }

        return .great
    }

    // MARK: - Eye Blink Detection (Eye Aspect Ratio)

    nonisolated private static func areEyesClosed(in faces: [VNFaceObservation]?) -> Bool {
        guard let face = faces?.first, let landmarks = face.landmarks else { return false }
        let ratios = [landmarks.leftEye, landmarks.rightEye].compactMap { eye -> CGFloat? in
            guard let pts = eye?.normalizedPoints, pts.count >= 4 else { return nil }
            let xs = pts.map(\.x), ys = pts.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return nil }
            let width = maxX - minX
            guard width > 0.01 else { return nil }
            return (maxY - minY) / width
        }
        guard !ratios.isEmpty else { return false }
        let avgEAR = ratios.reduce(0, +) / CGFloat(ratios.count)
        return avgEAR < 0.14
    }

    nonisolated private static func faceAngleHint(in faces: [VNFaceObservation]?) -> String? {
        guard let face = faces?.first else { return nil }
        if let roll = face.roll?.doubleValue, abs(roll) > 0.28 {
            return "Başını biraz düz tut"
        }
        if let yaw = face.yaw?.doubleValue, abs(yaw) > 0.55 {
            return "Yüzünü biraz kameraya dön"
        }
        return nil
    }

    nonisolated private static func isSmiling(in faces: [VNFaceObservation]?) -> Bool {
        guard let face = faces?.first,
              let lips = face.landmarks?.outerLips?.normalizedPoints,
              lips.count >= 6 else { return false }
        let xs = lips.map(\.x)
        let ys = lips.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return false }
        let mouthWidth = maxX - minX
        let mouthHeight = maxY - minY
        guard mouthWidth >= 0.40, mouthHeight > 0.02 else { return false }

        // Check mouth width relative to outer eye span when eyes are detected
        if let leftEyePts = face.landmarks?.leftEye?.normalizedPoints,
           let rightEyePts = face.landmarks?.rightEye?.normalizedPoints,
           let minEyeX = leftEyePts.map(\.x).min(),
           let maxEyeX = rightEyePts.map(\.x).max() {
            let eyeSpan = maxEyeX - minEyeX
            if eyeSpan > 0.1 && mouthWidth < eyeSpan * 0.88 {
                return false
            }
        }

        // Corners must be distinctly lifted above the mouth vertical midpoint (Vision Y is upward)
        let leftCorner = lips.min(by: { $0.x < $1.x })
        let rightCorner = lips.max(by: { $0.x < $1.x })
        let midY = (minY + maxY) / 2.0
        let cornerAvgY = ((leftCorner?.y ?? midY) + (rightCorner?.y ?? midY)) / 2.0
        return cornerAvgY > midY + 0.012
    }

    // MARK: - Couples Depth/Size Balance

    nonisolated private static func evaluateCouplesBalance(first: PoseSkeleton?, second: PoseSkeleton?) -> String? {
        guard let first, let second,
              let n1 = first.joints[.neck], let r1 = first.joints[.root],
              let n2 = second.joints[.neck], let r2 = second.joints[.root] else {
            return nil
        }
        let h1 = abs(r1.y - n1.y)
        let h2 = abs(r2.y - n2.y)
        guard h1 > 0.05, h2 > 0.05 else { return nil }

        let leftIsFirst = n1.x < n2.x
        let leftH = leftIsFirst ? h1 : h2
        let rightH = leftIsFirst ? h2 : h1

        if leftH < rightH * 0.78 { return "Soldaki yarım adım öne gelsin" }
        if rightH < leftH * 0.78 { return "Sağdaki yarım adım öne gelsin" }
        return nil
    }

    // MARK: - Head Background Vertical Line / Pole Detection

    nonisolated private static func detectVerticalLineBehindHead(in pixelBuffer: CVPixelBuffer, nose: NormalizedPoint?) -> Bool {
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

    // MARK: - Scale-Independent Pose Similarity Score (0 - 100%)

    /// Compares bone-vector angles between the live pose and target pose so
    /// distance from the camera or height differences do not penalize the score.
    nonisolated static func computePoseMatchScore(live: PoseSkeleton, target: PoseSkeleton) -> Int {
        var angleScoreSum = 0.0
        var angleCount = 0

        for (start, end) in PoseSkeleton.boneConnections {
            guard let la = live.joints[start], let lb = live.joints[end],
                  let ta = target.joints[start], let tb = target.joints[end] else {
                continue
            }

            let ldx = lb.x - la.x
            let ldy = lb.y - la.y
            let tdx = tb.x - ta.x
            let tdy = tb.y - ta.y

            let lMag = hypot(ldx, ldy)
            let tMag = hypot(tdx, tdy)
            guard lMag > 0.01, tMag > 0.01 else { continue }

            let dot = (ldx * tdx + ldy * tdy) / (lMag * tMag)
            let clampedDot = max(-1.0, min(1.0, dot))
            // Map cosine similarity [-1, 1] -> [0, 1]
            let boneSimilarity = (clampedDot + 1.0) / 2.0
            angleScoreSum += boneSimilarity
            angleCount += 1
        }

        guard angleCount >= 4 else { return 0 }
        let avgSimilarity = angleScoreSum / Double(angleCount)
        // Sharpen curve slightly so < 0.5 cosine feels low and > 0.92 feels 85-100%
        let adjusted = max(0.0, min(1.0, (avgSimilarity - 0.35) / 0.65))
        return Int((adjusted * 100.0).rounded())
    }

}
