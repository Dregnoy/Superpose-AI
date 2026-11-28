import Foundation
import UIKit

/// Shared container helper for passing images from the iOS Share Extension
/// ("Paylaş -> Superpose") directly into the main camera pose extractor.
enum SharedPoseImportStore {
    static let appGroupID = "group.com.superposelabs.superpose"
    static let deepLinkURL = URL(string: "superpose://import-pose")!

    static var containerDirectory: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.temporaryDirectory
    }

    static var pendingImageURL: URL {
        containerDirectory.appendingPathComponent("pending_shared_pose.jpg")
    }

    @discardableResult
    static func saveSharedImage(_ image: UIImage) -> Bool {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return false }
        do {
            try data.write(to: pendingImageURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func consumeSharedImage() -> UIImage? {
        let url = pendingImageURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        try? FileManager.default.removeItem(at: url)
        return image
    }
}
