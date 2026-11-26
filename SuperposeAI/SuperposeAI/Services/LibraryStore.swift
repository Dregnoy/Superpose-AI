import UIKit
import Photos

@MainActor
@Observable
final class LibraryStore {
    var items: [LibraryItem] = []

    private let fileManager = FileManager.default
    private var libraryDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("SuperposeLibrary", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var indexURL: URL {
        libraryDirectory.appendingPathComponent("library_index.json")
    }

    init() {
        load()
    }

    func saveCapturedPhoto(
        _ image: UIImage,
        isGeneratedReference: Bool = false,
        poseIdea: PoseIdea? = nil,
        zoomFactor: Double? = nil,
        overlayModeRaw: String? = nil,
        rollDegrees: Double? = nil
    ) {
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = libraryDirectory.appendingPathComponent(filename)
        if let data = image.jpegData(compressionQuality: 0.9) {
            try? data.write(to: fileURL)
        }

        let item = LibraryItem(
            imageFilename: filename,
            isGeneratedReference: isGeneratedReference,
            poseIdea: poseIdea,
            zoomFactor: zoomFactor,
            overlayModeRaw: overlayModeRaw,
            rollDegrees: rollDegrees
        )
        items.insert(item, at: 0)
        persist()
    }

    func image(for item: LibraryItem) -> UIImage? {
        let url = libraryDirectory.appendingPathComponent(item.imageFilename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func deleteItems(ids: Set<UUID>) {
        let toDelete = items.filter { ids.contains($0.id) }
        for item in toDelete {
            let url = libraryDirectory.appendingPathComponent(item.imageFilename)
            try? fileManager.removeItem(at: url)
        }
        items.removeAll { ids.contains($0.id) }
        persist()
    }

    func saveToApplePhotos(_ item: LibraryItem) async -> Bool {
        guard let uiImage = image(for: item) else { return false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
            }
            return true
        } catch {
            return false
        }
    }

    func saveVideoToApplePhotos(_ fileURL: URL) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }
            try? FileManager.default.removeItem(at: fileURL)
            return true
        } catch {
            return false
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([LibraryItem].self, from: data) else {
            return
        }
        items = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL)
    }
}
