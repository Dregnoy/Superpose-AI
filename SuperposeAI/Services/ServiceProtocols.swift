import AVFoundation
import UIKit

@MainActor
protocol CameraServicing: AnyObject {
    var cameraPosition: AVCaptureDevice.Position { get }
    var flashMode: AVCaptureDevice.FlashMode { get }
    var zoomFactor: CGFloat { get set }
    var isRAWEnabled: Bool { get set }
    var isRAWSupported: Bool { get }
    var isAppleProRAWSupported: Bool { get }
    var isHDRBracketingEnabled: Bool { get set }

    func toggleCamera()
    func toggleFlash()
    func setZoom(_ factor: CGFloat)
    func capturePhoto() async throws -> UIImage
    func capturePhotoWithRAW(preferRAW: Bool) async throws -> (UIImage, Data?)
    func captureBracketedHDR() async throws -> UIImage
}

@MainActor
protocol LibraryStoring: AnyObject {
    var items: [LibraryItem] { get }

    @discardableResult
    func saveCapturedPhoto(
        _ image: UIImage,
        isGeneratedReference: Bool,
        poseIdea: PoseIdea?,
        zoomFactor: Double?,
        overlayModeRaw: String?,
        rollDegrees: Double?,
        qualityScore: Double?
    ) -> UUID

    func updateQualityScore(id: UUID, score: Double)
    func image(for item: LibraryItem) -> UIImage?
    func deleteItems(ids: Set<UUID>)
    func toggleFavorite(id: UUID)
}

@MainActor
protocol ShotPackStoring: AnyObject {
    var isUnlimited: Bool { get }
    func consumeOnePack() -> Bool
}
