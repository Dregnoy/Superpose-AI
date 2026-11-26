import SwiftUI

struct CoachingSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let pose: PoseIdea
    @State private var voiceCoach = VoiceCoachService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Animated 2-second Pose Transition Guide
                    AnimatedPoseGuideView(targetSkeleton: pose.skeleton, secondaryTarget: pose.secondarySkeleton)
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(pose.angleLabel)
                            .font(.caption.bold())
                            .foregroundStyle(.cyan)
                        Text(pose.coaching.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // For the Subject
                    tipSection(
                        title: "Poz Veren İçin (Duruş)",
                        icon: "person.fill",
                        accent: .cyan,
                        tips: pose.coaching.subjectTips
                    )

                    // For the Photographer
                    tipSection(
                        title: "Fotoğrafçı İçin (Kadraj)",
                        icon: "camera.fill",
                        accent: .orange,
                        tips: pose.coaching.photographerTips
                    )

                    Button {
                        dismiss()
                        appState.pinPoseAndSwitchToCamera(pose)
                    } label: {
                        Label("Pozu Sabitle ve Kamerayı Aç", systemImage: "pin.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.black)
                    }
                }
                .padding(20)
            }
            .navigationTitle(pose.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if voiceCoach.isSpeaking {
                            voiceCoach.stop()
                        } else {
                            voiceCoach.speakCoaching(for: pose)
                        }
                    } label: {
                        Label(
                            voiceCoach.isSpeaking ? "Durdur" : "Sesli Dinle",
                            systemImage: voiceCoach.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill"
                        )
                        .font(.caption.bold())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") {
                        voiceCoach.stop()
                        dismiss()
                    }
                }
            }
            .onAppear {
                voiceCoach.speakCoaching(for: pose)
            }
            .onDisappear {
                voiceCoach.stop()
            }
        }
    }

    private func tipSection(title: String, icon: String, accent: Color, tips: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(accent)

            ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .frame(width: 22, height: 22)
                        .background(accent.opacity(0.2), in: Circle())
                        .foregroundStyle(accent)

                    Text(tip)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Animated Pose Transition Guide

struct AnimatedPoseGuideView: View {
    let targetSkeleton: PoseSkeleton
    var secondaryTarget: PoseSkeleton? = nil

    @State private var progress: Double = 0.0

    private static let neutralSkeleton = PoseSkeleton(joints: [
        .nose: NormalizedPoint(x: 0.50, y: 0.21),
        .neck: NormalizedPoint(x: 0.50, y: 0.28),
        .leftShoulder: NormalizedPoint(x: 0.40, y: 0.32),
        .rightShoulder: NormalizedPoint(x: 0.60, y: 0.32),
        .leftElbow: NormalizedPoint(x: 0.37, y: 0.45),
        .rightElbow: NormalizedPoint(x: 0.63, y: 0.45),
        .leftWrist: NormalizedPoint(x: 0.37, y: 0.57),
        .rightWrist: NormalizedPoint(x: 0.63, y: 0.57),
        .root: NormalizedPoint(x: 0.50, y: 0.55),
        .leftHip: NormalizedPoint(x: 0.43, y: 0.56),
        .rightHip: NormalizedPoint(x: 0.57, y: 0.56),
        .leftKnee: NormalizedPoint(x: 0.43, y: 0.74),
        .rightKnee: NormalizedPoint(x: 0.57, y: 0.74),
        .leftAnkle: NormalizedPoint(x: 0.43, y: 0.90),
        .rightAnkle: NormalizedPoint(x: 0.57, y: 0.90)
    ])

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PoseOverlayView(
                targetSkeleton: interpolated(from: Self.neutralSkeleton, to: targetSkeleton, t: progress),
                secondaryTargetSkeleton: secondaryTarget.map { interpolated(from: Self.neutralSkeleton, to: $0, t: progress) },
                liveSkeleton: nil,
                mode: .detailedContour,
                matchScore: nil
            )

            Text(progress > 0.5 ? "Hedef Poz" : "Başlangıç")
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                progress = 1.0
            }
        }
    }

    private func interpolated(from a: PoseSkeleton, to b: PoseSkeleton, t: Double) -> PoseSkeleton {
        var joints: [BodyJoint: NormalizedPoint] = [:]
        for joint in BodyJoint.allCases {
            if let pa = a.joints[joint], let pb = b.joints[joint] {
                joints[joint] = NormalizedPoint(
                    x: pa.x + (pb.x - pa.x) * t,
                    y: pa.y + (pb.y - pa.y) * t
                )
            } else if let pb = b.joints[joint] {
                joints[joint] = pb
            }
        }
        return PoseSkeleton(joints: joints)
    }
}
