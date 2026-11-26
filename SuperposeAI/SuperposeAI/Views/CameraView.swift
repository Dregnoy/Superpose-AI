import SwiftUI
import AVFoundation
import PhotosUI

struct CameraView: View {
    @Environment(AppState.self) private var appState
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(ShotPackStore.self) private var shotPackStore

    @State private var cameraService = CameraService()
    @State private var visionService = PoseVisionService()
    @State private var voiceCoach = VoiceCoachService()
    @State private var horizonService = HorizonLevelService()
    @State private var isGeneratingPoses = false
    @State private var toastMessage: String?
    @State private var showNoPacksAlert = false
    @State private var autoShutterCountdown: Int?
    @State private var autoShutterTask: Task<Void, Never>?
    @State private var selectedInspoItem: PhotosPickerItem?
    @State private var timerSeconds: Int = 0 // 0, 3, or 10
    @State private var isBurstEnabled: Bool = false
    @State private var focusPoint: CGPoint?
    @State private var exposureBias: Float = 0.0
    @State private var previewingLatestItem: LibraryItem?

    private let poseGenerator = AIPoseGeneratorService()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraService.authorizationStatus == .authorized {
                GeometryReader { geo in
                    CameraPreviewRepresentable(session: cameraService.session)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let normalized = CGPoint(
                                x: max(0, min(1, location.y / geo.size.height)),
                                y: max(0, min(1, 1.0 - (location.x / geo.size.width)))
                            )
                            cameraService.focusAndExpose(at: normalized)
                            focusPoint = location
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                if focusPoint == location { focusPoint = nil }
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 12)
                                .onChanged { value in
                                    guard focusPoint != nil else { return }
                                    let delta = Float(-value.translation.height / 120.0)
                                    let clamped = max(-2.0, min(2.0, delta))
                                    exposureBias = clamped
                                    cameraService.setExposureBias(clamped)
                                }
                        )
                }
                .ignoresSafeArea()
            } else {
                cameraPermissionPlaceholder
            }

            // Focus Reticle
            if let focusPoint {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.yellow, lineWidth: 1.5)
                        .frame(width: 64, height: 64)
                    Image(systemName: "sun.max.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
                .position(focusPoint)
                .allowsHitTesting(false)
            }

            // Optional Rule of Thirds Grid + Subtle Horizon Level
            if appState.isGridEnabled {
                ZStack {
                    RuleOfThirdsGridView()
                    HorizonLevelIndicatorView(
                        rollDegrees: horizonService.rollDegrees,
                        isLevel: horizonService.isLevel
                    )
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // Pose Outline Overlay
            if let pinned = appState.pinnedPose {
                PoseOverlayView(
                    targetSkeleton: pinned.skeleton,
                    secondaryTargetSkeleton: pinned.secondarySkeleton,
                    liveSkeleton: visionService.guidance.detectedSkeleton,
                    liveSecondarySkeleton: visionService.guidance.detectedSecondarySkeleton,
                    ghostMaskImage: appState.pinnedGhostMask,
                    mode: appState.overlayMode,
                    matchScore: visionService.guidance.poseMatchScore
                )
            }

            // Top & Bottom HUD
            VStack {
                topGuidanceHUD
                Spacer()
                if let toastMessage {
                    Text(toastMessage)
                        .font(.caption.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 8)
                }
                bottomControlsHUD
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if isGeneratingPoses {
                generatingOverlay
            }
        }
        .task {
            horizonService.start()
            let granted = await cameraService.checkAndRequestPermission()
            if granted {
                cameraService.onVideoFrame = { buffer in
                    visionService.analyzeFrame(buffer, targetPose: appState.pinnedPose)
                }
                cameraService.startSession()
            }
        }
        .onChange(of: visionService.guidance) { _, newGuidance in
            voiceCoach.announceIfNeeded(
                newGuidance,
                isEnabled: appState.isVoiceCoachEnabled,
                hasPinnedPose: appState.pinnedPose != nil
            )
            evaluateAutoShutter(with: newGuidance)
        }
        .onDisappear {
            autoShutterTask?.cancel()
            voiceCoach.stop()
            horizonService.stop()
            cameraService.stopSession()
        }
        .onChange(of: selectedInspoItem) { _, newItem in
            guard let newItem else { return }
            Task { await importInspoPose(from: newItem) }
        }
        .sheet(item: $previewingLatestItem) { item in
            ResultViewerSheet(item: item)
        }
        .alert("Out of Shot Packs", isPresented: $showNoPacksAlert) {
            Button("Get Shot Packs") {
                appState.selectedTab = .shotPacks
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You've used today's free Shot Pack. Pick up a one-time Starter or Value Pack anytime—no subscription required.")
        }
    }

    // MARK: - Top Real-Time Guidance HUD

    private var topGuidanceHUD: some View {
        VStack(spacing: 8) {
            HStack {
                // Lighting Status
                Label(visionService.guidance.lighting.message, systemImage: visionService.guidance.lighting.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(visionService.guidance.lighting.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())

                Spacer()

                // Framing Status
                Text(visionService.guidance.framing.message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(visionService.guidance.framing.isOptimal ? .green : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            HStack {
                HStack(spacing: 8) {
                    Button {
                        cameraService.toggleFlash()
                    } label: {
                        Image(systemName: cameraService.flashMode == .on ? "bolt.fill" : "bolt.slash")
                            .font(.subheadline)
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Button {
                        appState.isVoiceCoachEnabled.toggle()
                        if !appState.isVoiceCoachEnabled { voiceCoach.stop() }
                    } label: {
                        Image(systemName: appState.isVoiceCoachEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                            .font(.subheadline)
                            .foregroundStyle(appState.isVoiceCoachEnabled ? .cyan : .white)
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Button {
                        appState.isAutoShutterEnabled.toggle()
                        if !appState.isAutoShutterEnabled {
                            autoShutterTask?.cancel()
                            autoShutterCountdown = nil
                        }
                    } label: {
                        Text("AUTO")
                            .font(.caption2.bold())
                            .foregroundStyle(appState.isAutoShutterEnabled ? .black : .white)
                            .padding(.horizontal, 9)
                            .frame(height: 34)
                            .background(appState.isAutoShutterEnabled ? AnyShapeStyle(Color.cyan) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                    }

                    Button {
                        appState.isGridEnabled.toggle()
                    } label: {
                        Image(systemName: "grid")
                            .font(.subheadline)
                            .foregroundStyle(appState.isGridEnabled ? .cyan : .white)
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Button {
                        timerSeconds = (timerSeconds == 0) ? 3 : (timerSeconds == 3 ? 10 : 0)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "timer")
                            if timerSeconds > 0 {
                                Text("\(timerSeconds)s")
                            }
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(timerSeconds > 0 ? .black : .white)
                        .padding(.horizontal, timerSeconds > 0 ? 8 : 0)
                        .frame(minWidth: 34, minheight: 34)
                        .background(timerSeconds > 0 ? AnyShapeStyle(Color.cyan) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                    }

                    Button {
                        isBurstEnabled.toggle()
                    } label: {
                        Image(systemName: "square.stack.3d.down.right")
                            .font(.subheadline)
                            .foregroundStyle(isBurstEnabled ? .black : .white)
                            .frame(width: 34, height: 34)
                            .background(isBurstEnabled ? AnyShapeStyle(Color.cyan) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
                    }
                }

                Spacer()

                if let pinned = appState.pinnedPose {
                    HStack(spacing: 8) {
                        Text(pinned.title)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Button {
                            appState.coachingPose = pinned
                        } label: {
                            Text("Coach")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.cyan, in: Capsule())
                                .foregroundStyle(.black)
                        }
                        Button {
                            appState.pinnedPose = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                } else {
                    HStack(spacing: 6) {
                        Button {
                            appState.latestGeneratedPoses = MockPoseCatalog.quickOfflinePoses
                            appState.isResultsSheetPresented = true
                        } label: {
                            Label("Quick", systemImage: "figure.stand")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial, in: Capsule())
                        }

                        PhotosPicker(selection: $selectedInspoItem, matching: .images) {
                            Label("Inspo", systemImage: "photo.badge.plus")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }

                Spacer()

                // Overlay Mode Switcher
                Button {
                    cycleOverlayMode()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.overlayMode.icon)
                        Text(appState.overlayMode.rawValue)
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
    }

    // MARK: - Bottom Camera Controls

    private var bottomControlsHUD: some View {
        VStack(spacing: 12) {
            if cameraService.cameraPosition == .back {
                HStack(spacing: 8) {
                    ForEach([CGFloat(1.0), CGFloat(2.0)], id: \.self) { factor in
                        Button {
                            cameraService.setZoom(factor)
                        } label: {
                            Text("\(Int(factor))x")
                                .font(.caption2.bold())
                                .frame(width: 32, height: 32)
                                .background(
                                    cameraService.zoomFactor == factor
                                        ? AnyShapeStyle(Color.cyan)
                                        : AnyShapeStyle(.ultraThinMaterial),
                                    in: Circle()
                                )
                                .foregroundStyle(cameraService.zoomFactor == factor ? .black : .white)
                        }
                    }
                }
            }

            HStack(spacing: 24) {
                // Generate AI Poses Button
                Button {
                    Task { await captureAndGeneratePoses() }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .frame(width: 48, height: 48)
                            .background(Color.cyan.opacity(0.22), in: Circle())
                            .overlay(Circle().stroke(Color.cyan, lineWidth: 1.5))
                        Text("AI Poses (\(shotPackStore.totalPacksAvailable))")
                            .font(.caption2.bold())
                    }
                }
                .foregroundStyle(.white)

                // Standard Shutter Button (shows 3-2-1 ring for Auto-Shutter or Timer)
                Button {
                    if autoShutterTask != nil {
                        autoShutterTask?.cancel()
                        autoShutterTask = nil
                        autoShutterCountdown = nil
                    } else if timerSeconds > 0 {
                        startManualTimerCapture(seconds: timerSeconds)
                    } else {
                        Task { await captureAndSavePhoto() }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(autoShutterCountdown != nil ? Color.cyan : Color.white, lineWidth: 4)
                            .frame(width: 74, height: 74)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 60, height: 60)
                        if let count = autoShutterCountdown {
                            Text("\(count)")
                                .font(.title2.bold())
                                .foregroundStyle(.black)
                        }
                    }
                }

                // Flip Camera & Last Shot Pill
                HStack(spacing: 12) {
                    Button {
                        cameraService.toggleCamera()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.title3)
                                .frame(width: 48, height: 48)
                                .background(.ultraThinMaterial, in: Circle())
                            Text("Flip")
                                .font(.caption2.bold())
                        }
                    }
                    .foregroundStyle(.white)

                    if let latest = libraryStore.items.first,
                       let thumb = libraryStore.image(for: latest) {
                        Button {
                            previewingLatestItem = latest
                        } label: {
                            VStack(spacing: 4) {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 46, height: 46)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.5))
                                Text("Last")
                                    .font(.caption2.bold())
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var cameraPermissionPlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Camera Access Required")
                .font(.headline)
            Text("Enable camera access in Settings to use live lighting, framing, and pose outline overlays.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var generatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(.cyan)
                Text("Generating 4 Pose Ideas…")
                    .font(.headline)
                Text("Analyzing body language, angles & framing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Actions

    private func cycleOverlayMode() {
        let all = OverlayMode.allCases
        if let idx = all.firstIndex(of: appState.overlayMode) {
            appState.overlayMode = all[(idx + 1) % all.count]
        }
    }

    private func captureAndSavePhoto() async {
        do {
            if isBurstEnabled {
                var burstFrames: [UIImage] = []
                for idx in 0..<3 {
                    let frame = try await cameraService.capturePhoto()
                    burstFrames.append(frame)
                    if idx < 2 {
                        try? await Task.sleep(for: .milliseconds(160))
                    }
                }
                if let best = await visionService.pickBestShot(from: burstFrames) {
                    libraryStore.saveCapturedPhoto(best, isGeneratedReference: false, poseIdea: appState.pinnedPose)
                    showToast("Best of 3 saved")
                }
            } else {
                let image = try await cameraService.capturePhoto()
                libraryStore.saveCapturedPhoto(image, isGeneratedReference: false, poseIdea: appState.pinnedPose)
                showToast("Saved to Library")
            }
        } catch {
            showToast("Capture failed")
        }
    }

    private func captureAndGeneratePoses() async {
        guard shotPackStore.consumeOnePack() else {
            showNoPacksAlert = true
            return
        }

        isGeneratingPoses = true
        defer { isGeneratingPoses = false }

        do {
            let testImage = try await cameraService.capturePhoto()
            libraryStore.saveCapturedPhoto(testImage, isGeneratedReference: false)
            let poses = try await poseGenerator.generatePosePack(from: testImage, useCase: appState.preferredUseCase)
            appState.latestGeneratedPoses = poses
            appState.isResultsSheetPresented = true
        } catch {
            showToast("Could not generate poses")
        }
    }

    private func showToast(_ text: String) {
        toastMessage = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toastMessage == text { toastMessage = nil }
        }
    }

    private func evaluateAutoShutter(with guidance: LiveGuidanceState) {
        guard appState.isAutoShutterEnabled,
              appState.pinnedPose != nil,
              !isGeneratingPoses else { return }

        let isReady = guidance.lighting == .good
            && guidance.framing == .great
            && (guidance.poseMatchScore ?? 0) >= 85

        if isReady && autoShutterTask == nil {
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()

            autoShutterTask = Task {
                for count in [3, 2, 1] {
                    guard !Task.isCancelled else { return }
                    autoShutterCountdown = count
                    try? await Task.sleep(for: .seconds(1))
                }
                guard !Task.isCancelled else { return }
                autoShutterCountdown = nil
                autoShutterTask = nil
                await captureAndSavePhoto()
            }
        } else if !isReady, autoShutterTask != nil {
            autoShutterTask?.cancel()
            autoShutterTask = nil
            autoShutterCountdown = nil
        }
    }

    private func importInspoPose(from item: PhotosPickerItem) async {
        defer { selectedInspoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data),
              let extracted = await visionService.extractPose(from: uiImage) else {
            showToast("No person detected in photo")
            return
        }
        let mask = await visionService.extractPersonSilhouette(from: uiImage)
        appState.pinPoseAndSwitchToCamera(extracted)
        appState.pinnedGhostMask = mask
        if mask != nil { appState.overlayMode = .ghost }
        showToast("Inspo pose pinned!")
    }

    private func startManualTimerCapture(seconds: Int) {
        autoShutterTask?.cancel()
        autoShutterTask = Task {
            for remaining in stride(from: seconds, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                autoShutterCountdown = remaining
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            autoShutterCountdown = nil
            autoShutterTask = nil
            await captureAndSavePhoto()
        }
    }
}

// MARK: - Subtle Rule of Thirds Grid

struct RuleOfThirdsGridView: View {
    var body: some View {
        Canvas { context, size in
            let lineColor = Color.white.opacity(0.28)
            for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                var vLine = Path()
                vLine.move(to: CGPoint(x: size.width * fraction, y: 0))
                vLine.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                context.stroke(vLine, with: .color(lineColor), lineWidth: 0.75)

                var hLine = Path()
                hLine.move(to: CGPoint(x: 0, y: size.height * fraction))
                hLine.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                context.stroke(hLine, with: .color(lineColor), lineWidth: 0.75)
            }
        }
    }
}

struct HorizonLevelIndicatorView: View {
    let rollDegrees: Double
    let isLevel: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 72, height: 1)

            Rectangle()
                .fill(isLevel ? Color.green : Color.yellow)
                .frame(width: 48, height: isLevel ? 2 : 1.5)
                .rotationEffect(.degrees(-rollDegrees))
        }
    }
}

// MARK: - UIKit AVCaptureVideoPreviewLayer Bridge

struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
