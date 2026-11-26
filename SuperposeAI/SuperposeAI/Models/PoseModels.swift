import Foundation
import CoreGraphics
import SwiftUI

// MARK: - Onboarding Focus

enum PoseUseCase: String, CaseIterable, Identifiable, Codable {
    case travel = "Travel Shots"
    case couples = "Couples Photos"
    case dating = "Dating Profile"
    case selfie = "Daily Selfies"

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
        case .travel: return "Scenic framing & natural full-body poses"
        case .couples: return "Balanced two-person angles & connection"
        case .dating: return "Confident, candid, approachable portraits"
        case .selfie: return "Flattering angles, chin & hand placement"
        }
    }
}

// MARK: - Overlay Modes

enum OverlayMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case fastSilhouette = "Silhouette"
    case detailedContour = "Contour"
    case ghost = "Ghost"

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

// MARK: - Pose Idea

struct PoseIdea: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let angleLabel: String
    let confidenceTag: String
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

    var message: String {
        switch self {
        case .evaluating: return String(localized: "Checking Light…")
        case .good: return String(localized: "Good Lighting")
        case .tooDark: return String(localized: "Low Light — Face a Window")
        case .backlitOrHarsh: return String(localized: "Strong Backlight — Turn Slightly")
        }
    }

    var color: Color {
        switch self {
        case .evaluating: return .secondary
        case .good: return .green
        case .tooDark: return .orange
        case .backlitOrHarsh: return .yellow
        }
    }

    var icon: String {
        switch self {
        case .evaluating: return "sun.min"
        case .good: return "sun.max.fill"
        case .tooDark: return "moon.fill"
        case .backlitOrHarsh: return "sun.haze.fill"
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
        case .noSubject: return String(localized: "Step Into Frame")
        case .tooClose: return String(localized: "Step Back Slightly")
        case .tooFar: return String(localized: "Move Closer")
        case .moveLeft: return String(localized: "Shift Left")
        case .moveRight: return String(localized: "Shift Right")
        case .tiltDown: return String(localized: "Leave Less Headroom")
        case .great: return String(localized: "Great Framing")
        }
    }

    var isOptimal: Bool { self == .great }
}

struct LiveGuidanceState: Equatable {
    var lighting: LightingStatus = .evaluating
    var framing: FramingStatus = .noSubject
    var lumaScore: Double = 0.5
    var poseMatchScore: Int? = nil
    var detectedSkeleton: PoseSkeleton? = nil
    var detectedSecondarySkeleton: PoseSkeleton? = nil
}

// MARK: - Library Item

struct LibraryItem: Identifiable, Codable, Hashable {
    let id: UUID
    let imageFilename: String
    let isGeneratedReference: Bool
    let poseIdea: PoseIdea?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        imageFilename: String,
        isGeneratedReference: Bool,
        poseIdea: PoseIdea? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.imageFilename = imageFilename
        self.isGeneratedReference = isGeneratedReference
        self.poseIdea = poseIdea
        self.createdAt = createdAt
    }
}
