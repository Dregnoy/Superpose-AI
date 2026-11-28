import UIKit

/// Renders a clean 9:16 story-ready card featuring the captured photo,
/// its on-device aesthetic score badge, and optional pose title.
enum ShareCardRenderer {
    static func renderStoryCard(
        photo: UIImage,
        aestheticReport: AestheticScoreReport?,
        poseTitle: String?
    ) -> UIImage {
        let canvasSize = CGSize(width: 1080, height: 1920)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { ctx in
            let cg = ctx.cgContext

            // Studio dark gradient background
            let colors = [
                UIColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1.0).cgColor,
                UIColor(red: 0.09, green: 0.13, blue: 0.19, alpha: 1.0).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: canvasSize.height), options: [])
            }

            // Photo frame (centered, rounded)
            let frameRect = CGRect(x: 72, y: 200, width: 936, height: 1320)
            let clipPath = UIBezierPath(roundedRect: frameRect, cornerRadius: 42)
            cg.saveGState()
            clipPath.addClip()

            let imgAspect = photo.size.width / max(1, photo.size.height)
            let frameAspect = frameRect.width / frameRect.height
            let drawRect: CGRect
            if imgAspect > frameAspect {
                let drawWidth = frameRect.height * imgAspect
                drawRect = CGRect(
                    x: frameRect.midX - drawWidth / 2,
                    y: frameRect.minY,
                    width: drawWidth,
                    height: frameRect.height
                )
            } else {
                let drawHeight = frameRect.width / max(0.01, imgAspect)
                drawRect = CGRect(
                    x: frameRect.minX,
                    y: frameRect.midY - drawHeight / 2,
                    width: frameRect.width,
                    height: drawHeight
                )
            }
            photo.draw(in: drawRect)
            cg.restoreGState()

            UIColor.white.withAlphaComponent(0.18).setStroke()
            clipPath.lineWidth = 3
            clipPath.stroke()

            // Top Aesthetic Score Badge
            if let report = aestheticReport {
                let badgeText = "Estetik \(report.outOfTenText) • \(report.verdict)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 34, weight: .bold),
                    .foregroundColor: UIColor.black
                ]
                let textSize = (badgeText as NSString).size(withAttributes: attrs)
                let pillRect = CGRect(
                    x: (canvasSize.width - (textSize.width + 64)) / 2,
                    y: 100,
                    width: textSize.width + 64,
                    height: 68
                )
                UIColor(red: 0.25, green: 0.88, blue: 0.96, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: pillRect, cornerRadius: 34).fill()
                (badgeText as NSString).draw(
                    at: CGPoint(x: pillRect.minX + 32, y: pillRect.minY + (pillRect.height - textSize.height) / 2),
                    withAttributes: attrs
                )
            }

            // Bottom Pose Title & Subtle Superpose Branding
            let titleText = poseTitle ?? "Doğal Işık & Kadraj"
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 40, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let titleSize = (titleText as NSString).size(withAttributes: titleAttrs)
            (titleText as NSString).draw(
                at: CGPoint(x: (canvasSize.width - titleSize.width) / 2, y: 1600),
                withAttributes: titleAttrs
            )
        }
    }
}
