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

    private let visionQueue = DispatchQueue(label: "com.superposelabs.vision", qos: .userInitiated)
    private var isProcessing = false
    private var lastProcessedTime: CFAbsoluteTime = 0
    @ObservationIgnored private var smileStreak: Int = 0
    @ObservationIgnored nonisolated private static let sharedCIContext: CIContext = {
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

        visionQueue.async { [weak self] in
            let rectRequest = VNDetectHumanRectanglesRequest()
            rectRequest.upperBodyOnly = isUpperBodyMode
            let faceRequest = VNDetectFaceLandmarksRequest()
            let poseRequest = shouldDetectPose ? VNDetectHumanBodyPoseRequest() : nil

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                var requests: [VNRequest] = [rectRequest, faceRequest]
                if let poseRequest { requests.append(poseRequest) }
                try handler.perform(requests)
            } catch {
                Task { @MainActor [weak self] in
                    self?.isProcessing = false
                }
                return
            }

            let detectedAll = (poseRequest?.results ?? []).prefix(2).compactMap { Self.extractSkeleton(from: $0) }
            let detectedSkeleton = detectedAll.first
            let detectedSecondary = detectedAll.count > 1 ? detectedAll[1] : nil
            let framing = Self.evaluateFraming(
                from: rectRequest.results?.first,
                skeleton: detectedSkeleton,
                upperBodyOnly: isUpperBodyMode
            )
            let eyesClosed = Self.areEyesClosed(in: faceRequest.results)
            let rawSmile = !eyesClosed && Self.isSmiling(in: faceRequest.results)
            let faceAngleHint = Self.faceAngleHint(in: faceRequest.results)
            let faceBox: CGRect? = faceRequest.results?.first.map { obs in
                let b = obs.boundingBox
                return CGRect(x: b.minX, y: 1.0 - b.maxY, width: b.width, height: b.height)
            }
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
                self.smileStreak = rawSmile ? (self.smileStreak + 1) : 0
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

    nonisolated private static func extractSkeleton(from observation: VNHumanBodyPoseObservation?) -> PoseSkeleton? {
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

    // MARK: - Static Image Pose Extraction (Inspo Import)

    /// Extracts a 1-person or 2-person pose skeleton, framing, and category from any imported
    /// reference photo entirely on-device with zero cloud AI cost.
    func extractPose(from image: UIImage) async -> PoseIdea? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = Self.cgImageOrientation(from: image.imageOrientation)

        return await withCheckedContinuation { continuation in
            visionQueue.async {
                let poseRequest = VNDetectHumanBodyPoseRequest()
                let rectRequest = VNDetectHumanRectanglesRequest()
                let classifyRequest = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([poseRequest, rectRequest, classifyRequest])
                    let skeletons = (poseRequest.results ?? []).prefix(2).compactMap { Self.extractSkeleton(from: $0) }
                    guard let primary = skeletons.first else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let secondary = skeletons.count > 1 ? skeletons[1] : nil

                    let hasLowerBody = primary.joints[.leftAnkle] != nil || primary.joints[.rightAnkle] != nil
                        || primary.joints[.leftKnee] != nil || primary.joints[.rightKnee] != nil
                    let hasTorso = primary.joints[.root] != nil || primary.joints[.leftHip] != nil || primary.joints[.rightHip] != nil
                    let box = rectRequest.results?.first?.boundingBox
                    let boxHeight = box?.height ?? 0

                    let framingLabel: String
                    if hasLowerBody || boxHeight > 0.65 {
                        framingLabel = "Tam Boy"
                    } else if hasTorso || boxHeight > 0.38 {
                        framingLabel = "Bel Üstü"
                    } else {
                        framingLabel = "Portre"
                    }

                    let jointXs = primary.joints.values.map(\.x)
                    let centerX = jointXs.isEmpty ? (box?.midX ?? 0.5) : (jointXs.reduce(0, +) / Double(jointXs.count))
                    let placementLabel: String
                    if centerX < 0.40 {
                        placementLabel = "Sol 1/3"
                    } else if centerX > 0.60 {
                        placementLabel = "Sağ 1/3"
                    } else {
                        placementLabel = "Orta"
                    }

                    let tags = (classifyRequest.results ?? [])
                        .filter { $0.confidence >= 0.2 }
                        .prefix(6)
                        .map { $0.identifier.lowercased() }

                    let inferredCategory: PoseCategory
                    if secondary != nil {
                        inferredCategory = .couples
                    } else if tags.contains(where: { $0.contains("beach") || $0.contains("coast") || $0.contains("ocean") || $0.contains("sea") }) {
                        inferredCategory = .beach
                    } else if tags.contains(where: { $0.contains("cafe") || $0.contains("restaurant") || $0.contains("coffee") }) {
                        inferredCategory = .cafe
                    } else if framingLabel == "Portre" {
                        inferredCategory = .portrait
                    } else {
                        inferredCategory = .street
                    }

                    let idea = PoseIdea(
                        title: secondary == nil ? "İlham Pozu (\(framingLabel))" : "İlham Çift Pozu",
                        angleLabel: "\(framingLabel) · \(placementLabel)",
                        confidenceTag: "Referans",
                        category: inferredCategory,
                        skeleton: primary,
                        secondarySkeleton: secondary,
                        coaching: CoachingTips(
                            summary: "Referans kadraj: \(framingLabel), \(placementLabel) yerleşimi.",
                            subjectTips: [
                                "Omuzlarını ve kalçanı ekrandaki silüete göre hizala.",
                                "İstersen Hayalet (Ghost) moduna geçip yarı saydam gölgeyle eşleş."
                            ],
                            photographerTips: [
                                "Öznemizi kadrajın \(placementLabel) bölgesine yerleştir (\(framingLabel) ölçeği).",
                                "Daha estetik portre oranları için 2x lensi kullan."
                            ]
                        )
                    )
                    continuation.resume(returning: idea)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    nonisolated private static func cgImageOrientation(from uiOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch uiOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    /// Extracts a background-free translucent silhouette from an imported photo
    /// using Apple Vision person segmentation for Photo-to-Ghost overlays.
    func extractPersonSilhouette(from image: UIImage) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = Self.cgImageOrientation(from: image.imageOrientation)

        return await withCheckedContinuation { continuation in
            visionQueue.async {
                let request = VNGeneratePersonSegmentationRequest()
                request.qualityLevel = .balanced
                request.outputPixelFormat = kCVPixelFormatType_OneComponent8

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                    guard let maskBuffer = request.results?.first?.pixelBuffer else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let ciContext = Self.sharedCIContext
                    let originalCI = CIImage(cgImage: cgImage)
                    let maskCI = CIImage(cvPixelBuffer: maskBuffer)

                    let scaleX = originalCI.extent.width / maskCI.extent.width
                    let scaleY = originalCI.extent.height / maskCI.extent.height
                    let scaledMask = maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

                    guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
                        continuation.resume(returning: nil)
                        return
                    }
                    blendFilter.setValue(originalCI, forKey: kCIInputImageKey)
                    blendFilter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
                    blendFilter.setValue(scaledMask, forKey: kCIInputMaskImageKey)

                    guard let output = blendFilter.outputImage,
                          let resultCG = ciContext.createCGImage(output, from: originalCI.extent) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: UIImage(cgImage: resultCG, scale: image.scale, orientation: image.imageOrientation))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    struct ShotQualityBreakdown: Sendable, Equatable {
        let totalScore: Double
        let faceQuality: Double
        let sharpnessScore: Double
        let poseMatchScore: Double?
    }

    /// Evaluates face capture quality, edge sharpness, and optional pose alignment
    /// on-device for a single captured photo.
    func evaluateShotQuality(image: UIImage, targetPose: PoseIdea? = nil) async -> ShotQualityBreakdown {
        await withCheckedContinuation { continuation in
            visionQueue.async {
                let breakdown = Self.evaluateShotSync(image: image, targetPose: targetPose)
                continuation.resume(returning: breakdown)
            }
        }
    }

    /// Evaluates face capture quality, sharpness, and optional pose alignment across
    /// multiple shots and returns the best frame on-device.
    func pickBestShot(from images: [UIImage], targetPose: PoseIdea? = nil) async -> UIImage? {
        guard images.count > 1 else { return images.first }

        return await withCheckedContinuation { continuation in
            visionQueue.async {
                var bestImage = images[0]
                var bestScore: Double = -1.0

                for image in images {
                    let breakdown = Self.evaluateShotSync(image: image, targetPose: targetPose)
                    if breakdown.totalScore > bestScore {
                        bestScore = breakdown.totalScore
                        bestImage = image
                    }
                }
                continuation.resume(returning: bestImage)
            }
        }
    }

    nonisolated private static func evaluateShotSync(image: UIImage, targetPose: PoseIdea?) -> ShotQualityBreakdown {
        guard let cgImage = image.cgImage else {
            return ShotQualityBreakdown(totalScore: 0, faceQuality: 0, sharpnessScore: 0, poseMatchScore: nil)
        }

        let orientation = cgImageOrientation(from: image.imageOrientation)
        let faceRequest = VNDetectFaceCaptureQualityRequest()
        var requests: [VNRequest] = [faceRequest]
        let poseRequest: VNDetectHumanBodyPoseRequest?
        if targetPose != nil {
            let pr = VNDetectHumanBodyPoseRequest()
            poseRequest = pr
            requests.append(pr)
        } else {
            poseRequest = nil
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try? handler.perform(requests)

        let hasFace = !(faceRequest.results?.isEmpty ?? true)
        let faceQuality = Double(faceRequest.results?.first?.faceCaptureQuality ?? 0.0)
        let sharpness = computeSharpnessScore(cgImage: cgImage)

        var poseMatchScore: Double? = nil
        if let target = targetPose,
           let detected = extractSkeleton(from: poseRequest?.results?.first) {
            poseMatchScore = Double(computePoseMatchScore(live: detected, target: target.skeleton))
        }

        let totalScore: Double
        if hasFace, let poseScore = poseMatchScore {
            totalScore = 0.45 * (faceQuality * 100.0) + 0.35 * (sharpness * 100.0) + 0.20 * poseScore
        } else if hasFace {
            totalScore = 0.55 * (faceQuality * 100.0) + 0.45 * (sharpness * 100.0)
        } else if let poseScore = poseMatchScore {
            totalScore = 0.65 * (sharpness * 100.0) + 0.35 * poseScore
        } else {
            totalScore = sharpness * 100.0
        }

        return ShotQualityBreakdown(
            totalScore: min(100.0, max(0.0, totalScore)),
            faceQuality: faceQuality,
            sharpnessScore: sharpness,
            poseMatchScore: poseMatchScore
        )
    }

    nonisolated static func computeSharpnessScore(cgImage: CGImage) -> Double {
        let ciImage = CIImage(cgImage: cgImage)
        let maxDim = max(ciImage.extent.width, ciImage.extent.height)
        let scale = maxDim > 512 ? 512.0 / maxDim : 1.0
        let scaled = scale < 1.0
            ? ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : ciImage

        guard let edgesFilter = CIFilter(name: "CIEdges") else { return 0.5 }
        edgesFilter.setValue(scaled, forKey: kCIInputImageKey)
        edgesFilter.setValue(2.0, forKey: kCIInputIntensityKey)
        guard let edgeOutput = edgesFilter.outputImage else { return 0.5 }

        guard let avgFilter = CIFilter(name: "CIAreaAverage") else { return 0.5 }
        avgFilter.setValue(edgeOutput, forKey: kCIInputImageKey)
        avgFilter.setValue(CIVector(cgRect: edgeOutput.extent), forKey: kCIInputExtentKey)
        guard let avgOutput = avgFilter.outputImage else { return 0.5 }

        var pixel = [UInt8](repeating: 0, count: 4)
        sharedCIContext.render(
            avgOutput,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let avgIntensity = (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / (3.0 * 255.0)
        return min(1.0, max(0.0, avgIntensity / 0.14))
    }

    /// Classifies the environment on-device using Apple Vision (e.g. "outdoor", "beach", "cafe")
    /// so only anonymous text tags—never pixels—are shared with AI.
    func classifySceneTags(from image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = Self.cgImageOrientation(from: image.imageOrientation)

        return await withCheckedContinuation { continuation in
            visionQueue.async {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                    let tags = (request.results ?? [])
                        .filter { $0.confidence >= 0.25 }
                        .prefix(4)
                        .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
                    continuation.resume(returning: Array(tags))
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// Applies subtle on-device portrait background blur using person segmentation.
    static func applyPortraitBokeh(to image: UIImage, blurSigma: Double = 10.0) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = cgImageOrientation(from: image.imageOrientation)

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNGeneratePersonSegmentationRequest()
                request.qualityLevel = .balanced
                request.outputPixelFormat = kCVPixelFormatType_OneComponent8

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                    guard let maskBuffer = request.results?.first?.pixelBuffer else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let ciContext = Self.sharedCIContext
                    let originalCI = CIImage(cgImage: cgImage)
                    let maskCI = CIImage(cvPixelBuffer: maskBuffer)
                    let scaleX = originalCI.extent.width / maskCI.extent.width
                    let scaleY = originalCI.extent.height / maskCI.extent.height
                    let scaledMask = maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

                    let blurredBG = originalCI
                        .clampedToExtent()
                        .applyingGaussianBlur(sigma: max(2.0, min(24.0, blurSigma)))
                        .cropped(to: originalCI.extent)

                    guard let blend = CIFilter(name: "CIBlendWithMask") else {
                        continuation.resume(returning: nil)
                        return
                    }
                    blend.setValue(originalCI, forKey: kCIInputImageKey)
                    blend.setValue(blurredBG, forKey: kCIInputBackgroundImageKey)
                    blend.setValue(scaledMask, forKey: kCIInputMaskImageKey)

                    guard let output = blend.outputImage,
                          let resultCG = ciContext.createCGImage(output, from: originalCI.extent) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: UIImage(cgImage: resultCG, scale: image.scale, orientation: image.imageOrientation))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
