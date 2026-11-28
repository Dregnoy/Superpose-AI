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
        let poses = try await service.generatePosePack(
            from: nil,
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
        let savedID = store.saveCapturedPhoto(img)
        #expect(store.items.count == initialCount + 1)
        store.updateQualityScore(id: savedID, score: 88.5)
        #expect(store.items.first(where: { $0.id == savedID })?.qualityScore == 88.5)
        if let created = store.items.first {
            store.toggleFavorite(id: created.id)
            #expect(store.items.first?.isFavorite == true)
            store.deleteItems(ids: [created.id])
            #expect(store.items.count == initialCount)
        }
    }

    @Test("PoseVisionService sharpness score distinguishes flat and detailed images")
    func sharpnessScoring() throws {
        let flatRenderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let flatImg = flatRenderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let sharpImg = flatRenderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            UIColor.white.setFill()
            for y in stride(from: 0, to: 64, by: 8) {
                for x in stride(from: 0, to: 64, by: 8) {
                    if ((x + y) / 8) % 2 == 0 {
                        ctx.fill(CGRect(x: x, y: y, width: 8, height: 8))
                    }
                }
            }
        }
        let flatCG = try #require(flatImg.cgImage)
        let sharpCG = try #require(sharpImg.cgImage)
        let flatScore = PoseVisionService.computeSharpnessScore(cgImage: flatCG)
        let sharpScore = PoseVisionService.computeSharpnessScore(cgImage: sharpCG)
        #expect(flatScore >= 0.0 && flatScore <= 1.0)
        #expect(sharpScore > flatScore)
    }

    @Test("PhotoEnhancerService fuseExposureBracket preserves dimensions and handles invalid RAW")
    func exposureBracketAndRawFallback() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48))
        let dark = renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
        }
        let mid = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
        }
        let bright = renderer.image { ctx in
            UIColor.lightGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
        }
        let fused = PhotoEnhancerService.fuseExposureBracket([dark, mid, bright])
        #expect(fused.size.width == 48)
        #expect(fused.size.height == 48)
        #expect(PhotoEnhancerService.developRAW(Data()) == nil)
    }

    @Test("PhotoEnhancerService applyLook preserves dimensions across all presets")
    func photoLookPresets() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        let sample = renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        for preset in PhotoLookPreset.allCases {
            let styled = PhotoEnhancerService.applyLook(preset, to: sample)
            #expect(styled.size.width == 40)
            #expect(styled.size.height == 40)
        }
        #expect(PhotoLookPreset.natural.next == .cinematic)
    }

    @Test("PoseVisionService evaluateCouplesBalance detects wide horizontal gap")
    func multiPersonSpacingHint() {
        let leftPerson = PoseSkeleton(joints: [
            .neck: NormalizedPoint(x: 0.12, y: 0.30),
            .root: NormalizedPoint(x: 0.12, y: 0.60)
        ])
        let rightPerson = PoseSkeleton(joints: [
            .neck: NormalizedPoint(x: 0.88, y: 0.30),
            .root: NormalizedPoint(x: 0.88, y: 0.60)
        ])
        let hint = PoseVisionService.evaluateCouplesBalance(first: leftPerson, second: rightPerson)
        #expect(hint?.contains("birbirinize") == true)
    }

    @Test("AestheticScoringService and One-Tap Magic preserve valid ranges and dimensions")
    func aestheticAndOneTapMagic() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let sample = renderer.image { ctx in
            UIColor.systemGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let magic = PhotoEnhancerService.applyOneTapMagic(sample, lumaHint: 0.30)
        #expect(magic.size.width == 64)
        #expect(magic.size.height == 64)

        let report = AestheticScoringService.evaluate(image: magic, poseMatchScore: 88, subjectCenter: CGPoint(x: 0.33, y: 0.33))
        #expect(report.overallScore >= 0 && report.overallScore <= 100)
        #expect(report.outOfTenText.contains("/10"))

        let storyCard = ShareCardRenderer.renderStoryCard(photo: magic, aestheticReport: report, poseTitle: "Test Pozu")
        #expect(storyCard.size.width == 1080)
        #expect(storyCard.size.height == 1920)
    }
}
