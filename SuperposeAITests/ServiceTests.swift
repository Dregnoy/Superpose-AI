import Testing
import AVFoundation
import Foundation
import UIKit
@testable import SuperposeAI

@Suite("Service & State Tests")
struct ServiceTests {

    @Test("ShotPackStore allows unlimited pack consumption")
    @MainActor
    func shotPackStoreUnlimited() {
        let store = ShotPackStore()
        #expect(store.isUnlimited == true)
        #expect(store.consumeOnePack() == true)
    }

    @Test("CameraService toggles flash and camera position")
    @MainActor
    func cameraServiceStateToggles() {
        let service = CameraService()
        #expect(service.cameraPosition == .back)
        #expect(service.flashMode == .auto)

        service.toggleFlash()
        #expect(service.flashMode == .on)
        service.toggleFlash()
        #expect(service.flashMode == .off)
        service.toggleFlash()
        #expect(service.flashMode == .auto)

        service.zoomFactor = 2.0
        service.toggleCamera()
        #expect(service.cameraPosition == .front)
        #expect(service.zoomFactor == 1.0)
    }

    @Test("AppState saves, pins, and switches to camera tab")
    @MainActor
    func appStatePosePinAndSave() {
        let state = AppState()
        let pose = PoseIdea(
            title: "Test Pose",
            angleLabel: "2x",
            confidenceTag: "Test",
            skeleton: PoseSkeleton(joints: [.nose: NormalizedPoint(x: 0.5, y: 0.25)]),
            coaching: CoachingTips(summary: "Test", subjectTips: [], photographerTips: [])
        )

        #expect(state.isPoseSaved(pose) == false)
        state.toggleSavePose(pose)
        #expect(state.isPoseSaved(pose) == true)

        state.pinPoseAndSwitchToCamera(pose)
        #expect(state.pinnedPose?.id == pose.id)
        #expect(state.selectedTab == .camera)
    }

    @Test("LibraryItem decodes cleanly with and without qualityScore")
    func libraryItemBackwardCompatibleDecoding() throws {
        let id = UUID()
        let legacyJSON = """
        {
            "id": "\(id.uuidString)",
            "imageFilename": "legacy.jpg",
            "isGeneratedReference": false,
            "createdAt": 0
        }
        """.data(using: .utf8)!

        let decodedLegacy = try JSONDecoder().decode(LibraryItem.self, from: legacyJSON)
        #expect(decodedLegacy.id == id)
        #expect(decodedLegacy.isFavorite == false)
        #expect(decodedLegacy.qualityScore == nil)

        let scored = LibraryItem(imageFilename: "scored.jpg", isGeneratedReference: false, qualityScore: 91.2)
        let encoded = try JSONEncoder().encode(scored)
        let decodedScored = try JSONDecoder().decode(LibraryItem.self, from: encoded)
        #expect(decodedScored.qualityScore == 91.2)
    }

    @Test("AIPoseGeneratorService returns valid 4-pose packs across all use cases")
    func aiPoseGeneratorAllUseCases() async throws {
        let generator = AIPoseGeneratorService()
        for useCase in PoseUseCase.allCases {
            let poses = try await generator.generatePosePack(
                from: nil,
                sceneTags: ["outdoor", "cafe"],
                lighting: .good,
                useCase: useCase,
                apiKey: ""
            )
            #expect(poses.count == 4)
            #expect(poses.allSatisfy { !$0.title.isEmpty && !$0.skeleton.joints.isEmpty })
        }
    }

    @Test("HorizonLevelService defaults to level and non-shaking")
    @MainActor
    func horizonLevelInitialState() {
        let horizon = HorizonLevelService()
        #expect(horizon.rollDegrees == 0.0)
        #expect(horizon.isShaking == false)
    }

    @Test("AIPoseGeneratorService parses valid and markdown-fenced Gemini JSON responses")
    func geminiResponseParsing() throws {
        let innerJSON = """
        ```json
        {"poses":[{"title":"Kafe Işığı","angleLabel":"2x · Yan","confidenceTag":"Doğal","category":"Kafe","joints":{"nose":{"x":1.2,"y":-0.1},"neck":{"x":0.5,"y":0.28},"leftShoulder":{"x":0.4,"y":0.32},"rightShoulder":{"x":0.6,"y":0.32},"leftElbow":{"x":0.36,"y":0.44},"rightElbow":{"x":0.64,"y":0.44},"root":{"x":0.5,"y":0.55},"leftHip":{"x":0.43,"y":0.56}},"summary":"Sıcak pencere ışığı","subjectTips":["Çeneni hafif kaldır"],"photographerTips":["2x lens kullan"]}]}
        ```
        """
        let envelope: [String: Any] = [
            "candidates": [
                ["content": ["parts": [["text": innerJSON]]]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        let poses = AIPoseGeneratorService.parseGeminiResponse(data)

        #expect(poses.count == 1)
        #expect(poses.first?.title == "Kafe Işığı")
        #expect(poses.first?.category == .cafe)
        #expect(poses.first?.skeleton.joints[.nose]?.x == 0.95)
        #expect(poses.first?.skeleton.joints[.nose]?.y == 0.05)

        let invalid = AIPoseGeneratorService.parseGeminiResponse(Data("not json".utf8))
        #expect(invalid.isEmpty)
    }

    @Test("LiveGuidanceState initializes with haze and lead room defaults")
    func liveGuidanceDefaults() {
        let guidance = LiveGuidanceState()
        #expect(guidance.hazeOrFlareWarning == false)
        #expect(guidance.leadRoomHint == nil)
        #expect(PoseVisionService.leadRoomHint(in: nil) == nil)
    }

    @Test("Core services conform to dependency injection protocols")
    @MainActor
    func serviceProtocolConformances() {
        let camera: any CameraServicing = CameraService()
        let library: any LibraryStoring = LibraryStore()
        let packs: any ShotPackStoring = ShotPackStore()

        #expect(camera.cameraPosition == .back)
        #expect(library.items.count >= 0)
        #expect(packs.consumeOnePack() == true)
    }

    @Test("AIPoseGeneratorService offline rule engine adapts tips to lighting")
    func offlineRuleEngineAdaptsToLighting() {
        let poses = AIPoseGeneratorService.generateOfflinePoses(
            from: nil,
            sceneTags: ["cafe"],
            lighting: .tooDark,
            useCase: .dating
        )
        #expect(poses.count == 4)
        #expect(poses.first?.confidenceTag == "Çevrimdışı AI")
        #expect(poses.first?.coaching.photographerTips.first?.contains("Işık düşük") == true)
    }

    @Test("MockPoseCatalog quickOfflinePoses provides categorized templates")
    func poseTemplateCatalogNonEmpty() {
        let templates = MockPoseCatalog.quickOfflinePoses
        #expect(templates.count >= 4)
        #expect(templates.contains(where: { $0.category == .couples }))
    }

    @Test("ShootingMetricsStore tracks shots, aesthetic average, and shares")
    @MainActor
    func shootingMetricsTracking() throws {
        let suiteName = "com.superposelabs.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let metrics = ShootingMetricsStore(defaults: defaults)

        metrics.recordShot(aestheticScore: 80.0, usedMagic: true, poseMatchScore: 90)
        metrics.recordShot(aestheticScore: 90.0, usedMagic: false, poseMatchScore: 70)
        metrics.recordShare()

        #expect(metrics.totalShotsCaptured == 2)
        #expect(metrics.magicEnhancedShots == 1)
        #expect(metrics.poseMatchesAchieved == 1)
        #expect(metrics.totalShares == 1)
        #expect(metrics.bestAestheticScore == 90.0)
        #expect(metrics.averageAestheticScore == 85.0)

        metrics.reset()
        #expect(metrics.totalShotsCaptured == 0)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("AppState poseMatchThreshold clamps between 65 and 95 and WatchRemoteService initializes")
    @MainActor
    func calibrationAndWatchService() {
        let state = AppState()
        let previous = state.poseMatchThreshold
        state.poseMatchThreshold = 40
        #expect(state.poseMatchThreshold == 65)
        state.poseMatchThreshold = 110
        #expect(state.poseMatchThreshold == 95)
        state.poseMatchThreshold = previous

        let vision = PoseVisionService()
        #expect(!vision.thermalStateLabel.isEmpty)

        let watch = WatchRemoteService()
        #expect(watch.isWatchReachable == false)
    }

    @Test("SharedPoseImportStore saves and consumes shared reference image")
    func sharedPoseImportLifecycle() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        let img = renderer.image { ctx in
            UIColor.systemCyan.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        #expect(SharedPoseImportStore.saveSharedImage(img) == true)
        let consumed = try #require(SharedPoseImportStore.consumeSharedImage())
        #expect(consumed.size.width > 0)
        #expect(SharedPoseImportStore.consumeSharedImage() == nil)
    }

    @Test("LibraryStore encodeHEIFData encodes valid image data")
    @MainActor
    func heifEncodingProducesData() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        let img = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let encoded = try #require(LibraryStore.encodeHEIFData(from: img))
        #expect(!encoded.data.isEmpty)
    }
}
