import UIKit
import Photos
import UniformTypeIdentifiers

@MainActor
@Observable
final class LibraryStore: LibraryStoring {
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

    @discardableResult
    func saveCapturedPhoto(
        _ image: UIImage,
        isGeneratedReference: Bool = false,
        poseIdea: PoseIdea? = nil,
        zoomFactor: Double? = nil,
        overlayModeRaw: String? = nil,
        rollDegrees: Double? = nil,
        qualityScore: Double? = nil
    ) -> UUID {
        let encoded = Self.encodeHEIFData(from: image)
        let ext = (encoded?.isHEIC == true) ? "heic" : "jpg"
        let filename = "\(UUID().uuidString).\(ext)"
        let fileURL = libraryDirectory.appendingPathComponent(filename)
        if let data = encoded?.data {
            try? data.write(to: fileURL)
        }

        let item = LibraryItem(
            imageFilename: filename,
            isGeneratedReference: isGeneratedReference,
            poseIdea: poseIdea,
            zoomFactor: zoomFactor,
            overlayModeRaw: overlayModeRaw,
            rollDegrees: rollDegrees,
            qualityScore: qualityScore
        )
        items.insert(item, at: 0)
        persist()
        return item.id
    }

    func updateQualityScore(id: UUID, score: Double) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].qualityScore = score
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

    func toggleFavorite(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isFavorite.toggle()
        persist()
    }

    static func encodeHEIFData(from image: UIImage) -> (data: Data, isHEIC: Bool)? {
        if let heic = image.heicData() {
            return (heic, true)
        }
        if let jpeg = image.jpegData(compressionQuality: 0.92) {
            return (jpeg, false)
        }
        return nil
    }

    static func saveImageToApplePhotos(_ image: UIImage) async -> Bool {
        guard let encoded = encodeHEIFData(from: image) else { return false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = encoded.isHEIC ? UTType.heic.identifier : UTType.jpeg.identifier
                request.addResource(with: .photo, data: encoded.data, options: options)
            }
            return true
        } catch {
            return false
        }
    }

    func saveToApplePhotos(_ item: LibraryItem) async -> Bool {
        let fileURL = libraryDirectory.appendingPathComponent(item.imageFilename)
        if let data = try? Data(contentsOf: fileURL) {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { return false }
            let isHEIC = item.imageFilename.lowercased().hasSuffix(".heic")
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.uniformTypeIdentifier = isHEIC ? UTType.heic.identifier : UTType.jpeg.identifier
                    request.addResource(with: .photo, data: data, options: options)
                }
                return true
            } catch {
                return false
            }
        }
        guard let uiImage = image(for: item) else { return false }
        return await Self.saveImageToApplePhotos(uiImage)
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

    func saveRAWToApplePhotos(_ dngData: Data) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: dngData, options: nil)
            }
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
