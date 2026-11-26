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
        case golden = "Altın"
        case blueHour = "Mavi"
        case dramatic = "Dramatik"
        case noir = "S-B"

        var id: String { rawValue }
    }

    @Environment(AppState.self) private var appState
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(\.dismiss) private var dismiss

    let item: LibraryItem
    @State private var savedToPhotos = false
    @State private var selectedTone: PhotoTone = .original
    @State private var isPortraitBokeh = false
    @State private var bokehSigma: Double = 12.0
    @State private var bokehBaseImage: UIImage?
    @State private var isApplyingBokeh = false
    @State private var isNaturalEnhanced = false
    @State private var enhancedCache: UIImage?

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

                // Minimal 3-tone selector + AI/CoreImage suggestion
                VStack(spacing: 6) {
                    if let suggestion = recommendedTone(), suggestion != .original {
                        Text("Önerilen Ton: \(suggestion.rawValue)")
                            .font(.caption2.bold())
                            .foregroundStyle(.cyan)
                    }
                    Picker("Tone", selection: $selectedTone) {
                        ForEach(PhotoTone.allCases) { tone in
                            Text(tone.rawValue).tag(tone)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Doğallaştır ve Netleştir", isOn: $isNaturalEnhanced)
                        .font(.subheadline)
                        .tint(.cyan)
                        .onChange(of: isNaturalEnhanced) { _, enabled in
                            guard enabled, enhancedCache == nil,
                                  let original = libraryStore.image(for: item) else { return }
                            enhancedCache = PhotoEnhancerService.naturalizeAndSharpen(original)
                        }

                    Toggle("Portre Bokeh (Yumuşak Arka Plan)", isOn: $isPortraitBokeh)
                        .font(.subheadline)
                        .tint(.cyan)
                        .onChange(of: isPortraitBokeh) { _, enabled in
                            guard enabled, bokehBaseImage == nil,
                                  let original = libraryStore.image(for: item) else { return }
                            isApplyingBokeh = true
                            Task {
                                bokehBaseImage = await PoseVisionService.applyPortraitBokeh(to: original, blurSigma: bokehSigma)
                                isApplyingBokeh = false
                            }
                        }

                    if isPortraitBokeh {
                        HStack(spacing: 10) {
                            Text("Diyafram")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Slider(value: $bokehSigma, in: 4...22, step: 2, onEditingChanged: { editing in
    guard !editing, let original = libraryStore.image(for: item) else { return }
    isApplyingBokeh = true
    Task {
        bokehBaseImage = await PoseVisionService.applyPortraitBokeh(to: original, blurSigma: bokehSigma)
        isApplyingBokeh = false
    }
})
                            .tint(.cyan)
                            Text(String(format: "f/%.1f", max(1.4, 6.2 - (bokehSigma / 4.5))))
                                .font(.caption2.monospacedDigit().bold())
                                .foregroundStyle(.cyan)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 12) {
                    Button {
                        dismiss()
                        appState.reshotFromLibrary(item)
                    } label: {
                        Label("Tekrar Çek", systemImage: "camera.rotate")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.black)
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
        var baseImage: UIImage? = isPortraitBokeh ? (bokehBaseImage ?? libraryStore.image(for: item)) : libraryStore.image(for: item)
        if isNaturalEnhanced {
            baseImage = enhancedCache ?? baseImage.map { PhotoEnhancerService.naturalizeAndSharpen($0) }
        }
        guard let base = baseImage else { return nil }
        guard selectedTone != .original, let cgImage = base.cgImage else { return base }

        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        let output: CIImage?

        switch selectedTone {
        case .original:
            return base
        case .golden:
            let filter = CIFilter(name: "CITemperatureAndTint")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            filter?.setValue(CIVector(x: 4700, y: 18), forKey: "inputTargetNeutral")
            if let warmed = filter?.outputImage {
                let vib = CIFilter(name: "CIVibrance")
                vib?.setValue(warmed, forKey: kCIInputImageKey)
                vib?.setValue(0.22, forKey: "inputAmount")
                output = vib?.outputImage ?? warmed
            } else {
                output = nil
            }
        case .blueHour:
            let filter = CIFilter(name: "CITemperatureAndTint")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            filter?.setValue(CIVector(x: 8400, y: -8), forKey: "inputTargetNeutral")
            if let cooled = filter?.outputImage {
                let vib = CIFilter(name: "CIVibrance")
                vib?.setValue(cooled, forKey: kCIInputImageKey)
                vib?.setValue(0.24, forKey: "inputAmount")
                output = vib?.outputImage ?? cooled
            } else {
                output = nil
            }
        case .dramatic:
            let controls = CIFilter(name: "CIColorControls")
            controls?.setValue(ciImage, forKey: kCIInputImageKey)
            controls?.setValue(1.18, forKey: kCIInputContrastKey)
            controls?.setValue(0.88, forKey: kCIInputSaturationKey)
            if let contrasted = controls?.outputImage {
                let vignette = CIFilter(name: "CIVignette")
                vignette?.setValue(contrasted, forKey: kCIInputImageKey)
                vignette?.setValue(1.1, forKey: kCIInputIntensityKey)
                vignette?.setValue(1.8, forKey: kCIInputRadiusKey)
                output = vignette?.outputImage ?? contrasted
            } else {
                output = nil
            }
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

    private func recommendedTone() -> PhotoTone? {
        guard let base = libraryStore.image(for: item),
              let cgImage = base.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ]),
        let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(output, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0
        let avg = (r + g + b) / 3.0

        if avg < 0.30 { return .noir }
        if b > r + 0.05 { return .golden }
        return .original
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
