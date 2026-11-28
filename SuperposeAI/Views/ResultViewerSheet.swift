import SwiftUI
import CoreImage
import Photos

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
        case square1x1 = "1:1"
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
    @State private var manualTiltDegrees: Double = 0.0
    @State private var exposureAdjust: Double = 0.0
    @State private var warmthAdjust: Double = 0.0
    @State private var enhancedCache: UIImage?
    @State private var isMagicApplied = false
    @State private var magicCache: UIImage?
    @State private var isStudioRelight = false
    @State private var relightCache: UIImage?
    @State private var aestheticReport: AestheticScoreReport?

    private static let sharedCIContext = PhotoEnhancerService.context

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
                    HStack(spacing: 8) {
                        Button {
                            if !isMagicApplied, magicCache == nil, let original = libraryStore.image(for: item) {
                                magicCache = PhotoEnhancerService.applyOneTapMagic(original)
                            }
                            isMagicApplied.toggle()
                        } label: {
                            Label(isMagicApplied ? "Sihir Uygulandı" : "Tek Dokunuşla Sihir", systemImage: "wand.and.stars")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(isMagicApplied ? Color.cyan : Color.yellow, in: Capsule())
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)

                        if let report = aestheticReport {
                            Label(
                                "\(report.usedCoreMLModel ? "CoreML Estetik" : "Estetik") \(report.outOfTenText) • \(report.verdict)",
                                systemImage: report.usedCoreMLModel ? "cpu" : "sparkles"
                            )
                                .font(.caption2.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial, in: Capsule())
                                .foregroundStyle(.cyan)
                        }
                    }

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

                    Toggle("Sanal Stüdyo Işığı (Özne Aydınlat)", isOn: $isStudioRelight)
                        .font(.subheadline)
                        .tint(.yellow)
                        .onChange(of: isStudioRelight) { _, enabled in
                            guard enabled, relightCache == nil,
                                  let original = libraryStore.image(for: item) else { return }
                            Task {
                                relightCache = await PoseVisionService.applyStudioRelight(to: original)
                            }
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

                    DisclosureGroup("İnce Ayar (Işık / Sıcaklık / Eğim)") {
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
                            HStack(spacing: 8) {
                                Text("Eğim")
                                    .font(.caption2.bold())
                                    .frame(width: 54, alignment: .leading)
                                Slider(value: $manualTiltDegrees, in: -15...15, step: 0.5)
                                    .tint(.green)
                                Button(String(format: "%.0f°", manualTiltDegrees)) {
                                    manualTiltDegrees = 0
                                }
                                .font(.caption2.monospacedDigit().bold())
                                .foregroundStyle(.green)
                                .frame(width: 34, alignment: .trailing)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption.bold())
                    .tint(.cyan)
                }
                .padding(.horizontal)

                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Button {
                            dismiss()
                            appState.reshotFromLibrary(item)
                        } label: {
                            Label("Tekrar Çek", systemImage: "camera.rotate")
                                .font(.subheadline.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
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
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(savedToPhotos ? Color.green.opacity(0.35) : Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            if let img = libraryStore.image(for: item) {
                                dismiss()
                                appState.startGhostReference(img, item: item)
                            }
                        } label: {
                            Label("Hayalet", systemImage: "person.fill.viewfinder")
                                .font(.caption.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }

                        if let shareImage = buildShareImage() {
                            ShareLink(
                                item: Image(uiImage: shareImage),
                                preview: SharePreview("Superpose Çekimi", image: Image(uiImage: shareImage))
                            ) {
                                Label(hasBeforePhoto ? "Önce/Sonra" : "Paylaş", systemImage: "square.and.arrow.up")
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(.white)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                ShootingMetricsStore.shared.recordShare()
                            })
                        }

                        if let storyCard = buildStoryCardImage() {
                            ShareLink(
                                item: Image(uiImage: storyCard),
                                preview: SharePreview("Superpose Hikâye Kartı", image: Image(uiImage: storyCard))
                            ) {
                                Label("Kart", systemImage: "rectangle.portrait.on.rectangle.portrait.angled")
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(Color.purple.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(.white)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                ShootingMetricsStore.shared.recordShare()
                            })
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
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                enhancedCache = nil
                magicCache = nil
                relightCache = nil
                bokehBaseImage = nil
                isApplyingBokeh = false
            }
            .task {
                if aestheticReport == nil, let img = libraryStore.image(for: item) {
                    aestheticReport = AestheticScoringService.evaluate(image: img)
                }
            }
        }
    }

    private var hasBeforePhoto: Bool {
        libraryStore.items.count > 1
    }

    @MainActor
    private func buildStoryCardImage() -> UIImage? {
        guard let photo = styledImage() else { return nil }
        return ShareCardRenderer.renderStoryCard(
            photo: photo,
            aestheticReport: aestheticReport,
            poseTitle: item.poseIdea?.title
        )
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
        if isStudioRelight, let relit = relightCache {
            baseImage = relit
        }
        if isMagicApplied {
            baseImage = magicCache ?? baseImage.map { PhotoEnhancerService.applyOneTapMagic($0) }
        } else if isNaturalEnhanced {
            baseImage = enhancedCache ?? baseImage.map { PhotoEnhancerService.naturalizeAndSharpen($0) }
        }
        guard let base = baseImage else { return nil }
        let totalTilt = (isHorizonStraightened ? (item.rollDegrees ?? 0) : 0) + manualTiltDegrees
        let straightenedBase = abs(totalTilt) > 0.1
            ? straightenHorizon(base, rollDegrees: totalTilt)
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
        case .square1x1: targetAspect = 1.0
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
        await LibraryStore.saveImageToApplePhotos(image)
    }
}
