import Testing
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
}
