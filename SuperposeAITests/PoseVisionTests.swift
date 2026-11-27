import Testing
import UIKit
@testable import SuperposeAI

@Suite("Pose Matching & Unlimited Shot Pack Tests")
struct PoseVisionTests {
    @Test("Identical skeletons yield 100% match score")
    func identicalSkeletons() {
        let skeleton = MockPoseCatalog.generateFourPoses(for: .travel).first!.skeleton
        let score = PoseVisionService.computePoseMatchScore(live: skeleton, target: skeleton)
        #expect(score == 100)
    }

    @Test("Scaled and shifted skeleton still matches above 90%")
    func scaleAndTranslationInvariance() {
        let target = MockPoseCatalog.generateFourPoses(for: .travel).first!.skeleton
        var scaledJoints: [BodyJoint: NormalizedPoint] = [:]
        for (joint, pt) in target.joints {
            scaledJoints[joint] = NormalizedPoint(x: pt.x * 0.7 + 0.15, y: pt.y * 0.7 + 0.10)
        }
        let live = PoseSkeleton(joints: scaledJoints)
        let score = PoseVisionService.computePoseMatchScore(live: live, target: target)
        #expect(score >= 95)
    }

    @Test("ShotPackStore allows unlimited free pose generation")
    @MainActor
    func unlimitedGeneration() {
        let store = ShotPackStore()
        #expect(store.isUnlimited == true)
        #expect(store.consumeOnePack() == true)
        #expect(store.consumeOnePack() == true)
    }

    @Test("GridMode includes framing guide and LibraryItem preserves rollDegrees")
    func gridAndHorizonMetadata() {
        #expect(GridMode.allCases.contains(.framing))
        let item = LibraryItem(imageFilename: "test.jpg", isGeneratedReference: false, rollDegrees: 2.5)
        #expect(item.rollDegrees == 2.5)
    }

    @Test("Couples pose swap exchanges primary and secondary skeletons")
    @MainActor
    func couplesSwap() {
        let appState = AppState()
        let first = PoseSkeleton(joints: [.nose: NormalizedPoint(x: 0.3, y: 0.3)])
        let second = PoseSkeleton(joints: [.nose: NormalizedPoint(x: 0.7, y: 0.3)])
        appState.pinnedPose = PoseIdea(
            title: "Çift",
            angleLabel: "Ön",
            confidenceTag: "Test",
            skeleton: first,
            secondarySkeleton: second,
            coaching: CoachingTips(summary: "Özet", subjectTips: [], photographerTips: [])
        )
        appState.swapCouplesPose()
        #expect(appState.pinnedPose?.skeleton.joints[.nose]?.x == 0.7)
        #expect(appState.pinnedPose?.secondarySkeleton?.joints[.nose]?.x == 0.3)
    }

    @Test("AIPoseGeneratorService offline fallback returns 4 valid poses")
    func offlinePoseGeneration() async throws {
        let service = AIPoseGeneratorService()
        let poses = try await service.generatePoses(
            skeleton: nil,
            sceneTags: ["street"],
            lighting: .good,
            useCase: .travel,
            apiKey: ""
        )
        #expect(poses.count == 4)
    }

    @Test("PhotoEnhancerService preserves image dimensions")
    func photoEnhancerDimensions() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let sample = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let enhanced = PhotoEnhancerService.naturalizeAndSharpen(sample)
        #expect(enhanced.size.width == 64)
        #expect(enhanced.size.height == 64)
    }

    @Test("LibraryStore save, toggleFavorite, and delete lifecycle")
    @MainActor
    func libraryLifecycle() {
        let store = LibraryStore()
        let initialCount = store.items.count
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        let img = renderer.image { ctx in
            UIColor.cyan.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        store.saveCapturedPhoto(img)
        #expect(store.items.count == initialCount + 1)
        if let created = store.items.first {
            store.toggleFavorite(id: created.id)
            #expect(store.items.first?.isFavorite == true)
            store.deleteItems(ids: [created.id])
            #expect(store.items.count == initialCount)
        }
    }
}
