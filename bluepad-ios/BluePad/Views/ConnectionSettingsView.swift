import SwiftUI
import UIKit

struct ConnectionSettingsView: View {
    private enum ConnectionSection: String, CaseIterable, Identifiable {
        case devices = "Cihazlar"
        case smartTV = "Smart TV"
        case settings = "Ayarlar"

        var id: String { rawValue }
    }

    private enum InputField: Hashable {
        case advertisedName
        case tvHost
        case tvPIN
        case wifiHost
        case wifiPort
        case wifiPIN
    }

    @ObservedObject var viewModel: AppViewModel
    @State private var activeSection: ConnectionSection = .devices
    @State private var showAdvancedBluetooth: Bool = false
    @State private var showOtherPCMethods: Bool = false
    @State private var showDiagnosticsLog: Bool = false
    @State private var nameDraft: String = ""
    @State private var onlyNamedHosts: Bool = true
    @State private var tvHostDraft: String = ""
    @State private var tvKindDraft: SmartTVKind = .androidTV
    @State private var tvPINDraft: String = ""
    @State private var wifiHostDraft: String = ""
    @State private var wifiPortDraft: String = "8765"
    @State private var wifiPINDraft: String = ""
    @State private var testFeedbackWorking: Bool? = nil
    @FocusState private var focusedField: InputField?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if viewModel.activeTarget.isActive {
                    activeConnectionLockBanner
                }

                Picker("Bölüm", selection: $activeSection) {
                    ForEach(ConnectionSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                switch activeSection {
                case .devices:
                    bluetoothControlCard

                    DisclosureGroup(isExpanded: $showOtherPCMethods) {
                        VStack(spacing: 12) {
                            nearbyHostsCard
                            wifiConnectionCard
                        }
                        .padding(.top, 8)
                    } label: {
                        Label("Diğer Seçenekler (Mac/iPad & Wi-Fi PC)", systemImage: "laptopcomputer.and.iphone")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BluePadTheme.textPrimary)
                    }
                    .tint(BluePadTheme.accentCyan)
                    .glassCard()

                case .smartTV:
                    smartTVCard

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Smart TV İpucu", systemImage: "lightbulb.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BluePadTheme.accentAmber)
                        Text("• Samsung ve LG webOS TV'lerde Trackpad gerçek fare imleci olarak çalışır.\n• Google / Android TV'de gerçek fare imleci için Bluetooth üzerinden eşleyin; Wi-Fi bağlantısında Trackpad kaydırarak yön/OK kumandası olur.")
                            .font(.caption2)
                            .foregroundStyle(BluePadTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                case .settings:
                    preferencesCard
                    pairingGuidesCard

                    DisclosureGroup(isExpanded: $showDiagnosticsLog) {
                        diagnosticsCard
                            .padding(.top, 8)
                    } label: {
                        Label("Gelişmiş Tanı Günlüğü (\(viewModel.diagnosticEvents.count))", systemImage: "waveform.path.ecg")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BluePadTheme.accentViolet)
                    }
                    .tint(BluePadTheme.accentViolet)
                    .glassCard()
                }
            }
            .padding(14)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(BluePadTheme.bgPrimary)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Bitti") {
                    dismissKeyboard()
                }
                .font(.subheadline.weight(.bold))
            }
        }
        .onAppear {
            nameDraft = viewModel.settings.advertisedName
            if tvHostDraft.isEmpty, let firstTV = viewModel.discoveredTVs.first {
                tvHostDraft = firstTV.host
                tvKindDraft = firstTV.kind
            }
            if wifiHostDraft.isEmpty, let first = viewModel.wifiHosts.first {
                wifiHostDraft = first.host
                wifiPortDraft = "\(first.port)"
            }
        }
        .onChange(of: viewModel.discoveredTVs) { _, newTVs in
            if tvHostDraft.isEmpty, let firstTV = newTVs.first {
                tvHostDraft = firstTV.host
                tvKindDraft = firstTV.kind
            }
        }
    }

    // MARK: Active Single-Target Lock Banner

    private var activeConnectionLockBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(BluePadTheme.accentMint)

            VStack(alignment: .leading, spacing: 2) {
                Text("Aktif Bağlantı (Tek Cihaz Kilitli)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BluePadTheme.accentMint)
                Text(viewModel.activeTarget.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BluePadTheme.textPrimary)
                    .lineLimit(1)
                Text("Başka bir cihaza bağlanmak için önce bu bağlantıyı kesin.")
                    .font(.caption2)
                    .foregroundStyle(BluePadTheme.textSecondary)
            }

            Spacer()

            Button("Bağlantıyı Kes") {
                dismissKeyboard()
                viewModel.disconnectActiveTarget()
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(BluePadTheme.accentRose))
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BluePadTheme.accentMint.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BluePadTheme.accentMint.opacity(0.45), lineWidth: 1)
                )
        )
    }

    // MARK: Smart TV Wi-Fi Remote Card

    private var smartTVCard: some View {
        let isLockedByOtherTarget = viewModel.activeTarget.isActive && !viewModel.activeTarget.isSmartTV
        let isTVStoppable = viewModel.tvState.isConnected || viewModel.tvState.isBusy || viewModel.tvState.isAwaitingCode

        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Smart TV (Wi-Fi Fare & Kumanda)", systemImage: "tv.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BluePadTheme.accentCyan)
                Spacer()
                Text(viewModel.tvState.statusText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(
                        viewModel.tvState.isConnected
                            ? BluePadTheme.accentMint
                            : ((viewModel.tvState.isAwaitingCode || viewModel.tvState.isAwaitingApproval)
                                ? BluePadTheme.accentAmber
                                : BluePadTheme.textSecondary)
                    )
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text("Samsung ve LG'de gerçek fare imleci; Google/Android TV ve Vestel'de Wi-Fi kumanda.")
                    .font(.caption2)
                    .foregroundStyle(BluePadTheme.textSecondary)
                Spacer()
                Button {
                    viewModel.refreshTVDiscovery()
                } label: {
                    Label("Yenile", systemImage: "arrow.clockwise")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BluePadTheme.accentCyan)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8).fill(BluePadTheme.bgPrimary))
                }
                .buttonStyle(.plain)
            }

            if !viewModel.discoveredTVs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AĞDA BULUNAN TV'LER")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BluePadTheme.textSecondary)

                    ForEach(viewModel.discoveredTVs) { tv in
                        HStack(spacing: 8) {
                            Image(systemName: "tv")
                                .foregroundStyle(BluePadTheme.accentMint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tv.name)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BluePadTheme.textPrimary)
                                    .lineLimit(1)
                                Text("\(tv.host) · \(tv.kind.displayName)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(BluePadTheme.textSecondary)
                            }
                            Spacer()
                            Button("Bağlan") {
                                dismissKeyboard()
                                tvHostDraft = tv.host
                                tvKindDraft = tv.kind
                                viewModel.connectSmartTV(host: tv.host, name: tv.name, kind: tv.kind)
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(BluePadTheme.bgPrimary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(BluePadTheme.accentMint))
                            .buttonStyle(.plain)
                            .disabled(isLockedByOtherTarget || isTVStoppable)
                            .opacity((isLockedByOtherTarget || isTVStoppable) ? 0.45 : 1.0)
                        }
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 9).fill(BluePadTheme.bgPrimary))
                    }
                }
            }

            if case .awaitingPairingCode(let tvName, _) = viewModel.tvState {
                tvPairingCodeCard(tvName: tvName, isVerifying: false)
            } else if viewModel.tvState == .verifyingCode {
                tvPairingCodeCard(tvName: tvHostDraft.isEmpty ? "TV" : tvHostDraft, isVerifying: true)
            } else if case .awaitingTVApproval(let tvName, _, let kind) = viewModel.tvState {
                HStack(spacing: 10) {
                    Image(systemName: "tv.and.mediabox")
                        .foregroundStyle(BluePadTheme.accentAmber)
                    Text("TV ekranında çıkan 'İzin Ver / Kabul Et' onayına basın (\(tvName) · \(kind.shortLabel)).")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BluePadTheme.accentAmber)
                    Spacer()
                    Button("İptal") {
                        dismissKeyboard()
                        viewModel.disconnectSmartTV()
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(BluePadTheme.accentRose))
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BluePadTheme.accentAmber.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(BluePadTheme.accentAmber.opacity(0.45), lineWidth: 1)
                        )
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SmartTVKind.allCases) { kind in
                        let selected = (tvKindDraft == kind)
                        Button {
                            tvKindDraft = kind
                            viewModel.triggerHaptic(.light)
                        } label: {
                            HStack(spacing: 4) {
                                Text(kind.shortLabel)
                                    .font(.caption2.weight(.bold))
                                if kind.supportsDirectPointer {
                                    Image(systemName: "computermouse.fill")
                                        .font(.system(size: 9))
                                }
                            }
                            .foregroundStyle(selected ? BluePadTheme.bgPrimary : BluePadTheme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selected ? BluePadTheme.accentCyan : BluePadTheme.bgPrimary)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(selected ? BluePadTheme.accentCyan : BluePadTheme.borderSubtle, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("TV IP (örn. 192.168.2.230)", text: $tvHostDraft)
                    .focused($focusedField, equals: .tvHost)
                    .textFieldStyle(.plain)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 9).fill(BluePadTheme.bgPrimary))
                    .foregroundStyle(.white)
                    .font(.caption.monospaced())

                Button {
                    dismissKeyboard()
                    if isTVStoppable {
                        tvPINDraft = ""
                        viewModel.disconnectSmartTV()
                    } else {
                        viewModel.connectSmartTV(host: tvHostDraft, name: nil, kind: tvKindDraft)
                    }
                } label: {
                    let btnText = viewModel.tvState.isConnected ? "TV Kes" : (isTVStoppable ? "İptal Et" : "TV Bağlan")
                    Text(btnText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(viewModel.tvState.isConnected ? .white : BluePadTheme.bgPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(
                                    viewModel.tvState.isConnected
                                        ? BluePadTheme.accentRose
                                        : (isTVStoppable ? BluePadTheme.accentAmber : BluePadTheme.accentCyan)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(isLockedByOtherTarget && !isTVStoppable)
                .opacity((isLockedByOtherTarget && !isTVStoppable) ? 0.45 : 1.0)
            }
        }
        .glassCard()
    }

    private func tvPairingCodeCard(tvName: String, isVerifying: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TV ekranındaki 6 haneli kodu girin (\(tvName))")
                .font(.caption.weight(.bold))
                .foregroundStyle(BluePadTheme.accentAmber)

            HStack(spacing: 8) {
                TextField("Örn. A1B2C3", text: $tvPINDraft)
                    .focused($focusedField, equals: .tvPIN)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(BluePadTheme.bgElevated))
                    .foregroundStyle(.white)
                    .font(.subheadline.monospaced().weight(.bold))

                Button(isVerifying ? "Doğrulanıyor..." : "Eşleşmeyi Onayla") {
                    dismissKeyboard()
                    viewModel.submitTVPairingCode(tvPINDraft)
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(BluePadTheme.bgPrimary)
                .padding(.horizontal, 11)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(BluePadTheme.accentAmber))
                .buttonStyle(.plain)
                .disabled(isVerifying)

                Button("İptal") {
                    dismissKeyboard()
                    tvPINDraft = ""
                    viewModel.disconnectSmartTV()
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(BluePadTheme.accentRose))
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BluePadTheme.accentAmber.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(BluePadTheme.accentAmber.opacity(0.45), lineWidth: 1)
                )
        )
    }

    // MARK: Local Wi-Fi / LAN Transport Card

    private var wifiConnectionCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Wi-Fi Yerel Ağ (İsteğe Bağlı Yedek)", systemImage: "wifi")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BluePadTheme.accentMint)
                Spacer()
                Text(viewModel.wifiState.statusText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(viewModel.wifiState.isConnected ? BluePadTheme.accentMint : BluePadTheme.textSecondary)
                    .lineLimit(1)
            }

            Text("iOS Klasik Bluetooth HID desteklemediği için Windows/Mac/Linux bilgisayarda tools/bluepad_receiver.py çalıştırıp aynı Wi-Fi'den sıfır bulut ile bağlanabilirsiniz.")
                .font(.caption2)
                .foregroundStyle(BluePadTheme.textSecondary)

            if !viewModel.wifiHosts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AĞDA BULUNAN BİLGİSAYARLAR")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BluePadTheme.textSecondary)

                    ForEach(viewModel.wifiHosts) { endpoint in
                        Button {
                            dismissKeyboard()
                            wifiHostDraft = endpoint.host
                            wifiPortDraft = "\(endpoint.port)"
                            viewModel.triggerHaptic(.light)
                            viewModel.showToast("Seçildi: \(endpoint.host):\(endpoint.port) — PIN girip Bağlan'a basın")
                        } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                    .foregroundStyle(BluePadTheme.accentCyan)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(endpoint.name)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(BluePadTheme.textPrimary)
                                    Text("\(endpoint.host):\(endpoint.port) · \(endpoint.osName)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(BluePadTheme.textSecondary)
                                }
                                Spacer()
                                Text("Seç")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(BluePadTheme.accentCyan)
                            }
                            .padding(9)
                            .background(RoundedRectangle(cornerRadius: 9).fill(BluePadTheme.bgPrimary))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("PC IP (örn. 192.168.1.25)", text: $wifiHostDraft)
                    .focused($focusedField, equals: .wifiHost)
                    .textFieldStyle(.plain)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .wifiPIN
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(BluePadTheme.bgPrimary))
                    .foregroundStyle(.white)
                    .font(.caption.monospaced())

                TextField("Port", text: $wifiPortDraft)
                    .focused($focusedField, equals: .wifiPort)
                    .textFieldStyle(.plain)
                    .keyboardType(.numberPad)
                    .frame(width: 62)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(BluePadTheme.bgPrimary))
                    .foregroundStyle(.white)
                    .font(.caption.monospaced())

                TextField("PIN", text: $wifiPINDraft)
                    .focused($focusedField, equals: .wifiPIN)
                    .textFieldStyle(.plain)
                    .keyboardType(.numberPad)
                    .frame(width: 64)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(BluePadTheme.bgPrimary))
                    .foregroundStyle(.white)
                    .font(.caption.monospaced())
            }

            let isWiFiLockedByOther = viewModel.activeTarget.isActive && !viewModel.activeTarget.isWiFiPC
            let isWiFiStoppable = viewModel.wifiState.isConnected || viewModel.wifiState.isConnecting

            HStack(spacing: 10) {
                Button {
                    dismissKeyboard()
                    if isWiFiStoppable {
                        viewModel.disconnectWiFi()
                    } else {
                        let port = UInt16(wifiPortDraft.trimmingCharacters(in: .whitespaces)) ?? WiFiHIDTransportService.defaultTCPPort
                        viewModel.connectWiFi(host: wifiHostDraft, port: port, pin: wifiPINDraft)
                    }
                } label: {
                    let buttonTitle = viewModel.wifiState.isConnected
                        ? "Wi-Fi Kes"
                        : (viewModel.wifiState.isConnecting ? "İptal Et" : "Wi-Fi Bağlan")
                    let buttonIcon = viewModel.wifiState.isConnected
                        ? "wifi.slash"
                        : (viewModel.wifiState.isConnecting ? "xmark.circle.fill" : "wifi")
                    let textColor: Color = viewModel.wifiState.isConnected ? .white : BluePadTheme.bgPrimary
                    Label(buttonTitle, systemImage: buttonIcon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(textColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(
                    KeycapButtonStyle(
                        fill: viewModel.wifiState.isConnected
                            ? BluePadTheme.accentRose
                            : (viewModel.wifiState.isConnecting ? BluePadTheme.accentAmber : BluePadTheme.accentMint),
                        border: BluePadTheme.borderSubtle
                    )
                )
                .disabled(isWiFiLockedByOther && !isWiFiStoppable)
                .opacity((isWiFiLockedByOther && !isWiFiStoppable) ? 0.45 : 1.0)

                Button {
                    viewModel.isScannerPresented = true
                } label: {
                    Label("QR Bağlan", systemImage: "qrcode.viewfinder")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BluePadTheme.accentCyan)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                }
                .buttonStyle(KeycapButtonStyle(fill: BluePadTheme.bgPrimary, border: BluePadTheme.accentCyan.opacity(0.4)))
                .disabled(isWiFiLockedByOther)
                .opacity(isWiFiLockedByOther ? 0.45 : 1.0)
            }
        }
        .glassCard()
    }

    // MARK: Bluetooth Control Card

    private var bluetoothControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Bluetooth (PC / Mac / Android)", systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BluePadTheme.accentCyan)
                Spacer()
                Text(viewModel.connectionState.statusText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(viewModel.connectionState.isConnected ? BluePadTheme.accentMint : BluePadTheme.textSecondary)
            }

            if viewModel.connectionState.isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(BluePadTheme.accentMint)
                    Text("Bağlı — Trackpad, Klavye ve Kumanda aktif.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BluePadTheme.accentMint)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BluePadTheme.accentMint.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(BluePadTheme.accentMint.opacity(0.35), lineWidth: 1)
                        )
                )
            } else {
                Text("Bilgisayar veya cihazın Bluetooth ayarlarından \"\(viewModel.settings.advertisedName)\" seçin. Windows 11'de görünmezse 'Daha fazla cihaz göster' veya tools/BluePad_Windows_Esle.bat kullanın.")
                    .font(.caption2)
                    .foregroundStyle(BluePadTheme.textSecondary)
            }

            let isBLELockedByOther = viewModel.activeTarget.isActive && !viewModel.activeTarget.isBluetooth
            if isBLELockedByOther {
                Text("Tek cihaz kilidi: Önce \(viewModel.activeTarget.displayName) bağlantısını kesin.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BluePadTheme.accentAmber)
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.toggleBluetoothAdvertising()
                } label: {
                    let toggleTitle = viewModel.connectionState.isConnected
                        ? "Bağlantıyı Kes"
                        : (viewModel.connectionState.isActiveRadio ? "Yayını Durdur" : "Yayını Başlat")
                    let toggleIcon = viewModel.connectionState.isConnected
                        ? "xmark.circle.fill"
                        : (viewModel.connectionState.isActiveRadio ? "stop.fill" : "play.fill")
                    Label(toggleTitle, systemImage: toggleIcon)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(viewModel.connectionState.isActiveRadio ? .white : BluePadTheme.bgPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(
                    KeycapButtonStyle(
                        fill: viewModel.connectionState.isActiveRadio ? BluePadTheme.accentRose.opacity(0.85) : BluePadTheme.accentMint,
                        border: BluePadTheme.borderSubtle
                    )
                )
                .disabled(isBLELockedByOther && !viewModel.connectionState.isActiveRadio)
                .opacity((isBLELockedByOther && !viewModel.connectionState.isActiveRadio) ? 0.45 : 1.0)

                if viewModel.connectionState.isConnected {
                    Button {
                        viewModel.runConnectionTestPulse()
                    } label: {
                        Label("İmleç Testi", systemImage: "cursorarrow.motionlines")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BluePadTheme.bgPrimary)
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                    }
                    .buttonStyle(KeycapButtonStyle(fill: BluePadTheme.accentAmber, border: BluePadTheme.borderSubtle))
                }
            }

            if !viewModel.connectionState.isActiveRadio {
                Button {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                } label: {
                    Label("iOS Bluetooth Ayarlarını Aç", systemImage: "gearshape.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BluePadTheme.accentCyan)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(KeycapButtonStyle(fill: BluePadTheme.bgPrimary, border: BluePadTheme.accentCyan.opacity(0.35)))
            }

            DisclosureGroup("Cihaz Adı & Gelişmiş Bluetooth", isExpanded: $showAdvancedBluetooth) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("Yayın Adı", text: $nameDraft)
                            .focused($focusedField, equals: .advertisedName)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(BluePadTheme.bgPrimary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(BluePadTheme.borderSubtle, lineWidth: 1)
                                    )
                            )
                            .foregroundStyle(.white)

                        Button("Uygula") {
                            dismissKeyboard()
                            viewModel.applyAdvertisedName(nameDraft)
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BluePadTheme.bgPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(BluePadTheme.accentCyan))
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 10) {
                        statPill(title: "Protokol", value: viewModel.protocolMode.displayName)
                        statPill(title: "Gönderilen Paket", value: "\(viewModel.packetsSentCount)")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            gattBadge(code: "180F", active: viewModel.gattStatus.batteryAdded)
                            gattBadge(code: "180A", active: viewModel.gattStatus.deviceInfoAdded)
                            gattBadge(code: "1812", active: viewModel.gattStatus.hidAdded)
                            Spacer()
                            Text(viewModel.gattStatus.advertisingMode)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(viewModel.gattStatus.isAdvertising ? BluePadTheme.accentMint : BluePadTheme.accentAmber)
                                .lineLimit(1)
                        }

                        if let err = viewModel.gattStatus.lastError {
                            Text("Son Hata: \(err)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(BluePadTheme.accentRose)
                                .lineLimit(2)
                        }

                        if let latest = viewModel.diagnosticEvents.first {
                            Text("Son olay [\(latest.category.rawValue)]: \(latest.message)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(BluePadTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(BluePadTheme.bgPrimary)
                    )

                    HStack(spacing: 10) {
                        Button {
                            viewModel.triggerServiceChangedRefresh()
                        } label: {
                            Label("GATT Yenile", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BluePadTheme.accentCyan)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                        }
                        .buttonStyle(KeycapButtonStyle(fill: BluePadTheme.bgPrimary, border: BluePadTheme.accentCyan.opacity(0.35)))
                        .disabled(!viewModel.gattStatus.hidAdded)
                        .opacity(viewModel.gattStatus.hidAdded ? 1.0 : 0.45)

                        Button {
                            viewModel.runConnectionTestPulse()
                        } label: {
                            Label("Test Gönder", systemImage: "cursorarrow.motionlines")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BluePadTheme.bgPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                        }
                        .buttonStyle(KeycapButtonStyle(fill: BluePadTheme.accentAmber, border: BluePadTheme.borderSubtle))
                    }
                }
                .padding(.top, 8)
            }
            .font(.caption.weight(.semibold))
            .tint(BluePadTheme.accentCyan)
        }
        .glassCard()
    }

    // MARK: Outbound Nearby Hosts Scanner Card

    private var filteredHosts: [DiscoveredBLEHost] {
        if onlyNamedHosts {
            return viewModel.discoveredHosts.filter {
                $0.hasExplicitName || $0.linkState.isConnected || $0.linkState.isConnecting || $0.isSystemConnected
            }
        }
        return viewModel.discoveredHosts
    }

    private var nearbyHostsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Yakındaki Cihazlar (iPhone'dan Bağlan)", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BluePadTheme.accentMint)
                Spacer()
                Button {
                    viewModel.toggleHostScan()
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isScanningHosts {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(BluePadTheme.bgPrimary)
                        }
                        Text(viewModel.isScanningHosts ? "Durdur" : "Tara")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(BluePadTheme.bgPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(viewModel.isScanningHosts ? BluePadTheme.accentAmber : BluePadTheme.accentMint)
                    )
                }
                .buttonStyle(.plain)
            }

            Text("Windows PC için buradan 'Bağlan'a basmayın ('GATT Açık / HID Yok' olur); Windows bağlantıyı kendi kurar. İlk eşleştirme için tools/BluePad_Windows_Esle.bat kullanın.")
                .font(.caption2)
                .foregroundStyle(BluePadTheme.textSecondary)

            Toggle("Sadece isimli cihazları göster", isOn: $onlyNamedHosts)
                .font(.caption.weight(.semibold))
                .tint(BluePadTheme.accentCyan)

            if filteredHosts.isEmpty {
                let emptyHint: String = viewModel.discoveredHosts.isEmpty
                    ? "Henüz BLE cihazı taranmadı. Hedef cihazın Bluetooth ayarlarını açıp 'Tara' butonuna basın."
                    : "İsimsiz \(viewModel.discoveredHosts.count) BLE sinyali bulundu. Görmek için yukarıdaki filtreyi kapatın."
                Text(emptyHint)
                    .font(.caption)
                    .foregroundStyle(BluePadTheme.textSecondary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(BluePadTheme.bgPrimary))
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredHosts.prefix(20)) { host in
                        let isActiveHIDHost = host.linkState.isConnected || (host.isSystemConnected && viewModel.connectionState.isConnected)
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(host.name)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BluePadTheme.textPrimary)
                                    .lineLimit(1)

                                HStack(spacing: 6) {
                                    Text("\(host.proximityLabel) · \(host.rssi) dBm")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(BluePadTheme.textSecondary)

                                    if let mfg = host.manufacturerName {
                                        Text(mfg)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(BluePadTheme.accentViolet)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(RoundedRectangle(cornerRadius: 4).fill(BluePadTheme.accentViolet.opacity(0.16)))
                                    }

                                    if host.isSystemConnected && !host.linkState.isConnected {
                                        let isConnectedHID = viewModel.connectionState.isConnected
                                        Text(isConnectedHID ? "Bağlı (HID)" : "Sistem / Eşli")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(isConnectedHID ? BluePadTheme.accentMint : BluePadTheme.accentCyan)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill((isConnectedHID ? BluePadTheme.accentMint : BluePadTheme.accentCyan).opacity(0.15))
                                            )
                                    }

                                    if host.linkState != .discovered {
                                        Text(host.linkState.label)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(
                                                (host.linkState.isConnected && viewModel.connectionState.isConnected)
                                                    ? BluePadTheme.accentMint
                                                    : BluePadTheme.accentAmber
                                            )
                                    }
                                }
                            }

                            Spacer()

                            let isMicrosoftPC = host.manufacturerName?.contains("Microsoft") == true
                            if isMicrosoftPC && !isActiveHIDHost && !host.linkState.isConnecting {
                                Text("Windows PC · Bilgisayardan bağlanın")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(BluePadTheme.accentAmber)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(BluePadTheme.accentAmber.opacity(0.14)))
                            } else {
                                let disableOutbound = viewModel.activeTarget.isActive && !isActiveHIDHost && !host.linkState.isConnecting
                                Button {
                                    if isActiveHIDHost || host.linkState.isConnecting {
                                        viewModel.disconnectHostOrHID(host)
                                    } else {
                                        viewModel.connectToHost(host)
                                    }
                                } label: {
                                    Text(isActiveHIDHost ? "Kes" : (host.linkState.isConnecting ? "İptal" : "Bağlan"))
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(isActiveHIDHost ? .white : BluePadTheme.bgPrimary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(
                                                    isActiveHIDHost
                                                        ? BluePadTheme.accentRose
                                                        : (host.linkState.isConnecting ? BluePadTheme.accentAmber : BluePadTheme.accentCyan)
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                                .disabled(disableOutbound)
                                .opacity(disableOutbound ? 0.45 : 1.0)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(BluePadTheme.bgPrimary)
                        )
                    }
                }
            }
        }
        .glassCard()
    }

    // MARK: Pairing Guides

    private var pairingGuidesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Eşleştirme Rehberi (Sunucusuz)", systemImage: "questionmark.circle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BluePadTheme.accentMint)

            DisclosureGroup("Yöntem 1: iPhone'dan Bağlan (Görünmeyen Cihazlar İçin)") {
                Text("1. Hedef cihazda (Windows / Android / Mac / TV) Bluetooth Ayarları ekranını açık bırakın.\n2. BluePad içinde yukarıdaki 'Yakındaki Cihazlar → Tara' butonuna dokunun.\n3. Listede cihazınızı seçip 'Bağlan' deyin; iPhone bağlantıyı başlatınca karşı taraf 0x1812 HID servisini algılar.\n4. İkisinde de çıkan eşleştirme PIN/onayını kabul edin.")
                    .font(.caption)
                    .foregroundStyle(BluePadTheme.textSecondary)
                    .padding(.top, 4)
            }
            .tint(BluePadTheme.accentMint)

            DisclosureGroup("Yöntem 2: Hedef Cihazdan Windows 10 / 11'e Eşleştirme") {
                Text("1. BluePad'i ön planda ve iPhone ekranını açık tutun (kilitlenirse iOS BLE adını gizler).\n2. Windows 11 24H2'de Ayarlar → Bluetooth ve cihazlar → Cihaz ekle → Bluetooth ekranında en alttaki 'Daha fazla cihaz göster' butonuna tıklayıp \"\(viewModel.settings.advertisedName)\" seçin.\n3. Windows listesi hâlâ gizliyorsa bilgisayarda tools/bluepad_pair_windows.ps1 betiğini çalıştırarak 5 saniyede doğrudan eşleştirin.")
                    .font(.caption)
                    .foregroundStyle(BluePadTheme.textSecondary)
                    .padding(.top, 4)
            }
            .tint(BluePadTheme.accentCyan)

            DisclosureGroup("macOS & iPadOS / Aynı Apple ID") {
                Text("1. Aynı Apple ID ile giriş yapılmış iki Apple cihazında Ayarlar → Bluetooth diğer cihazı gizleyebilir.\n2. Bu durumda hedef Mac/iPad'de Bluetooth ayarını açık tutup yukarıdaki 'Yakındaki Cihazlar' listesinden bağlanın.\n3. Bağlantı kurulunca hedef cihaz otomatik olarak 0x1812 HID profiline abone olur.")
                    .font(.caption)
                    .foregroundStyle(BluePadTheme.textSecondary)
                    .padding(.top, 4)
            }
            .tint(BluePadTheme.accentCyan)

            DisclosureGroup("Android / Google TV / Linux & Eşleşme Sıfırlama") {
                Text("1. HOGP protokolü şifreli bağlama (bonding) gerektirir. Eski/yarım kalan eşleşme varsa iki taraftan da cihazı 'Unut' yapın.\n2. TV/Android aksesuar taramasında görünmezse Yöntem 1'i kullanın veya 'GATT Yenile'ye basın.")
                    .font(.caption)
                    .foregroundStyle(BluePadTheme.textSecondary)
                    .padding(.top, 4)
            }
            .tint(BluePadTheme.accentAmber)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(BluePadTheme.textPrimary)
        .glassCard()
    }

    // MARK: Preferences

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Trackpad, Klavye & Haptik Ayarları", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BluePadTheme.accentCyan)

            Picker("Varsayılan Klavye Düzeni", selection: $viewModel.settings.keyboardLayout) {
                ForEach(KeyboardLayoutKind.allCases) { layout in
                    Text(layout.displayName).tag(layout)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Picker("Klavye Kısayol Profili", selection: $viewModel.settings.hostOS) {
                    ForEach(HostOSProfile.allCases) { os in
                        Text(os.displayName).tag(os)
                    }
                }
                Text("Yalnızca Kopyala/Yapıştır/Ekran Kilidi kısayol tuşlarını (Ctrl / ⌘) değiştirir; Bluetooth bağlantısını değiştirmez.")
                    .font(.caption2)
                    .foregroundStyle(BluePadTheme.textSecondary)
            }

            Divider().overlay(BluePadTheme.borderSubtle)

            sliderRow(
                title: "İmleç Hassasiyeti",
                valueText: String(format: "%.2fx", viewModel.settings.pointerSensitivity),
                value: $viewModel.settings.pointerSensitivity,
                range: 0.3...3.5,
                step: 0.05
            )

            sliderRow(
                title: "Kaydırma Hızı",
                valueText: String(format: "%.2fx", viewModel.settings.scrollSensitivity),
                value: $viewModel.settings.scrollSensitivity,
                range: 0.3...3.0,
                step: 0.05
            )

            sliderRow(
                title: "Hava Faresi Hassasiyeti",
                valueText: String(format: "%.2fx", viewModel.settings.airMouseSensitivity),
                value: $viewModel.settings.airMouseSensitivity,
                range: 0.4...3.0,
                step: 0.05
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Toplu Yazma Gecikmesi")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(viewModel.settings.typingDelayMs) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(BluePadTheme.accentCyan)
                }
                Slider(
                    value: Binding(
                        get: { Double(viewModel.settings.typingDelayMs) },
                        set: { viewModel.settings.typingDelayMs = Int($0.rounded()) }
                    ),
                    in: 5...80,
                    step: 1
                )
                .tint(BluePadTheme.accentCyan)
            }

            Divider().overlay(BluePadTheme.borderSubtle)

            Toggle("İmleç İvmelenmesi", isOn: $viewModel.settings.pointerAcceleration)
                .font(.caption.weight(.semibold))
                .tint(BluePadTheme.accentCyan)
            Toggle("Doğal Kaydırma (Natural Scroll)", isOn: $viewModel.settings.naturalScrolling)
                .font(.caption.weight(.semibold))
                .tint(BluePadTheme.accentCyan)
            Toggle("Dokunarak Tıklama (Tap-to-Click)", isOn: $viewModel.settings.tapToClick)
                .font(.caption.weight(.semibold))
                .tint(BluePadTheme.accentCyan)
            Toggle("Dokunsal Geri Bildirim (Haptik)", isOn: $viewModel.settings.hapticsEnabled)
                .font(.caption.weight(.semibold))
                .tint(BluePadTheme.accentCyan)
            Toggle("Fare Butonlarını Üstte Göster", isOn: $viewModel.settings.touchpadButtonsOnTop)
                .font(.caption.weight(.semibold))
                .tint(BluePadTheme.accentCyan)
            Toggle("Kenar Kaydırma Şeridi", isOn: $viewModel.settings.showScrollStrip)
                .font(.caption.weight(.semibold))
                .tint(BluePadTheme.accentCyan)
            VStack(alignment: .leading, spacing: 3) {
                Toggle("Yayın Açıkken Ekranı Açık Tut", isOn: $viewModel.settings.keepScreenAwakeWhileAdvertising)
                    .font(.caption.weight(.semibold))
                    .tint(BluePadTheme.accentCyan)
                Text("iOS ekran kilitlenince BLE adını gizler; eşleştirme ve kullanım sırasında açık kalması önerilir.")
                    .font(.caption2)
                    .foregroundStyle(BluePadTheme.textSecondary)
            }
        }
        .glassCard()
    }

    // MARK: Live HID Diagnostics

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("HID Protokol Tanı Günlüğü", systemImage: "waveform.path.ecg")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BluePadTheme.accentViolet)
                Spacer()
                Button("Kopyala") {
                    UIPasteboard.general.string = viewModel.diagnosticsLogText()
                    viewModel.showToast("Tanı günlüğü panoya kopyalandı")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(BluePadTheme.accentCyan)

                Button("Temizle") {
                    viewModel.clearDiagnostics()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(BluePadTheme.accentRose)
            }

            if viewModel.diagnosticEvents.isEmpty {
                Text("Henüz HID / GATT olayı kaydedilmedi.")
                    .font(.caption)
                    .foregroundStyle(BluePadTheme.textSecondary)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.diagnosticEvents.prefix(40)) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(event.category.rawValue)
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .foregroundStyle(categoryColor(event.category))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(categoryColor(event.category).opacity(0.16)))
                                Text(event.message)
                                    .font(.caption2)
                                    .foregroundStyle(BluePadTheme.textPrimary)
                                    .lineLimit(2)
                            }
                            if let hex = event.hexPayload {
                                Text(hex)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(BluePadTheme.accentCyan)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BluePadTheme.bgPrimary)
                )
            }
        }
        .glassCard()
    }

    // MARK: Helpers

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BluePadTheme.textSecondary)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(BluePadTheme.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BluePadTheme.bgPrimary)
        )
    }

    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(BluePadTheme.accentCyan)
            }
            Slider(value: value, in: range, step: step)
                .tint(BluePadTheme.accentCyan)
        }
    }

    private func gattBadge(code: String, active: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: active ? "checkmark.circle.fill" : "clock")
                .font(.system(size: 9))
            Text(code)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(active ? BluePadTheme.accentMint : BluePadTheme.textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill((active ? BluePadTheme.accentMint : BluePadTheme.textSecondary).opacity(0.14))
        )
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func categoryColor(_ category: HIDDiagnosticEvent.Category) -> Color {
        switch category {
        case .ble: return BluePadTheme.accentCyan
        case .gatt: return BluePadTheme.accentMint
        case .tx: return BluePadTheme.accentBlue
        case .rx: return BluePadTheme.accentAmber
        case .error: return BluePadTheme.accentRose
        }
    }
}
