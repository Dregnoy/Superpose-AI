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

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Superpose", systemImage: "figure.stand.line.dotted.figure.stand")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.cyan)
                            Spacer()
                            Button("Atla") {
                                finishOnboarding()
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        }

                        Text("İlk olarak ne konuda yardım istersin?")
                            .font(.title.bold())
                            .foregroundStyle(.white)

                        Text("Tek bir fotoğraf çek; sana özel poz fikirleri, çift taraflı koçluk ve canlı kamera çizgileri anında gelsin.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 16)

                    VStack(spacing: 10) {
                        ForEach(PoseUseCase.allCases) { useCase in
                            Button {
                                if selectedUseCase == useCase {
                                    finishOnboarding()
                                } else {
                                    selectedUseCase = useCase
                                }
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
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                        Text("Canlı kamera rehberliği %100 telefonunda çalışır.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        finishOnboarding()
                    } label: {
                        Text("Çekime Başla")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func finishOnboarding() {
        appState.preferredUseCase = selectedUseCase
        appState.hasCompletedOnboarding = true
    }
}
