import SwiftUI

struct ModemControlView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 14) {
            upnpWanCard
            keychainCard
            dslTelemetryCard
        }
    }

    private var upnpWanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("UPnP WAN Durumu (Şifresiz)")
                        .font(.subheadline.weight(.bold))
                    Text(upnpSummaryLine)
                        .font(.caption)
                        .foregroundStyle(Color.npMuted)
                }
                Spacer()
                if let st = vm.upnpInfo.wanStatus, vm.upnpInfo.available {
                    StatusPill(text: st, tone: st.lowercased() == "connected" ? .safe : .bad)
                }
            }

            HStack(spacing: 10) {
                Button("UPnP Yenile") {
                    Task { await vm.refreshUpnpNow() }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)

                Button("WAN Bağlantısını Tazele") {
                    vm.triggerAction(
                        RecommendedAction(
                            actionID: .modemReconnectWAN,
                            label: "Modem WAN Bağlantısını Tazele (UPnP)",
                            description: "Modem PPPoE/WAN bağlantısını yeniden kurar (5–15 sn kesinti).",
                            safety: .disruptive,
                            requiresConfirmation: true
                        )
                    )
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(Color.npAmber)
                .disabled(!vm.upnpInfo.wanControlAvailable)
            }
        }
        .npCard()
    }

    private var keychainCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Modem Girişi (AirTies DSL & Reboot)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                StatusPill(
                    text: vm.modemState.credentialsSaved ? "Kayıtlı (\(vm.modemState.savedHost ?? "—"))" : "Kayıtlı Değil",
                    tone: vm.modemState.credentialsSaved ? .safe : .muted
                )
            }

            Text("Şifre yalnızca iOS Keychain kasasında şifreli saklanır; raporlara veya loglara yazılmaz.")
                .font(.caption)
                .foregroundStyle(Color.npMuted)

            TextField("Modem IP (örn. 192.168.2.1)", text: $vm.modemHostInput)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.subheadline, design: .monospaced))
                .padding(10)
                .background(Color.npBg)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                TextField("Kullanıcı adı", text: $vm.modemUserInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color.npBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                SecureField("Modem şifresi", text: $vm.modemPassInput)
                    .padding(10)
                    .background(Color.npBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 10) {
                Button {
                    Task { await vm.saveModemCredentials() }
                } label: {
                    HStack(spacing: 6) {
                        if vm.isSavingModem { ProgressView().scaleEffect(0.8) }
                        Text(vm.isSavingModem ? "Doğrulanıyor..." : "Kaydet & DSL Oku")
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.npBlue)
                .disabled(vm.isSavingModem)

                if vm.modemState.credentialsSaved {
                    Button("Şifreyi Sil", role: .destructive) {
                        vm.deleteModemCredentials()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                }
            }

            if let fb = vm.modemSaveFeedback, !fb.isEmpty {
                Text(fb)
                    .font(.caption)
                    .foregroundStyle(Color(red: 253 / 255, green: 230 / 255, blue: 138 / 255))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.npAmber.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .npCard()
    }

    private var dslTelemetryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fiziksel DSL Hat Değerleri")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if vm.modemState.credentialsSaved {
                    Button {
                        Task { await vm.refreshDslStats(silent: false) }
                    } label: {
                        HStack(spacing: 4) {
                            if vm.isReadingDsl { ProgressView().scaleEffect(0.7) }
                            Text(vm.isReadingDsl ? "Okunuyor" : "Yenile")
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.isReadingDsl)
                }
            }

            if let d = vm.modemState.dslStats {
                if d.connected {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        dslBox("Model / Durum", "\(d.routerModel ?? "Modem") • \(d.dslStatus ?? "—")")
                        dslBox(
                            "DSL Sync (↓ / ↑)",
                            "\(d.downlinkKbps.map { String(format: "%.1f", Double($0) / 1000.0) } ?? "—") / \(d.uplinkKbps.map { String(format: "%.1f", Double($0) / 1000.0) } ?? "—") Mbps"
                        )
                        dslBox(
                            "SNR Marjı (↓ / ↑)",
                            "\(d.snrDownDb.map { String(format: "%.1f", $0) } ?? "—") / \(d.snrUpDb.map { String(format: "%.1f", $0) } ?? "—") dB"
                        )
                        dslBox(
                            "CRC (Yerel / Santral)",
                            "\(d.crcErrors.map(String.init) ?? "—") / \(d.atucCrcErrors.map(String.init) ?? "—")"
                        )
                    }

                    HStack(spacing: 8) {
                        StatusPill(text: d.lineHealth.label, tone: dslTone(d.lineHealth))
                        Text("\(d.healthNote) (Zayıflama: \(d.attenDownDb.map { String(format: "%.1f", $0) } ?? "—")/\(d.attenUpDb.map { String(format: "%.1f", $0) } ?? "—") dB • FW: \(d.firmware ?? "—"))")
                            .font(.caption2)
                            .foregroundStyle(Color.npMuted)
                    }

                    Button(role: .destructive) {
                        vm.triggerAction(
                            RecommendedAction(
                                actionID: .modemReboot,
                                label: "Modemi Yeniden Başlat (Reboot)",
                                description: "Modem tamamen yeniden başlatılır (60–90 sn internet kesintisi).",
                                safety: .disruptive,
                                requiresConfirmation: true
                            )
                        )
                    } label: {
                        Label("Modemi Yeniden Başlat", systemImage: "power")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.npRed)
                } else {
                    Text(d.error ?? "Fiziksel DSL verileri okunamadı.")
                        .font(.caption)
                        .foregroundStyle(Color(red: 253 / 255, green: 230 / 255, blue: 138 / 255))
                }
            } else {
                Text("SNR marjı, CRC hataları ve onaylı yeniden başlatma için yukarıdan modem şifrenizi kaydedin.")
                    .font(.caption)
                    .foregroundStyle(Color.npMuted)
            }
        }
        .npCard()
    }

    private func dslBox(_ title: String, _ val: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.npMuted)
            Text(val)
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.npBg)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var upnpSummaryLine: String {
        guard vm.upnpInfo.available else {
            return vm.upnpInfo.note ?? "Modem UPnP WAN bilgisi bekleniyor."
        }
        var parts: [String] = []
        if let name = vm.upnpInfo.routerName { parts.append(name) }
        if let ip = vm.upnpInfo.wanExternalIP { parts.append("WAN IP: \(ip)") }
        if let err = vm.upnpInfo.wanLastError, err != "ERROR_NONE" { parts.append("Hata: \(err)") }
        return parts.joined(separator: " • ")
    }

    private func dslTone(_ h: DslLineHealth) -> PillTone {
        switch h {
        case .good: return .safe
        case .warn: return .warn
        case .bad: return .bad
        case .unknown: return .muted
        }
    }
}
