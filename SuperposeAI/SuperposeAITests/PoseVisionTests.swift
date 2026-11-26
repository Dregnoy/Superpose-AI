import Testing
@testable import SuperposeAI

@Suite("Pose Matching & Shot Pack Tests")
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

    @Test("Daily free Shot Pack resets and consumes properly")
    @MainActor
    func dailyPackConsumption() {
        let store = ShotPackStore()
        store.dailyFreeUsedDate = nil
        store.paidPacksRemaining = 0

        #expect(store.hasDailyFreePack == true)
        #expect(store.consumeOnePack() == true)
        #expect(store.hasDailyFreePack == false)
        #expect(store.consumeOnePack() == false)
    }
}
