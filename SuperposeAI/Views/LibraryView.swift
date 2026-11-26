import SwiftUI
import CoreImage
import Photos

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @Environment(LibraryStore.self) private var libraryStore

    @State private var isMultiSelectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var viewingItem: LibraryItem?

    private let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if libraryStore.items.isEmpty {
                    ContentUnavailableView(
                        "Henüz Fotoğraf Yok",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Kamera sekmesinden bir fotoğraf çekin veya AI poz önerileri oluşturun.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(libraryStore.items) { item in
                                libraryThumbnail(item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Kütüphane")
            .toolbar {
                if !libraryStore.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isMultiSelectMode ? "Bitti" : "Seç") {
                            isMultiSelectMode.toggle()
                            if !isMultiSelectMode { selectedIDs.removeAll() }
                        }
                    }
                }

                if isMultiSelectMode && !selectedIDs.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            libraryStore.deleteItems(ids: selectedIDs)
                            selectedIDs.removeAll()
                            isMultiSelectMode = false
                        } label: {
                            Label("Sil (\(selectedIDs.count))", systemImage: "trash")
                        }
                    }
                }
            }
            .sheet(item: $viewingItem) { item in
                ResultViewerSheet(item: item)
            }
        }
    }

    private func libraryThumbnail(_ item: LibraryItem) -> some View {
        let isSelected = selectedIDs.contains(item.id)

        return ZStack(alignment: .topTrailing) {
            if let uiImage = libraryStore.image(for: item) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 130, maxHeight: 130)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 130)
            }

            if isMultiSelectMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .cyan : .white)
                    .padding(6)
                    .shadow(radius: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isMultiSelectMode {
                if isSelected { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
            } else {
                viewingItem = item
            }
        }
    }
}

// MARK: - Result Viewer

struct ResultViewerSheet: View {
    enum PhotoTone: String, CaseIterable, Identifiable {
        case original = "Orijinal"
        case warm = "Sıcak"
        case noir = "Siyah-Beyaz"

        var id: String { rawValue }
    }

    @Environment(AppState.self) private var appState
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(\.dismiss) private var dismiss

    let item: LibraryItem
    @State private var savedToPhotos = false
    @State private var selectedTone: PhotoTone = .original

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if let displayImage = styledImage() {
                    Image(uiImage: displayImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                }

                // Minimal 3-tone selector
                Picker("Tone", selection: $selectedTone) {
                    ForEach(PhotoTone.allCases) { tone in
                        Text(tone.rawValue).tag(tone)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                HStack(spacing: 12) {
                    if let pose = item.poseIdea {
                        Button {
                            dismiss()
                            appState.pinPoseAndSwitchToCamera(pose)
                        } label: {
                            Label("Pozu Eşle", systemImage: "figure.stand")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.black)
                        }
                    }

                    Button {
                        Task {
                            if let img = styledImage() {
                                savedToPhotos = await saveImageToPhotos(img)
                            }
                        }
                    } label: {
                        Label(savedToPhotos ? "Kaydedildi!" : "Kaydet", systemImage: savedToPhotos ? "checkmark" : "square.and.arrow.down")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }

                    if let shareImage = buildShareImage() {
                        ShareLink(
                            item: Image(uiImage: shareImage),
                            preview: SharePreview("Superpose Çekimi", image: Image(uiImage: shareImage))
                        ) {
                            Label(hasBeforePhoto ? "Önce/Sonra" : "Paylaş", systemImage: "square.and.arrow.up")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Fotoğraf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        libraryStore.deleteItems(ids: [item.id])
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
    }

    private var hasBeforePhoto: Bool {
        libraryStore.items.count > 1
    }

    @MainActor
    private func buildShareImage() -> UIImage? {
        guard let afterImage = styledImage() else { return nil }
        guard let beforeItem = libraryStore.items.first(where: { $0.id != item.id }),
              let beforeImage = libraryStore.image(for: beforeItem) else {
            return afterImage
        }

        let card = HStack(spacing: 6) {
            comparisonPane(image: beforeImage, label: "ÖNCE")
            comparisonPane(image: afterImage, label: "SONRA • SUPERPOSE")
        }
        .padding(10)
        .frame(width: 720, height: 900)
        .background(Color.black)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2.0
        return renderer.uiImage ?? afterImage
    }

    private func comparisonPane(image: UIImage, label: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.65), in: Capsule())
                .foregroundStyle(.white)
                .padding(10)
        }
    }

    private func styledImage() -> UIImage? {
        guard let base = libraryStore.image(for: item) else { return nil }
        guard selectedTone != .original, let cgImage = base.cgImage else { return base }

        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        let output: CIImage?

        switch selectedTone {
        case .original:
            return base
        case .warm:
            let filter = CIFilter(name: "CITemperatureAndTint")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            filter?.setValue(CIVector(x: 5200, y: 12), forKey: "inputTargetNeutral")
            output = filter?.outputImage
        case .noir:
            let filter = CIFilter(name: "CIPhotoEffectNoir")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            output = filter?.outputImage
        }

        guard let finalCI = output,
              let finalCG = context.createCGImage(finalCI, from: ciImage.extent) else {
            return base
        }
        return UIImage(cgImage: finalCG, scale: base.scale, orientation: base.imageOrientation)
    }

    private func saveImageToPhotos(_ image: UIImage) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return true
        } catch {
            return false
        }
    }
}
