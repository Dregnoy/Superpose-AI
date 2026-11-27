import Foundation
import CoreGraphics
import SwiftUI

// MARK: - Onboarding Focus

enum PoseUseCase: String, CaseIterable, Identifiable, Codable {
    case travel = "Seyahat Çekimleri"
    case couples = "Çift Fotoğrafları"
    case dating = "Profil Fotoğrafı"
    case selfie = "Günlük Selfie"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .travel: return "airplane"
        case .couples: return "heart.fill"
        case .dating: return "sparkles"
        case .selfie: return "person.crop.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .travel: return "Manzaralı kadraj ve doğal tam boy pozlar"
        case .couples: return "Dengeli iki kişilik açılar ve uyum"
        case .dating: return "Özgüvenli, samimi ve doğal portreler"
        case .selfie: return "En iyi yüz açısı, çene ve el duruşu"
        }
    }
}

// MARK: - Overlay Modes

enum OverlayMode: String, CaseIterable, Identifiable {
    case off = "Kapalı"
    case fastSilhouette = "Çizgi"
    case detailedContour = "Kontur"
    case ghost = "Hayalet"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .off: return "eye.slash"
        case .fastSilhouette: return "figure.stand"
        case .detailedContour: return "person.and.background.dotted"
        case .ghost: return "person.fill.viewfinder"
        }
    }
}

enum AspectGuideMode: String, CaseIterable, Identifiable {
    case full = "Tam"
    case feed4x5 = "4:5"
    case story9x16 = "9:16"

    var id: String { rawValue }
}

enum GridMode: String, CaseIterable, Identifiable {
    case off = "Kapalı"
    case ruleOfThirds = "1/3"
    case symmetry = "Simetri"
    case diagonal = "Köşegen"
    case framing = "Çerçeve"

    var id: String { rawValue }
}

// MARK: - Pose Skeleton & Keypoints (Normalized 0...1 in Portrait Camera Space)

enum BodyJoint: String, Codable, CaseIterable, Hashable {
    case nose
    case neck
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case root
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
}

struct NormalizedPoint: Codable, Hashable {
    var x: Double
    var y: Double

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct PoseSkeleton: Codable, Hashable {
    var joints: [BodyJoint: NormalizedPoint]

    static let boneConnections: [(BodyJoint, BodyJoint)] = [
        (.nose, .neck),
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.neck, .root),
        (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
    ]
}

// MARK: - Coaching Tips (Split for Subject & Photographer)

struct CoachingTips: Codable, Hashable {
    let summary: String
    let subjectTips: [String]
    let photographerTips: [String]
}

// MARK: - Pose Categories

enum PoseCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case all = "Tümü"
    case street = "Sokak"
    case cafe = "Kafe"
    case beach = "Sahil"
    case portrait = "Portre"
    case couples = "Çiftler"

    var id: String { rawValue }
}

// MARK: - Pose Idea

struct PoseIdea: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let angleLabel: String
    let confidenceTag: String
    let category: PoseCategory
    let skeleton: PoseSkeleton
    let secondarySkeleton: PoseSkeleton?
    let coaching: CoachingTips
    let previewImageFilename: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        angleLabel: String,
        confidenceTag: String,
        category: PoseCategory = .street,
        skeleton: PoseSkeleton,
        secondarySkeleton: PoseSkeleton? = nil,
        coaching: CoachingTips,
        previewImageFilename: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.angleLabel = angleLabel
        self.confidenceTag = confidenceTag
        self.category = category
        self.skeleton = skeleton
        self.secondarySkeleton = secondarySkeleton
        self.coaching = coaching
        self.previewImageFilename = previewImageFilename
        self.createdAt = createdAt
    }
}

// MARK: - Real-Time On-Device Guidance

enum LightingStatus: Equatable {
    case evaluating
    case good
    case tooDark
    case backlitOrHarsh
    case turnLeftForLight
    case turnRightForLight
    case lowContrast

    var message: String {
        switch self {
        case .evaluating: return "Işık Ölçülüyor…"
        case .good: return "Işık İyi"
        case .tooDark: return "Işık Az"
        case .backlitOrHarsh: return "Ters Işık"
        case .turnLeftForLight: return "Işık Soldan — Sola Dön"
        case .turnRightForLight: return "Işık Sağdan — Sağa Dön"
        case .lowContrast: return "Arka Plan Çok Koyu"
        }
    }

    var color: Color {
        switch self {
        case .evaluating: return .secondary
        case .good: return .green
        case .tooDark, .lowContrast: return .orange
        case .backlitOrHarsh, .turnLeftForLight, .turnRightForLight: return .yellow
        }
    }

    var icon: String {
        switch self {
        case .evaluating: return "sun.min"
        case .good: return "sun.max.fill"
        case .tooDark: return "moon.fill"
        case .backlitOrHarsh: return "sun.haze.fill"
        case .turnLeftForLight: return "arrow.turn.up.left"
        case .turnRightForLight: return "arrow.turn.up.right"
        case .lowContrast: return "circle.lefthalf.filled"
        }
    }
}

enum FramingStatus: Equatable {
    case noSubject
    case tooClose
    case tooFar
    case moveLeft
    case moveRight
    case tiltDown
    case great

    var message: String {
        switch self {
        case .noSubject: return "Kadraja Gir"
        case .tooClose: return "Biraz Geri Çekil"
        case .tooFar: return "Biraz Yaklaş"
        case .moveLeft: return "Sola Kay"
        case .moveRight: return "Sağa Kay"
        case .tiltDown: return "Üst Boşluğu Azalt"
        case .great: return "Harika Kadraj"
        }
    }

    var isOptimal: Bool { self == .great }
}

struct LiveGuidanceState: Equatable {
    var lighting: LightingStatus = .evaluating
    var framing: FramingStatus = .noSubject
    var lumaScore: Double = 0.5
    var poseMatchScore: Int? = nil
    var eyesClosed: Bool = false
    var isGoodSmile: Bool = false
    var backgroundPoleWarning: Bool = false
    var couplesBalanceHint: String? = nil
    var faceAngleHint: String? = nil
    var detectedFaceBox: CGRect? = nil
    var detectedSkeleton: PoseSkeleton? = nil
    var detectedSecondarySkeleton: PoseSkeleton? = nil
}

// MARK: - Library Item

struct LibraryItem: Identifiable, Codable, Hashable {
    let id: UUID
    let imageFilename: String
    let isGeneratedReference: Bool
    let poseIdea: PoseIdea?
    let zoomFactor: Double?
    let overlayModeRaw: String?
    let rollDegrees: Double?
    var isFavorite: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        imageFilename: String,
        isGeneratedReference: Bool,
        poseIdea: PoseIdea? = nil,
        zoomFactor: Double? = nil,
        overlayModeRaw: String? = nil,
        rollDegrees: Double? = nil,
        isFavorite: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.imageFilename = imageFilename
        self.isGeneratedReference = isGeneratedReference
        self.poseIdea = poseIdea
        self.zoomFactor = zoomFactor
        self.overlayModeRaw = overlayModeRaw
        self.rollDegrees = rollDegrees
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.imageFilename = try c.decode(String.self, forKey: .imageFilename)
        self.isGeneratedReference = try c.decode(Bool.self, forKey: .isGeneratedReference)
        self.poseIdea = try c.decodeIfPresent(PoseIdea.self, forKey: .poseIdea)
        self.zoomFactor = try c.decodeIfPresent(Double.self, forKey: .zoomFactor)
        self.overlayModeRaw = try c.decodeIfPresent(String.self, forKey: .overlayModeRaw)
        self.rollDegrees = try c.decodeIfPresent(Double.self, forKey: .rollDegrees)
        self.isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}
