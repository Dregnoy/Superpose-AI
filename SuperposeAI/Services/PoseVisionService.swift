import Vision
import CoreImage
import UIKit
import Foundation

/// Runs 100% on-device using Apple Vision and CoreVideo luma analysis
/// to provide zero-latency lighting, framing, and pose-match feedback.
@MainActor
@Observable
final class PoseVisionService {
    var guidance = LiveGuidanceState()

    private let visionQueue = DispatchQueue(label: "com.superposelabs.vision", qos: .userInitiated)
    private var isProcessing = false
    private var lastProcessedTime: CFAbsoluteTime = 0

    /// Adapts frame analysis rate based on device thermal state to save battery.
    private var minimumInterval: CFAbsoluteTime {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return 0.12      // ~8 fps
        case .fair: return 0.20         // 5 fps
        case .serious, .critical: return 0.35 // ~3 fps
        @unknown default: return 0.15
        }
    }

    func analyzeFrame(_ pixelBuffer: CVPixelBuffer, targetPose: PoseIdea?) {
        let now = CFAbsoluteTimeGetCurrent()
        guard !isProcessing, now - lastProcessedTime >= minimumInterval else { return }

        isProcessing = true
        lastProcessedTime = now

        let luma = Self.estimateAverageLuma(from: pixelBuffer)
        let lighting: LightingStatus = {
            if luma < 0.22 { return .tooDark }
            if luma > 0.86 { return .backlitOrHarsh }
            return .good
        }()

        let isUpperBodyMode = (targetPose?.category == .cafe || targetPose?.category == .portrait)

        visionQueue.async { [weak self] in
            let poseRequest = VNDetectHumanBodyPoseRequest()
            let rectRequest = VNDetectHumanRectanglesRequest()
            rectRequest.upperBodyOnly = isUpperBodyMode

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([poseRequest, rectRequest])
            } catch {
                Task { @MainActor [weak self] in
                    self?.isProcessing = false
                }
                return
            }

            let detectedAll = (poseRequest.results ?? []).prefix(2).compactMap { Self.extractSkeleton(from: $0) }
            let detectedSkeleton = detectedAll.first
            let detectedSecondary = detectedAll.count > 1 ? detectedAll[1] : nil
            let framing = Self.evaluateFraming(
                from: rectRequest.results?.first,
                skeleton: detectedSkeleton,
                upperBodyOnly: isUpperBodyMode
            )
            let matchScore: Int? = {
                guard let targetPose, let detectedSkeleton else { return nil }
                let primary = Self.computePoseMatchScore(live: detectedSkeleton, target: targetPose.skeleton)
                if let targetSecond = targetPose.secondarySkeleton, let detectedSecondary {
                    let secondary = Self.computePoseMatchScore(live: detectedSecondary, target: targetSecond)
                    return (primary + secondary) / 2
                }
                return primary
            }()

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.guidance = LiveGuidanceState(
                    lighting: lighting,
                    framing: framing,
                    lumaScore: luma,
                    poseMatchScore: matchScore,
                    detectedSkeleton: detectedSkeleton,
                    detectedSecondarySkeleton: detectedSecondary
                )
                self.isProcessing = false
            }
        }
    }

    // MARK: - On-Device Luma Estimation

    nonisolated private static func estimateAverageLuma(from pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return 0.5
        }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var total: Int = 0
        var count: Int = 0
        let step = 16

        for y in stride(from: 0, to: height, by: step) {
            let row = buffer + y * bytesPerRow
            for x in stride(from: 0, to: width, by: step) {
                total += Int(row[x])
                count += 1
            }
        }

        guard count > 0 else { return 0.5 }
        return Double(total) / Double(count * 255)
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

    /// Extracts a 1-person or 2-person pose skeleton from any imported reference photo
    /// entirely on-device with zero cloud AI cost.
    func extractPose(from image: UIImage) async -> PoseIdea? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = Self.cgImageOrientation(from: image.imageOrientation)

        return await withCheckedContinuation { continuation in
            visionQueue.async {
                let request = VNDetectHumanBodyPoseRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                    let skeletons = (request.results ?? []).prefix(2).compactMap { Self.extractSkeleton(from: $0) }
                    guard let primary = skeletons.first else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let secondary = skeletons.count > 1 ? skeletons[1] : nil
                    let idea = PoseIdea(
                        title: secondary == nil ? "İçe Aktarılan Poz" : "İçe Aktarılan Çift Pozu",
                        angleLabel: "Fotoğrafından Çıkarıldı",
                        confidenceTag: "İlham",
                        skeleton: primary,
                        secondarySkeleton: secondary,
                        coaching: CoachingTips(
                            summary: "Seçtiğin fotoğraftan cihaz içinde anında çıkarıldı.",
                            subjectTips: [
                                "Omuzlarını ve kalçanı ekrandaki silüete göre hizala.",
                                "İstersen Hayalet (Ghost) moduna geçip yarı saydam gölgeyle eşleş."
                            ],
                            photographerTips: [
                                "Referans fotoğraftaki kamera yüksekliği ve mesafeyi yakalamaya çalış.",
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

                    let ciContext = CIContext()
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

    /// Evaluates face capture quality across a 3-shot burst and returns the sharpest,
    /// clearest frame on-device.
    func pickBestShot(from images: [UIImage]) async -> UIImage? {
        guard images.count > 1 else { return images.first }

        return await withCheckedContinuation { continuation in
            visionQueue.async {
                var bestImage = images[0]
                var bestScore: Float = -1.0

                for image in images {
                    guard let cgImage = image.cgImage else { continue }
                    let request = VNDetectFaceCaptureQualityRequest()
                    let orientation = Self.cgImageOrientation(from: image.imageOrientation)
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                    try? handler.perform([request])

                    let quality = request.results?.first?.faceCaptureQuality ?? 0.0
                    if quality > bestScore {
                        bestScore = quality
                        bestImage = image
                    }
                }
                continuation.resume(returning: bestImage)
            }
        }
    }
}
