import SwiftUI
import CoreImage
import Photos
import PhotosUI

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @Environment(LibraryStore.self) private var libraryStore

    enum LibraryFilter: String, CaseIterable, Identifiable {
        case all = "Tümü"
        case posed = "Pozlu"
        case favorites = "Favoriler"

        var id: String { rawValue }
    }

    @State private var isMultiSelectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var viewingItem: LibraryItem?
    @State private var libraryFilter: LibraryFilter = .all
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var isExtractingPose = false
    @State private var poseExtractAlert: String?
    @State private var generatedPDFURL: URL?

    private static let sharedCIContext = CIContext()

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
                        Picker("Filtre", selection: $libraryFilter) {
                            ForEach(LibraryFilter.allCases) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.vertical, 6)

                        let displayedItems: [LibraryItem] = {
                            switch libraryFilter {
                            case .all: return libraryStore.items
                            case .posed: return libraryStore.items.filter { $0.poseIdea != nil }
                            case .favorites: return libraryStore.items.filter { $0.isFavorite }
                            }
                        }()

                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(displayedItems) { item in
                                libraryThumbnail(item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Kütüphane")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PhotosPicker(selection: $pickedPhotoItem, matching: .images) {
                        if isExtractingPose {
                            ProgressView()
                        } else {
                            Label("Poz Çıkar", systemImage: "photo.badge.plus")
                        }
                    }
                    .disabled(isExtractingPose)
                }

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
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                Button {
                                    let idsToSave = selectedIDs
                                    Task {
                                        var savedCount = 0
                                        for item in libraryStore.items where idsToSave.contains(item.id) {
                                            if await libraryStore.saveToApplePhotos(item) {
                                                savedCount += 1
                                            }
                                        }
                                        selectedIDs.removeAll()
                                        isMultiSelectMode = false
                                        poseExtractAlert = "\(savedCount) fotoğraf Apple Fotoğraflar'a kaydedildi."
                                    }
                                } label: {
                                    Label("Kaydet (\(selectedIDs.count))", systemImage: "square.and.arrow.down")
                                }

                                if selectedIDs.count >= 2 {
                                    Button {
                                        let idsToPick = selectedIDs
                                        Task { await pickBestFavorite(from: idsToPick) }
                                    } label: {
                                        Label("En İyi", systemImage: "sparkles")
                                    }
                                }

                                if selectedIDs.count == 2 || selectedIDs.count == 4 {
                                    Button {
                                        createCollage(from: selectedIDs)
                                    } label: {
                                        Label("Kolaj", systemImage: "square.grid.2x2")
                                    }
                                }

                                if selectedIDs.count == 2 {
                                    Button {
                                        createDoubleExposure(from: selectedIDs)
                                    } label: {
                                        Label("Çift Poz", systemImage: "circle.lefthalf.filled")
                                    }
                                }

                                Button {
                                    createPDFAlbum(from: selectedIDs)
                                } label: {
                                    Label("PDF", systemImage: "doc.richtext")
                                }

                                Button(role: .destructive) {
                                    libraryStore.deleteItems(ids: selectedIDs)
                                    selectedIDs.removeAll()
                                    isMultiSelectMode = false
                                } label: {
                                    Label("Sil (\(selectedIDs.count))", systemImage: "trash")
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
            }
            .sheet(item: $viewingItem) { item in
                ResultViewerSheet(item: item)
            }
            .onChange(of: pickedPhotoItem) { _, newItem in
                guard let newItem else { return }
                isExtractingPose = true
                Task {
                    defer {
                        isExtractingPose = false
                        pickedPhotoItem = nil
                    }
                    guard let data = try? await newItem.loadTransferable(type: Data.self),
                          let uiImage = UIImage(data: data) else {
                        poseExtractAlert = "Fotoğraf yüklenemedi."
                        return
                    }
                    let vision = PoseVisionService()
                    guard let pose = await vision.extractPose(from: uiImage) else {
                        poseExtractAlert = "Seçilen fotoğrafta kişi algılanamadı."
                        return
                    }
                    let mask = await vision.extractPersonSilhouette(from: uiImage)
                    if !appState.isPoseSaved(pose) {
                        appState.toggleSavePose(pose)
                    }
                    appState.pinnedGhostMask = mask
                    appState.pinPoseAndSwitchToCamera(pose)
                }
            }
            .alert("Fotoğraftan Poz", isPresented: Binding(
                get: { poseExtractAlert != nil },
                set: { if !$0 { poseExtractAlert = nil } }
            )) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(poseExtractAlert ?? "")
            }
            .sheet(isPresented: Binding(
                get: { generatedPDFURL != nil },
                set: { if !$0 { generatedPDFURL = nil } }
            )) {
                if let pdfURL = generatedPDFURL {
                    VStack(spacing: 18) {
                        Image(systemName: "doc.richtext.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.cyan)
                        Text("PDF Albüm Hazır")
                            .font(.headline)
                        ShareLink(item: pdfURL) {
                            Label("PDF Albümü Paylaş / Kaydet", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.black)
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                    .presentationDetents([.height(240)])
                }
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
            } else if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
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

    @MainActor
    private func createCollage(from ids: Set<UUID>) {
        let images = libraryStore.items
            .filter { ids.contains($0.id) }
            .compactMap { libraryStore.image(for: $0) }
        guard images.count == 2 || images.count == 4 else { return }

        let collageView: some View = Group {
            if images.count == 2 {
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { idx in
                        Image(uiImage: images[idx])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 530, height: 1330)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(0..<2, id: \.self) { idx in
                            Image(uiImage: images[idx])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 530, height: 660)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(2..<4, id: \.self) { idx in
                            Image(uiImage: images[idx])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 530, height: 660)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.black)

        let renderer = ImageRenderer(content: collageView)
        renderer.scale = 1.0
        if let collageImage = renderer.uiImage {
            libraryStore.saveCapturedPhoto(collageImage)
            selectedIDs.removeAll()
            isMultiSelectMode = false
            poseExtractAlert = "Kolaj oluşturuldu ve kütüphaneye eklendi."
        }
    }

    @MainActor
    private func createDoubleExposure(from ids: Set<UUID>) {
        let images = libraryStore.items
            .filter { ids.contains($0.id) }
            .compactMap { libraryStore.image(for: $0) }
        guard images.count == 2,
              let cg1 = images[0].cgImage,
              let cg2 = images[1].cgImage else { return }

        let baseCI = CIImage(cgImage: cg1)
        let topRaw = CIImage(cgImage: cg2)
        let scaleX = baseCI.extent.width / max(1, topRaw.extent.width)
        let scaleY = baseCI.extent.height / max(1, topRaw.extent.height)
        let topScaled = topRaw.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let blend = CIFilter(name: "CIScreenBlendMode")
        blend?.setValue(topScaled, forKey: kCIInputImageKey)
        blend?.setValue(baseCI, forKey: kCIInputBackgroundImageKey)

        let context = Self.sharedCIContext
        guard let output = blend?.outputImage,
              let resultCG = context.createCGImage(output, from: baseCI.extent) else { return }

        let blended = UIImage(cgImage: resultCG, scale: images[0].scale, orientation: images[0].imageOrientation)
        libraryStore.saveCapturedPhoto(blended)
        selectedIDs.removeAll()
        isMultiSelectMode = false
        poseExtractAlert = "Çift pozlama fotoğrafı oluşturuldu."
    }

    @MainActor
    private func createPDFAlbum(from ids: Set<UUID>) {
        let images = libraryStore.items
            .filter { ids.contains($0.id) }
            .compactMap { libraryStore.image(for: $0) }
        guard !images.isEmpty else { return }

        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let pdfData = renderer.pdfData { ctx in
            for img in images {
                ctx.beginPage()
                UIColor.black.setFill()
                ctx.fill(pageRect)

                let margin: CGFloat = 32
                let availW = pageRect.width - margin * 2
                let availH = pageRect.height - margin * 2 - 28
                let scale = min(availW / max(1, img.size.width), availH / max(1, img.size.height))
                let drawW = img.size.width * scale
                let drawH = img.size.height * scale
                let drawRect = CGRect(
                    x: (pageRect.width - drawW) / 2,
                    y: margin + (availH - drawH) / 2,
                    width: drawW,
                    height: drawH
                )
                img.draw(in: drawRect)

                let footer: NSString = "SuperposeAI Lookbook"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: UIColor.lightGray
                ]
                footer.draw(at: CGPoint(x: margin, y: pageRect.height - 28), withAttributes: attrs)
            }
        }

        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("SuperposeAI_Album.pdf")
        try? pdfData.write(to: outURL)
        selectedIDs.removeAll()
        isMultiSelectMode = false
        generatedPDFURL = outURL
    }

    @MainActor
    private func pickBestFavorite(from ids: Set<UUID>) async {
        let candidates = libraryStore.items
            .filter { ids.contains($0.id) }
            .compactMap { item in libraryStore.image(for: item).map { (item, $0) } }
        guard candidates.count >= 2 else { return }

        let vision = PoseVisionService()
        guard let bestImage = await vision.pickBestShot(from: candidates.map(\.1)),
              let winner = candidates.first(where: { $0.1 === bestImage })?.0 else {
            return
        }

        if !winner.isFavorite {
            libraryStore.toggleFavorite(id: winner.id)
        }
        selectedIDs.removeAll()
        isMultiSelectMode = false
        viewingItem = winner
        poseExtractAlert = "En net ve en iyi yüz karesi favori olarak seçildi."
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

    enum CropRatio: String, CaseIterable, Identifiable {
        case original = "Tam"
        case feed4x5 = "4:5"
        case story9x16 = "9:16"

        var id: String { rawValue }
    }

    @Environment(AppState.self) private var appState
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(\.dismiss) private var dismiss

    let item: LibraryItem
    @State private var savedToPhotos = false
    @State private var selectedTone: PhotoTone = .original
    @State private var selectedCrop: CropRatio = .original
    @State private var isComparingOriginal = false
    @State private var isSplitCompare = false
    @State private var splitRatio: CGFloat = 0.5
    @State private var isPortraitBokeh = false
    @State private var bokehSigma: Double = 12.0
    @State private var bokehBaseImage: UIImage?
    @State private var isApplyingBokeh = false
    @State private var isNaturalEnhanced = false
    @State private var isHorizonStraightened = false
    @State private var exposureAdjust: Double = 0.0
    @State private var warmthAdjust: Double = 0.0
    @State private var enhancedCache: UIImage?

    private static let sharedCIContext = CIContext()

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if let editedImage = styledImage(),
                   let originalImage = libraryStore.image(for: item) {
                    ZStack(alignment: .topTrailing) {
                        if isSplitCompare {
                            GeometryReader { geo in
                                ZStack {
                                    Image(uiImage: editedImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: geo.size.width, height: geo.size.height)

                                    Image(uiImage: originalImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: geo.size.width, height: geo.size.height)
                                        .mask(
                                            HStack(spacing: 0) {
                                                Rectangle().frame(width: geo.size.width * splitRatio)
                                                Spacer(minLength: 0)
                                            }
                                        )

                                    Rectangle()
                                        .fill(Color.cyan)
                                        .frame(width: 2)
                                        .position(x: geo.size.width * splitRatio, y: geo.size.height / 2)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            splitRatio = max(0.08, min(0.92, value.location.x / max(1, geo.size.width)))
                                        }
                                )
                            }
                            .frame(maxHeight: 340)
                        } else {
                            ZStack(alignment: .topLeading) {
                                Image(uiImage: isComparingOriginal ? originalImage : editedImage)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 16))

                                if isComparingOriginal {
                                    Text("ORİJİNAL")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.black.opacity(0.7), in: Capsule())
                                        .foregroundStyle(.white)
                                        .padding(10)
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in isComparingOriginal = true }
                                    .onEnded { _ in isComparingOriginal = false }
                            )
                        }

                        Button {
                            isSplitCompare.toggle()
                        } label: {
                            Label(isSplitCompare ? "Tek" : "Böl", systemImage: "rectangle.split.2x1")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.65), in: Capsule())
                                .foregroundStyle(isSplitCompare ? .cyan : .white)
                        }
                        .padding(10)
                    }
                    .padding(.horizontal)
                }

                // Minimal 3-tone selector + Shot Summary + AI/CoreImage suggestion
                VStack(spacing: 6) {
                    if let summary = shotSummaryText() {
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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

                    Picker("Oran", selection: $selectedCrop) {
                        ForEach(CropRatio.allCases) { ratio in
                            Text(ratio.rawValue).tag(ratio)
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

                    if let roll = item.rollDegrees, abs(roll) >= 0.8 {
                        Toggle(String(format: "Ufku Düzelt (%.1f°)", abs(roll)), isOn: $isHorizonStraightened)
                            .font(.subheadline)
                            .tint(.cyan)
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

                    DisclosureGroup("İnce Ayar (Işık / Sıcaklık)") {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Text("Işık")
                                    .font(.caption2.bold())
                                    .frame(width: 54, alignment: .leading)
                                Slider(value: $exposureAdjust, in: -0.5...0.5)
                                    .tint(.cyan)
                            }
                            HStack(spacing: 8) {
                                Text("Sıcaklık")
                                    .font(.caption2.bold())
                                    .frame(width: 54, alignment: .leading)
                                Slider(value: $warmthAdjust, in: -1500...1500)
                                    .tint(.orange)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption.bold())
                    .tint(.cyan)
                }
                .padding(.horizontal)

                HStack(spacing: 10) {
                    Button {
                        dismiss()
                        appState.reshotFromLibrary(item)
                    } label: {
                        Label("Tekrar Çek", systemImage: "camera.rotate")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.black)
                    }

                    Button {
                        if let img = libraryStore.image(for: item) {
                            dismiss()
                            appState.startGhostReference(img, item: item)
                        }
                    } label: {
                        Label("Hayalet", systemImage: "person.fill.viewfinder")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
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
                    HStack(spacing: 12) {
                        Button {
                            libraryStore.toggleFavorite(id: item.id)
                        } label: {
                            let isFav = libraryStore.items.first(where: { $0.id == item.id })?.isFavorite ?? item.isFavorite
                            Image(systemName: isFav ? "star.fill" : "star")
                                .foregroundStyle(isFav ? .yellow : .primary)
                        }
                        Button("Bitti") { dismiss() }
                    }
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
        let straightenedBase = (isHorizonStraightened && item.rollDegrees != nil)
            ? straightenHorizon(base, rollDegrees: item.rollDegrees ?? 0)
            : base
        let croppedBase = applyCenterCrop(straightenedBase, ratio: selectedCrop)
        let hasFineTune = abs(exposureAdjust) > 0.01 || abs(warmthAdjust) > 10
        guard (selectedTone != .original || hasFineTune), let cgImage = croppedBase.cgImage else {
            return croppedBase
        }

        let ciImage = CIImage(cgImage: cgImage)
        let context = Self.sharedCIContext
        var currentCI: CIImage = ciImage

        switch selectedTone {
        case .original:
            break
        case .golden:
            let filter = CIFilter(name: "CITemperatureAndTint")
            filter?.setValue(currentCI, forKey: kCIInputImageKey)
            filter?.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            filter?.setValue(CIVector(x: 4700, y: 18), forKey: "inputTargetNeutral")
            if let warmed = filter?.outputImage {
                let vib = CIFilter(name: "CIVibrance")
                vib?.setValue(warmed, forKey: kCIInputImageKey)
                vib?.setValue(0.22, forKey: "inputAmount")
                currentCI = vib?.outputImage ?? warmed
            }
        case .blueHour:
            let filter = CIFilter(name: "CITemperatureAndTint")
            filter?.setValue(currentCI, forKey: kCIInputImageKey)
            filter?.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            filter?.setValue(CIVector(x: 8400, y: -8), forKey: "inputTargetNeutral")
            if let cooled = filter?.outputImage {
                let vib = CIFilter(name: "CIVibrance")
                vib?.setValue(cooled, forKey: kCIInputImageKey)
                vib?.setValue(0.24, forKey: "inputAmount")
                currentCI = vib?.outputImage ?? cooled
            }
        case .dramatic:
            let controls = CIFilter(name: "CIColorControls")
            controls?.setValue(currentCI, forKey: kCIInputImageKey)
            controls?.setValue(1.18, forKey: kCIInputContrastKey)
            controls?.setValue(0.88, forKey: kCIInputSaturationKey)
            if let contrasted = controls?.outputImage {
                let vignette = CIFilter(name: "CIVignette")
                vignette?.setValue(contrasted, forKey: kCIInputImageKey)
                vignette?.setValue(1.1, forKey: kCIInputIntensityKey)
                vignette?.setValue(1.8, forKey: kCIInputRadiusKey)
                currentCI = vignette?.outputImage ?? contrasted
            }
        case .noir:
            let filter = CIFilter(name: "CIPhotoEffectNoir")
            filter?.setValue(currentCI, forKey: kCIInputImageKey)
            if let noirImg = filter?.outputImage { currentCI = noirImg }
        }

        if abs(exposureAdjust) > 0.01 {
            let exp = CIFilter(name: "CIExposureAdjust")
            exp?.setValue(currentCI, forKey: kCIInputImageKey)
            exp?.setValue(exposureAdjust, forKey: kCIInputEVKey)
            if let out = exp?.outputImage { currentCI = out }
        }

        if abs(warmthAdjust) > 10 {
            let temp = CIFilter(name: "CITemperatureAndTint")
            temp?.setValue(currentCI, forKey: kCIInputImageKey)
            temp?.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            temp?.setValue(CIVector(x: 6500 - warmthAdjust, y: 0), forKey: "inputTargetNeutral")
            if let out = temp?.outputImage { currentCI = out }
        }

        guard let finalCG = context.createCGImage(currentCI, from: ciImage.extent) else {
            return croppedBase
        }
        return UIImage(cgImage: finalCG, scale: croppedBase.scale, orientation: croppedBase.imageOrientation)
    }

    private func applyCenterCrop(_ image: UIImage, ratio: CropRatio) -> UIImage {
        let targetAspect: CGFloat
        switch ratio {
        case .original: return image
        case .feed4x5: targetAspect = 4.0 / 5.0
        case .story9x16: targetAspect = 9.0 / 16.0
        }
        guard let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        // Account for orientation when width/height are swapped
        let isRotated = image.imageOrientation == .left || image.imageOrientation == .right ||
                        image.imageOrientation == .leftMirrored || image.imageOrientation == .rightMirrored
        let displayW = isRotated ? height : width
        let displayH = isRotated ? width : height
        let currentAspect = displayW / displayH

        var cropDisplayW = displayW
        var cropDisplayH = displayH
        if currentAspect > targetAspect {
            cropDisplayW = displayH * targetAspect
        } else {
            cropDisplayH = displayW / targetAspect
        }

        let cropPixelW = isRotated ? cropDisplayH : cropDisplayW
        let cropPixelH = isRotated ? cropDisplayW : cropDisplayH
        let rect = CGRect(
            x: (width - cropPixelW) / 2.0,
            y: (height - cropPixelH) / 2.0,
            width: cropPixelW,
            height: cropPixelH
        )
        guard let cropped = cgImage.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    private func straightenHorizon(_ image: UIImage, rollDegrees: Double) -> UIImage {
        let clampedDegrees = max(-15.0, min(15.0, rollDegrees))
        guard abs(clampedDegrees) >= 0.5, let cgImage = image.cgImage else { return image }
        let radians = CGFloat(-clampedDegrees * .pi / 180.0)
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        let rotated = ciImage.transformed(by: CGAffineTransform(rotationAngle: radians))

        // Shrink to largest axis-aligned rect inside rotated bounds to avoid black corners
        let absCos = abs(cos(radians))
        let absSin = abs(sin(radians))
        let safeW = extent.width / (absCos + (extent.height / max(1, extent.width)) * absSin)
        let safeH = extent.height / (absCos + (extent.width / max(1, extent.height)) * absSin)
        let cropRect = CGRect(
            x: rotated.extent.midX - safeW / 2.0,
            y: rotated.extent.midY - safeH / 2.0,
            width: safeW,
            height: safeH
        )
        let context = Self.sharedCIContext
        guard let resultCG = context.createCGImage(rotated, from: cropRect) else { return image }
        return UIImage(cgImage: resultCG, scale: image.scale, orientation: image.imageOrientation)
    }

    private func shotSummaryText() -> String? {
        var parts: [String] = []
        if let zoom = item.zoomFactor {
            parts.append("\(Int(zoom.rounded()))x")
        }
        if let roll = item.rollDegrees {
            parts.append(String(format: "Ufuk %.1f°", abs(roll)))
        }
        if let title = item.poseIdea?.title {
            parts.append("Poz: \(title)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
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
