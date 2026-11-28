import Testing
import AVFoundation
import Foundation
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
        #expect(service.flashMode == .off)

        service.toggleFlash()
        #expect(service.flashMode == .on)
        service.toggleFlash()
        #expect(service.flashMode == .off)

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
}
