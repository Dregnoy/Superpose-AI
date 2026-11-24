import SwiftUI

struct StatusHeaderBar: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var pulse = false

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .connected:
            return BluePadTheme.accentMint
        case .advertising, .initializing:
            return BluePadTheme.accentCyan
        case .poweredOff, .unauthorized, .unsupported:
            return BluePadTheme.accentRose
        case .unknown:
            return BluePadTheme.accentAmber
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Connection status pill
            Button {
                viewModel.selectedTab = .connection
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        if viewModel.connectionState == .advertising {
                            Circle()
                                .fill(statusColor.opacity(0.35))
                                .frame(width: 16, height: 16)
                                .scaleEffect(pulse ? 1.45 : 0.9)
                                .opacity(pulse ? 0.15 : 0.7)
                        }
                        Circle()
                            .fill(statusColor)
                            .frame(width: 9, height: 9)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(viewModel.connectionState.statusText)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BluePadTheme.textPrimary)
                            .lineLimit(1)
                        Text("\(viewModel.settings.advertisedName) · \(viewModel.settings.keyboardLayout.shortCode)")
                            .font(.caption2)
                            .foregroundStyle(BluePadTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            // Host LED indicators (when active)
            if viewModel.ledState.contains(.capsLock) {
                ledPill("CAPS", color: BluePadTheme.accentAmber)
            }
            if viewModel.ledState.contains(.numLock) {
                ledPill("NUM", color: BluePadTheme.accentCyan)
            }

            // Jiggler active badge
            if viewModel.isJigglerActive {
                Button {
                    viewModel.toggleJiggler()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.caption2)
                        Text("\(viewModel.jigglerCountdownSeconds)s")
                            .font(.caption2.monospacedDigit().weight(.bold))
                    }
                    .foregroundStyle(BluePadTheme.bgPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(BluePadTheme.accentAmber))
                }
                .buttonStyle(.plain)
            }

            // Target Host OS quick picker
            Menu {
                ForEach(HostOSProfile.allCases) { profile in
                    Button {
                        viewModel.settings.hostOS = profile
                        viewModel.showToast("Hedef sistem: \(profile.displayName)")
                    } label: {
                        Label(
                            profile.displayName,
                            systemImage: viewModel.settings.hostOS == profile ? "checkmark" : profile.sfSymbol
                        )
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.settings.hostOS.sfSymbol)
                        .font(.caption2)
                    Text(viewModel.settings.hostOS.shortLabel)
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(BluePadTheme.accentCyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(BluePadTheme.bgElevated)
                        .overlay(Capsule().stroke(BluePadTheme.borderSubtle, lineWidth: 1))
                )
            }

            // Broadcast / Radio toggle
            Button {
                viewModel.toggleBluetoothAdvertising()
            } label: {
                Image(systemName: viewModel.connectionState.isActiveRadio ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(viewModel.connectionState.isActiveRadio ? BluePadTheme.accentCyan : BluePadTheme.accentRose)
                    .frame(width: 32, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(BluePadTheme.bgElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(BluePadTheme.borderSubtle, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bluetooth Yayınını Aç/Kapat")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(BluePadTheme.bgCard)
        .overlay(
            Rectangle()
                .fill(BluePadTheme.borderSubtle)
                .frame(height: 1),
            alignment: .bottom
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func ledPill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundStyle(BluePadTheme.bgPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
    }
}
