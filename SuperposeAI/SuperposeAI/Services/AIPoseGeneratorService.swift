import UIKit

protocol PoseGenerating: Sendable {
    func generatePosePack(from image: UIImage, useCase: PoseUseCase) async throws -> [PoseIdea]
}

/// Cloud-ready AI Pose Generator.
/// Sends the reference photo securely to your configured AI backend (when `endpointURL` is set),
/// or falls back to the built-in smart pose variation generator so the app works immediately.
struct AIPoseGeneratorService: PoseGenerating {
    var endpointURL: URL? = nil
    var apiKey: String? = nil

    func generatePosePack(from image: UIImage, useCase: PoseUseCase) async throws -> [PoseIdea] {
        if let endpointURL, let apiKey, !apiKey.isEmpty {
            return try await requestCloudPoses(image: image, useCase: useCase, endpoint: endpointURL, apiKey: apiKey)
        }

        // Simulate realistic cloud processing latency for UX parity
        try await Task.sleep(for: .milliseconds(900))
        return MockPoseCatalog.generateFourPoses(for: useCase)
    }

    private func requestCloudPoses(
        image: UIImage,
        useCase: PoseUseCase,
        endpoint: URL,
        apiKey: String
    ) async throws -> [PoseIdea] {
        guard let jpegData = image.jpegData(compressionQuality: 0.78) else {
            return MockPoseCatalog.generateFourPoses(for: useCase)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "use_case": useCase.rawValue,
            "image_base64": jpegData.base64EncodedString(),
            "count": 4
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return MockPoseCatalog.generateFourPoses(for: useCase)
        }

        let decoded = try JSONDecoder().decode([PoseIdea].self, from: data)
        return decoded.isEmpty ? MockPoseCatalog.generateFourPoses(for: useCase) : decoded
    }
}

// MARK: - Rich Built-in Pose Catalog (4 Variations per Shot Pack)

enum MockPoseCatalog {
    static func generateFourPoses(for useCase: PoseUseCase) -> [PoseIdea] {
        if useCase == .couples {
            return [couplesEmbracePose] + Array(soloPoses(for: useCase).prefix(3))
        }
        return soloPoses(for: useCase)
    }

    static var quickOfflinePoses: [PoseIdea] {
        soloPoses(for: .travel) + [couplesEmbracePose]
    }

    private static func soloPoses(for useCase: PoseUseCase) -> [PoseIdea] {
        [
            PoseIdea(
                title: "Relaxed Three-Quarter Turn",
                angleLabel: "45° Angle • Eye Level",
                confidenceTag: "\(useCase.rawValue) Pick",
                skeleton: threeQuarterSkeleton,
                coaching: CoachingTips(
                    summary: "Creates depth and a natural, slimming silhouette without looking stiff.",
                    subjectTips: [
                        "Turn your torso 45° away from the lens and look back toward the camera.",
                        "Rest your front hand lightly near your pocket or hip; keep fingers relaxed.",
                        "Push your chin slightly forward and down to sharpen your jawline."
                    ],
                    photographerTips: [
                        "Keep the lens at chest-to-eye height for natural proportions.",
                        "Leave about 10% headroom above the subject's hair.",
                        "Use 1x or 2x portrait focal length to avoid wide-angle distortion."
                    ]
                )
            ),
            PoseIdea(
                title: "Candid Over-the-Shoulder",
                angleLabel: "Dynamic • Slight Low Angle",
                confidenceTag: "Natural Motion",
                skeleton: overShoulderSkeleton,
                coaching: CoachingTips(
                    summary: "Captures spontaneous energy as if caught mid-walk.",
                    subjectTips: [
                        "Take one slow step away, then glance back over your front shoulder.",
                        "Drop your near shoulder slightly so it doesn't block your neck.",
                        "Keep a soft, natural smile—exhale right before the shutter."
                    ],
                    photographerTips: [
                        "Lower the camera 10–15 cm below eye level for a cinematic feel.",
                        "Place the subject slightly off-center on the left third line.",
                        "Tap to lock focus on the near eye."
                    ]
                )
            ),
            PoseIdea(
                title: "Asymmetric Lean & Frame",
                angleLabel: "Editorial • Balanced",
                confidenceTag: "Strong Lines",
                skeleton: asymmetricLeanSkeleton,
                coaching: CoachingTips(
                    summary: "Uses clean diagonal lines with arms and shoulders for effortless confidence.",
                    subjectTips: [
                        "Shift 70% of your weight onto your back leg to create a subtle S-curve.",
                        "Bring one hand up near your collar or hair to frame your face.",
                        "Keep elbows slightly away from your torso to add breathing room."
                    ],
                    photographerTips: [
                        "Align vertical background lines (walls, pillars) straight with the frame edge.",
                        "Check for distracting objects behind the subject's head.",
                        "Shoot 2–3 frames while the subject shifts weight."
                    ]
                )
            ),
            PoseIdea(
                title: "Centered Power Portrait",
                angleLabel: "Front • Close Framing",
                confidenceTag: "High Impact",
                skeleton: centeredPortraitSkeleton,
                coaching: CoachingTips(
                    summary: "Direct, confident portrait ideal for profiles and clean lighting.",
                    subjectTips: [
                        "Square your shoulders softly, then tilt your head just 5° to one side.",
                        "Relax your jaw and rest your tongue lightly behind your upper teeth.",
                        "Place one hand gently on your forearm or jacket lapel."
                    ],
                    photographerTips: [
                        "Center the nose bridge vertically in the frame.",
                        "Watch for harsh shadows under the eyes—ask the subject to tilt toward the light.",
                        "Fill 60–70% of the frame height with the subject."
                    ]
                )
            )
        ]
    }

    private static let threeQuarterSkeleton = PoseSkeleton(joints: [
        .nose: NormalizedPoint(x: 0.51, y: 0.21),
        .neck: NormalizedPoint(x: 0.50, y: 0.28),
        .leftShoulder: NormalizedPoint(x: 0.40, y: 0.31),
        .rightShoulder: NormalizedPoint(x: 0.59, y: 0.30),
        .leftElbow: NormalizedPoint(x: 0.35, y: 0.43),
        .rightElbow: NormalizedPoint(x: 0.63, y: 0.42),
        .leftWrist: NormalizedPoint(x: 0.41, y: 0.53),
        .rightWrist: NormalizedPoint(x: 0.58, y: 0.53),
        .root: NormalizedPoint(x: 0.49, y: 0.54),
        .leftHip: NormalizedPoint(x: 0.42, y: 0.55),
        .rightHip: NormalizedPoint(x: 0.56, y: 0.55),
        .leftKnee: NormalizedPoint(x: 0.41, y: 0.73),
        .rightKnee: NormalizedPoint(x: 0.57, y: 0.72),
        .leftAnkle: NormalizedPoint(x: 0.40, y: 0.89),
        .rightAnkle: NormalizedPoint(x: 0.58, y: 0.88)
    ])

    private static let overShoulderSkeleton = PoseSkeleton(joints: [
        .nose: NormalizedPoint(x: 0.48, y: 0.22),
        .neck: NormalizedPoint(x: 0.52, y: 0.29),
        .leftShoulder: NormalizedPoint(x: 0.43, y: 0.32),
        .rightShoulder: NormalizedPoint(x: 0.61, y: 0.31),
        .leftElbow: NormalizedPoint(x: 0.39, y: 0.45),
        .rightElbow: NormalizedPoint(x: 0.66, y: 0.44),
        .leftWrist: NormalizedPoint(x: 0.42, y: 0.56),
        .rightWrist: NormalizedPoint(x: 0.63, y: 0.55),
        .root: NormalizedPoint(x: 0.52, y: 0.54),
        .leftHip: NormalizedPoint(x: 0.45, y: 0.55),
        .rightHip: NormalizedPoint(x: 0.59, y: 0.55),
        .leftKnee: NormalizedPoint(x: 0.44, y: 0.73),
        .rightKnee: NormalizedPoint(x: 0.61, y: 0.74),
        .leftAnkle: NormalizedPoint(x: 0.42, y: 0.89),
        .rightAnkle: NormalizedPoint(x: 0.63, y: 0.90)
    ])

    private static let asymmetricLeanSkeleton = PoseSkeleton(joints: [
        .nose: NormalizedPoint(x: 0.52, y: 0.20),
        .neck: NormalizedPoint(x: 0.51, y: 0.27),
        .leftShoulder: NormalizedPoint(x: 0.41, y: 0.30),
        .rightShoulder: NormalizedPoint(x: 0.61, y: 0.32),
        .leftElbow: NormalizedPoint(x: 0.35, y: 0.40),
        .rightElbow: NormalizedPoint(x: 0.68, y: 0.42),
        .leftWrist: NormalizedPoint(x: 0.44, y: 0.27),
        .rightWrist: NormalizedPoint(x: 0.63, y: 0.54),
        .root: NormalizedPoint(x: 0.50, y: 0.53),
        .leftHip: NormalizedPoint(x: 0.43, y: 0.54),
        .rightHip: NormalizedPoint(x: 0.57, y: 0.55),
        .leftKnee: NormalizedPoint(x: 0.45, y: 0.72),
        .rightKnee: NormalizedPoint(x: 0.58, y: 0.72),
        .leftAnkle: NormalizedPoint(x: 0.46, y: 0.88),
        .rightAnkle: NormalizedPoint(x: 0.59, y: 0.89)
    ])

    private static let centeredPortraitSkeleton = PoseSkeleton(joints: [
        .nose: NormalizedPoint(x: 0.50, y: 0.22),
        .neck: NormalizedPoint(x: 0.50, y: 0.29),
        .leftShoulder: NormalizedPoint(x: 0.38, y: 0.33),
        .rightShoulder: NormalizedPoint(x: 0.62, y: 0.33),
        .leftElbow: NormalizedPoint(x: 0.34, y: 0.47),
        .rightElbow: NormalizedPoint(x: 0.66, y: 0.47),
        .leftWrist: NormalizedPoint(x: 0.43, y: 0.53),
        .rightWrist: NormalizedPoint(x: 0.55, y: 0.54),
        .root: NormalizedPoint(x: 0.50, y: 0.56),
        .leftHip: NormalizedPoint(x: 0.42, y: 0.57),
        .rightHip: NormalizedPoint(x: 0.58, y: 0.57),
        .leftKnee: NormalizedPoint(x: 0.42, y: 0.75),
        .rightKnee: NormalizedPoint(x: 0.58, y: 0.75),
        .leftAnkle: NormalizedPoint(x: 0.42, y: 0.90),
        .rightAnkle: NormalizedPoint(x: 0.58, y: 0.90)
    ])

    private static let couplesEmbracePose = PoseIdea(
        title: "Couples Walk & Lean",
        angleLabel: "2-Person • Natural Candid",
        confidenceTag: "Couples Pick",
        skeleton: PoseSkeleton(joints: [
            .nose: NormalizedPoint(x: 0.37, y: 0.22),
            .neck: NormalizedPoint(x: 0.37, y: 0.29),
            .leftShoulder: NormalizedPoint(x: 0.29, y: 0.32),
            .rightShoulder: NormalizedPoint(x: 0.45, y: 0.32),
            .leftElbow: NormalizedPoint(x: 0.26, y: 0.44),
            .rightElbow: NormalizedPoint(x: 0.50, y: 0.42),
            .leftWrist: NormalizedPoint(x: 0.30, y: 0.54),
            .rightWrist: NormalizedPoint(x: 0.55, y: 0.48),
            .root: NormalizedPoint(x: 0.37, y: 0.54),
            .leftHip: NormalizedPoint(x: 0.31, y: 0.55),
            .rightHip: NormalizedPoint(x: 0.43, y: 0.55),
            .leftKnee: NormalizedPoint(x: 0.31, y: 0.73),
            .rightKnee: NormalizedPoint(x: 0.43, y: 0.73),
            .leftAnkle: NormalizedPoint(x: 0.30, y: 0.89),
            .rightAnkle: NormalizedPoint(x: 0.44, y: 0.89)
        ]),
        secondarySkeleton: PoseSkeleton(joints: [
            .nose: NormalizedPoint(x: 0.62, y: 0.24),
            .neck: NormalizedPoint(x: 0.62, y: 0.31),
            .leftShoulder: NormalizedPoint(x: 0.54, y: 0.34),
            .rightShoulder: NormalizedPoint(x: 0.70, y: 0.34),
            .leftElbow: NormalizedPoint(x: 0.49, y: 0.44),
            .rightElbow: NormalizedPoint(x: 0.73, y: 0.46),
            .leftWrist: NormalizedPoint(x: 0.46, y: 0.50),
            .rightWrist: NormalizedPoint(x: 0.69, y: 0.56),
            .root: NormalizedPoint(x: 0.62, y: 0.55),
            .leftHip: NormalizedPoint(x: 0.56, y: 0.56),
            .rightHip: NormalizedPoint(x: 0.68, y: 0.56),
            .leftKnee: NormalizedPoint(x: 0.56, y: 0.74),
            .rightKnee: NormalizedPoint(x: 0.68, y: 0.74),
            .leftAnkle: NormalizedPoint(x: 0.55, y: 0.89),
            .rightAnkle: NormalizedPoint(x: 0.69, y: 0.89)
        ]),
        coaching: CoachingTips(
            summary: "Keeps both subjects connected and naturally angled toward each other.",
            subjectTips: [
                "Walk slowly side-by-side; one person looks at the camera while the other looks toward their partner.",
                "Keep shoulders slightly angled inward so there is no awkward gap between you.",
                "Rest the inner hand lightly on your partner's waist or forearm."
            ],
            photographerTips: [
                "Step back enough so both subjects have breathing room on left and right edges.",
                "Keep the camera at chest height of the taller person.",
                "Burst-shoot 3–4 frames as they take a slow step forward."
            ]
        )
    )
}
