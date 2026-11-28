import CoreImage
import Metal
import UIKit

/// Applies subtle, natural on-device shadow/highlight recovery, vibrance,
/// and luminance sharpening using CoreImage—zero cloud upload.
enum PhotoEnhancerService {
    static let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device)
        }
        return CIContext()
    }()

    static func naturalizeAndSharpen(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        var current = CIImage(cgImage: cgImage)

        // 1. Subtle shadow lift & highlight recovery for natural dynamic range
        if let shadowHighlight = CIFilter(name: "CIHighlightShadowAdjust") {
            shadowHighlight.setValue(current, forKey: kCIInputImageKey)
            shadowHighlight.setValue(0.24, forKey: "inputShadowAmount")
            shadowHighlight.setValue(0.92, forKey: "inputHighlightAmount")
            if let out = shadowHighlight.outputImage { current = out }
        }

        // 2. Gentle natural vibrance (preserves skin tones)
        if let vibrance = CIFilter(name: "CIVibrance") {
            vibrance.setValue(current, forKey: kCIInputImageKey)
            vibrance.setValue(0.14, forKey: "inputAmount")
            if let out = vibrance.outputImage { current = out }
        }

        // 3. Luminance-only sharpening (crisp eyes/hair without color noise)
        if let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(current, forKey: kCIInputImageKey)
            sharpen.setValue(0.45, forKey: kCIInputSharpnessKey)
            if let out = sharpen.outputImage { current = out }
        }

        guard let outputCG = context.createCGImage(current, from: current.extent) else {
            return image
        }
        return UIImage(cgImage: outputCG, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Develops a 12-bit/16-bit DNG RAW buffer on-device using Apple's `CIRAWFilter`
    /// with balanced highlight/shadow recovery and luminance noise reduction.
    static func developRAW(_ dngData: Data) -> UIImage? {
        guard let rawFilter = CIRAWFilter(imageData: dngData) else { return nil }
        rawFilter.boostAmount = 0.65
        rawFilter.boostShadowAmount = 0.45
        rawFilter.luminanceNoiseReductionAmount = 0.35
        rawFilter.colorNoiseReductionAmount = 0.45
        rawFilter.sharpnessAmount = 0.35

        guard var ciImage = rawFilter.outputImage else { return nil }
        if let shadowHighlight = CIFilter(name: "CIHighlightShadowAdjust") {
            shadowHighlight.setValue(ciImage, forKey: kCIInputImageKey)
            shadowHighlight.setValue(0.18, forKey: "inputShadowAmount")
            shadowHighlight.setValue(0.90, forKey: "inputHighlightAmount")
            if let out = shadowHighlight.outputImage { ciImage = out }
        }

        guard let outputCG = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: outputCG)
    }

    /// Fuses bracketed exposure frames (-1 EV, 0 EV, +1 EV) on-device to expand
    /// dynamic range on devices without Apple ProRAW (e.g. iPhone 11).
    static func fuseExposureBracket(_ images: [UIImage]) -> UIImage {
        guard let base = images.first else { return UIImage() }
        guard images.count > 1 else { return naturalizeAndSharpen(base) }

        let ciImages = images.compactMap { img -> CIImage? in
            guard let cg = img.cgImage else { return nil }
            return CIImage(cgImage: cg)
        }
        guard var blended = ciImages.first else { return base }

        for (index, nextImage) in ciImages.dropFirst().enumerated() {
            let alpha = CGFloat(1.0 / Double(index + 2))
            guard let alphaFilter = CIFilter(name: "CIColorMatrix") else { continue }
            alphaFilter.setValue(nextImage, forKey: kCIInputImageKey)
            alphaFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: alpha), forKey: "inputAVector")
            guard let weighted = alphaFilter.outputImage,
                  let composite = CIFilter(name: "CISourceOverCompositing") else { continue }
            composite.setValue(weighted, forKey: kCIInputImageKey)
            composite.setValue(blended, forKey: kCIInputBackgroundImageKey)
            if let out = composite.outputImage {
                blended = out
            }
        }

        if let shadowHighlight = CIFilter(name: "CIHighlightShadowAdjust") {
            shadowHighlight.setValue(blended, forKey: kCIInputImageKey)
            shadowHighlight.setValue(0.28, forKey: "inputShadowAmount")
            shadowHighlight.setValue(0.88, forKey: "inputHighlightAmount")
            if let out = shadowHighlight.outputImage { blended = out }
        }

        if let vibrance = CIFilter(name: "CIVibrance") {
            vibrance.setValue(blended, forKey: kCIInputImageKey)
            vibrance.setValue(0.12, forKey: "inputAmount")
            if let out = vibrance.outputImage { blended = out }
        }

        guard let outputCG = context.createCGImage(blended, from: blended.extent) else {
            return base
        }
        return UIImage(cgImage: outputCG, scale: base.scale, orientation: base.imageOrientation)
    }
}
