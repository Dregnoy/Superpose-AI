import CoreImage
import Metal
import UIKit

/// One-tap visual look presets for Simple Mode and post-capture styling.
enum PhotoLookPreset: String, CaseIterable, Identifiable {
    case natural = "Doğal"
    case cinematic = "Sinematik"
    case goldenHour = "Altın Saat"
    case monochrome = "Siyah-Beyaz"

    var id: String { rawValue }

    var next: PhotoLookPreset {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self) else { return .natural }
        return all[(idx + 1) % all.count]
    }
}

/// Applies subtle, natural on-device shadow/highlight recovery, vibrance,
/// and luminance sharpening using CoreImage—zero cloud upload.
enum PhotoEnhancerService {
    static let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device)
        }
        return CIContext()
    }()

    static func applyLook(_ preset: PhotoLookPreset, to image: UIImage) -> UIImage {
        guard preset != .natural else { return image }
        guard let cgImage = image.cgImage else { return image }
        var current = CIImage(cgImage: cgImage)

        switch preset {
        case .natural:
            return image
        case .cinematic:
            if let vibrance = CIFilter(name: "CIVibrance") {
                vibrance.setValue(current, forKey: kCIInputImageKey)
                vibrance.setValue(-0.12, forKey: "inputAmount")
                if let out = vibrance.outputImage { current = out }
            }
            if let controls = CIFilter(name: "CIColorControls") {
                controls.setValue(current, forKey: kCIInputImageKey)
                controls.setValue(1.12, forKey: kCIInputContrastKey)
                controls.setValue(-0.02, forKey: kCIInputBrightnessKey)
                if let out = controls.outputImage { current = out }
            }
        case .goldenHour:
            if let temp = CIFilter(name: "CITemperatureAndTint") {
                temp.setValue(current, forKey: kCIInputImageKey)
                temp.setValue(CIVector(x: 6800, y: 0), forKey: "inputNeutral")
                temp.setValue(CIVector(x: 5400, y: 0), forKey: "inputTargetNeutral")
                if let out = temp.outputImage { current = out }
            }
            if let vibrance = CIFilter(name: "CIVibrance") {
                vibrance.setValue(current, forKey: kCIInputImageKey)
                vibrance.setValue(0.20, forKey: "inputAmount")
                if let out = vibrance.outputImage { current = out }
            }
        case .monochrome:
            if let mono = CIFilter(name: "CIPhotoEffectNoir") {
                mono.setValue(current, forKey: kCIInputImageKey)
                if let out = mono.outputImage { current = out }
            }
        }

        guard let outputCG = context.createCGImage(current, from: current.extent) else {
            return image
        }
        return UIImage(cgImage: outputCG, scale: image.scale, orientation: image.imageOrientation)
    }

    /// One-Tap Magic ("Tek Vuruşluk Büyü"): balances dynamic range, micro-contrast,
    /// skin-safe vibrance, luminance crispness, and a subtle studio vignette on-device.
    static func applyOneTapMagic(_ image: UIImage, lumaHint: Double = 0.5) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        var current = CIImage(cgImage: cgImage)

        let shadowLift = lumaHint < 0.35 ? 0.36 : 0.26
        let highlightProtect = lumaHint > 0.72 ? 0.84 : 0.90
        if let shadowHighlight = CIFilter(name: "CIHighlightShadowAdjust") {
            shadowHighlight.setValue(current, forKey: kCIInputImageKey)
            shadowHighlight.setValue(shadowLift, forKey: "inputShadowAmount")
            shadowHighlight.setValue(highlightProtect, forKey: "inputHighlightAmount")
            if let out = shadowHighlight.outputImage { current = out }
        }

        if let controls = CIFilter(name: "CIColorControls") {
            controls.setValue(current, forKey: kCIInputImageKey)
            controls.setValue(1.06, forKey: kCIInputContrastKey)
            controls.setValue(lumaHint < 0.32 ? 0.03 : 0.0, forKey: kCIInputBrightnessKey)
            if let out = controls.outputImage { current = out }
        }

        if let vibrance = CIFilter(name: "CIVibrance") {
            vibrance.setValue(current, forKey: kCIInputImageKey)
            vibrance.setValue(0.18, forKey: "inputAmount")
            if let out = vibrance.outputImage { current = out }
        }

        if let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(current, forKey: kCIInputImageKey)
            sharpen.setValue(0.50, forKey: kCIInputSharpnessKey)
            if let out = sharpen.outputImage { current = out }
        }

        if let vignette = CIFilter(name: "CIVignette") {
            vignette.setValue(current, forKey: kCIInputImageKey)
            vignette.setValue(0.28, forKey: kCIInputIntensityKey)
            vignette.setValue(1.6, forKey: kCIInputRadiusKey)
            if let out = vignette.outputImage { current = out }
        }

        guard let outputCG = context.createCGImage(current, from: current.extent) else {
            return image
        }
        return UIImage(cgImage: outputCG, scale: image.scale, orientation: image.imageOrientation)
    }

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
        guard !dngData.isEmpty, let rawFilter = CIRAWFilter(imageData: dngData) else { return nil }
        if rawFilter.responds(to: NSSelectorFromString("setBoostAmount:")) {
            rawFilter.boostAmount = 0.65
        }
        if rawFilter.responds(to: NSSelectorFromString("setBoostShadowAmount:")) {
            rawFilter.boostShadowAmount = 0.45
        }
        if rawFilter.responds(to: NSSelectorFromString("setLuminanceNoiseReductionAmount:")) {
            rawFilter.luminanceNoiseReductionAmount = 0.35
        }
        if rawFilter.responds(to: NSSelectorFromString("setColorNoiseReductionAmount:")) {
            rawFilter.colorNoiseReductionAmount = 0.45
        }
        if rawFilter.responds(to: NSSelectorFromString("setSharpnessAmount:")) {
            rawFilter.sharpnessAmount = 0.35
        }

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
