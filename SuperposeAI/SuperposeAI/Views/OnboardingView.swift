import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedUseCase: PoseUseCase = .travel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.06, blue: 0.09), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Superpose", systemImage: "figure.stand.line.dotted.figure.stand")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.cyan)

                    Text("What would you like help with first?")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    Text("Snap one photo to get tailored pose ideas, split coaching tips, and live camera outlines.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                VStack(spacing: 12) {
                    ForEach(PoseUseCase.allCases) { useCase in
                        Button {
                            selectedUseCase = useCase
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: useCase.icon)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .background(selectedUseCase == useCase ? Color.cyan.opacity(0.2) : Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(useCase.rawValue)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text(useCase.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: selectedUseCase == useCase ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedUseCase == useCase ? .cyan : .secondary)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(selectedUseCase == useCase ? 0.12 : 0.05))
                                    .stroke(selectedUseCase == useCase ? Color.cyan.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                        Text("Live camera guidance runs 100% on your iPhone. Photos are never used to train AI models.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        appState.preferredUseCase = selectedUseCase
                        appState.hasCompletedOnboarding = true
                    } label: {
                        Text("Start Shooting")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
        }
    }
}
