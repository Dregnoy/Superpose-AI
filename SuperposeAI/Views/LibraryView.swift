import SwiftUI
import CoreImage
import Photos
import PhotosUI

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @Environment(LibraryStore.self) private var libraryStore

    enum LibraryFilter: String, CaseIterable, Identifiable {
        case all = "Tümü"
        case bestShots = "En İyiler"
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

    private static let sharedCIContext = PhotoEnhancerService.context

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
                        if ShootingMetricsStore.shared.totalShotsCaptured > 0 {
                            shootingScorecard
                                .padding(.horizontal)
                                .padding(.top, 6)
                        }

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
                            case .all:
                                return libraryStore.items
                            case .bestShots:
                                return libraryStore.items
                                    .filter { ($0.qualityScore ?? 0) >= 75 }
                                    .sorted { ($0.qualityScore ?? 0) > ($1.qualityScore ?? 0) }
                            case .posed:
                                return libraryStore.items.filter { $0.poseIdea != nil }
                            case .favorites:
                                return libraryStore.items.filter { $0.isFavorite }
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

            if let score = item.qualityScore {
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 3) {
                            if score >= 75 {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            Text(score >= 75 ? "En İyi %\(Int(score.rounded()))" : "%\(Int(score.rounded()))")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(score >= 75 ? Color.yellow.opacity(0.92) : Color.black.opacity(0.65))
                        )
                        .foregroundStyle(score >= 75 ? .black : .white)
                        .padding(5)
                        Spacer()
                    }
                }
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
        var scored: [(LibraryItem, Double)] = []
        for (item, image) in candidates {
            let breakdown = await vision.evaluateShotQuality(image: image, targetPose: item.poseIdea)
            libraryStore.updateQualityScore(id: item.id, score: breakdown.totalScore)
            scored.append((item, breakdown.totalScore))
        }

        guard let best = scored.max(by: { $0.1 < $1.1 }) else { return }
        let winner = best.0

        if !winner.isFavorite {
            libraryStore.toggleFavorite(id: winner.id)
        }
        selectedIDs.removeAll()
        isMultiSelectMode = false
        viewingItem = libraryStore.items.first(where: { $0.id == winner.id }) ?? winner
        poseExtractAlert = "En net, keskin ve uyumlu kare favori olarak seçildi (Skor: %\(Int(best.1.rounded())))."
    }

    private var shootingScorecard: some View {
        let metrics = ShootingMetricsStore.shared
        return HStack(spacing: 10) {
            scorecardCell(title: "Çekim", value: "\(metrics.totalShotsCaptured)")
            scorecardCell(title: "Ort. Estetik", value: String(format: "%.1f", metrics.averageAestheticScore / 10.0))
            scorecardCell(title: "Poz Uyumu", value: "\(metrics.poseMatchesAchieved)")
            scorecardCell(title: "Paylaşım", value: "\(metrics.totalShares)")
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func scorecardCell(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.cyan)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
