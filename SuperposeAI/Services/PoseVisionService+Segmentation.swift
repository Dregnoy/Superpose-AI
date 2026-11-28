import CoreImage
import CoreVideo
import UIKit
import Vision

extension PoseVisionService {
    nonisolated func renderFocusPeakingMask(from pixelBuffer: CVPixelBuffer) -> CGImage? {
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

    /// Virtual Studio Relight ("Sanal Stüdyo Işığı"):
    /// Uses `VNGeneratePersonSegmentationRequest` to brighten & crisp the subject by ~10-15%
    /// while gently softening and dimming the background for studio separation.
    static func applyStudioRelight(to image: UIImage, intensity: Double = 0.70) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let clampedIntensity = max(0.2, min(1.0, intensity))
        let orientation = cgImageOrientation(from: image.imageOrientation)

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNGeneratePersonSegmentationRequest()
                request.qualityLevel = .accurate
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
                    let scaledMask = maskCI
                        .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                        .clampedToExtent()
                        .applyingGaussianBlur(sigma: 2.5)
                        .cropped(to: originalCI.extent)

                    // Subject: ~12% brighter + subtle micro-contrast & luminance crispness
                    var subjectCI = originalCI
                    if let exposure = CIFilter(name: "CIExposureAdjust") {
                        exposure.setValue(subjectCI, forKey: kCIInputImageKey)
                        exposure.setValue(0.20 * clampedIntensity, forKey: kCIInputEVKey)
                        if let out = exposure.outputImage { subjectCI = out }
                    }
                    if let controls = CIFilter(name: "CIColorControls") {
                        controls.setValue(subjectCI, forKey: kCIInputImageKey)
                        controls.setValue(1.0 + 0.05 * clampedIntensity, forKey: kCIInputContrastKey)
                        if let out = controls.outputImage { subjectCI = out }
                    }
                    if let sharpen = CIFilter(name: "CISharpenLuminance") {
                        sharpen.setValue(subjectCI, forKey: kCIInputImageKey)
                        sharpen.setValue(0.35 * clampedIntensity, forKey: kCIInputSharpnessKey)
                        if let out = sharpen.outputImage { subjectCI = out }
                    }

                    // Background: gently dimmed & softly diffused
                    var backgroundCI = originalCI
                    if let bgExposure = CIFilter(name: "CIExposureAdjust") {
                        bgExposure.setValue(backgroundCI, forKey: kCIInputImageKey)
                        bgExposure.setValue(-0.28 * clampedIntensity, forKey: kCIInputEVKey)
                        if let out = bgExposure.outputImage { backgroundCI = out }
                    }
                    backgroundCI = backgroundCI
                        .clampedToExtent()
                        .applyingGaussianBlur(sigma: 1.8 * clampedIntensity)
                        .cropped(to: originalCI.extent)

                    guard let blend = CIFilter(name: "CIBlendWithMask") else {
                        continuation.resume(returning: nil)
                        return
                    }
                    blend.setValue(subjectCI, forKey: kCIInputImageKey)
                    blend.setValue(backgroundCI, forKey: kCIInputBackgroundImageKey)
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
