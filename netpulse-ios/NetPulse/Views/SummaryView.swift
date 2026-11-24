import Charts
import SwiftUI

struct SummaryView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    heroCard
                    metricTiles
                    latencyChartCard
                    homeNetworkCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.npBg.ignoresSafeArea())
            .navigationTitle("NetPulse")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(vm.pathSnapshot.isConnected ? Color.npGreen : Color.npAmber)
                            .frame(width: 8, height: 8)
                        Text(vm.pathSnapshot.connectionType.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.npMuted)
                    }
                }
            }
        }
    }

    private var heroCard: some View {
        let diag = vm.activeDiagnosis
        let score = diag?.healthScore ?? 0
        let ringColor: Color = {
            switch diag?.status ?? .healthy {
            case .healthy: return .npGreen
            case .degraded: return .npAmber
            case .critical: return .npRed
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(ringColor.opacity(0.25), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100.0)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(diag == nil ? "—" : "\(score)")
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(diag?.headline ?? "İlk ölçüm yapılıyor...")
                            .font(.headline)
                        if vm.pathSnapshot.isVPNActive {
                            StatusPill(text: "VPN Aktif", tone: .warn)
                        }
                    }
                    Text(vm.pinnedDeepDiagnosis != nil ? "3 sn derin teşhis sabitlendi" : "Canlı iOS ağ izleme (histerezis korumalı)")
                        .font(.caption)
                        .foregroundStyle(Color.npMuted)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    Task { await vm.runDeepDiagnose() }
                } label: {
                    HStack(spacing: 6) {
                        if vm.isDiagnosing {
                            ProgressView().tint(.black).scaleEffect(0.8)
                        } else {
                            Image(systemName: "waveform.path.ecg")
                        }
                        Text(vm.isDiagnosing ? "Ölçülüyor..." : "3 sn Sorun Teşhis")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.npBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .disabled(vm.isDiagnosing)

                if vm.pinnedDeepDiagnosis != nil {
                    Button("Canlıya Dön") {
                        vm.clearPinnedDiagnosis()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.npSurfaceSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            if let diag, (!diag.rootCauses.isEmpty || !diag.actions.isEmpty) {
                Divider().overlay(Color.npBorder)
                ForEach(diag.rootCauses.prefix(3)) { cause in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cause.title)
                            .font(.subheadline.weight(.semibold))
                        Text(cause.evidence)
                            .font(.caption)
                            .foregroundStyle(Color.npMuted)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.npBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if !diag.actions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(diag.actions) { act in
                                Button(act.label) {
                                    vm.triggerAction(act)
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(act.safety == .disruptive ? Color.npRed : Color.npGreen)
                                .foregroundStyle(act.safety == .disruptive ? .white : .black)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
        .npCard()
    }

    private var metricTiles: some View {
        let s = vm.history.last
        let gwVal = s?.gateway.reachable == true ? fmtMs(s?.gateway.avgMs) : (s == nil ? "—" : "Erişim Yok")
        let inetVal = s?.internet.reachable == true ? fmtMs(s?.internet.avgMs) : (s == nil ? "—" : "Kesik")
        let dnsVal = fmtMs(s?.dnsMs)
        let wanVal = vm.upnpInfo.available ? (vm.upnpInfo.wanStatus ?? "Aktif") : vm.pathSnapshot.connectionType.rawValue

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metricTile(
                title: "Modem (LAN)",
                value: gwVal,
                sub: "\(vm.effectiveGatewayIP ?? "—") • %\(Int(s?.gateway.lossPct ?? 0)) kayıp",
                dot: tileColor(reachable: s?.gateway.reachable ?? true, ms: s?.gateway.avgMs, warnMs: 18, badMs: 45, loss: s?.gateway.lossPct ?? 0)
            )
            metricTile(
                title: "İnternet (1.1.1.1)",
                value: inetVal,
                sub: "TCP 443 • %\(Int(s?.internet.lossPct ?? 0)) kayıp",
                dot: tileColor(reachable: s?.internet.reachable ?? true, ms: s?.internet.avgMs, warnMs: 65, badMs: 130, loss: s?.internet.lossPct ?? 0)
            )
            metricTile(
                title: "UDP DNS Hızı",
                value: dnsVal,
                sub: "cloudflare.com sorgusu",
                dot: (s?.dnsMs ?? 0) >= 180 ? .npRed : ((s?.dnsMs ?? 0) >= 85 ? .npAmber : .npGreen)
            )
            metricTile(
                title: "Ağ / Modem WAN",
                value: wanVal,
                sub: vm.upnpInfo.wanExternalIP ?? (vm.pathSnapshot.localIPv4 ?? "IP bekleniyor"),
                dot: vm.upnpInfo.available && vm.upnpInfo.wanStatus?.lowercased() != "connected" ? .npRed : .npGreen
            )
        }
    }

    private func metricTile(title: String, value: String, sub: String, dot: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.npMuted)
            }
            Text(value)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .lineLimit(1)
            Text(sub)
                .font(.caption2)
                .foregroundStyle(Color.npMuted)
                .lineLimit(1)
        }
        .npCard()
    }

    private var latencyChartCard: some View {
        let samples = Array(vm.history.suffix(60))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Canlı Gecikme Grafiği")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("Mavi: Modem • Yeşil: 1.1.1.1")
                    .font(.caption2)
                    .foregroundStyle(Color.npMuted)
            }

            if samples.count < 2 {
                Text("Grafik için birkaç ölçüm örneği bekleniyor...")
                    .font(.caption)
                    .foregroundStyle(Color.npMuted)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(samples) { item in
                        if let gwMs = item.gateway.avgMs {
                            LineMark(
                                x: .value("Zaman", Date(timeIntervalSince1970: item.timestamp)),
                                y: .value("ms", gwMs),
                                series: .value("Hat", "Modem")
                            )
                            .foregroundStyle(Color.npBlue)
                        }
                        if let inMs = item.internet.avgMs {
                            LineMark(
                                x: .value("Zaman", Date(timeIntervalSince1970: item.timestamp)),
                                y: .value("ms", inMs),
                                series: .value("Hat", "İnternet")
                            )
                            .foregroundStyle(Color.npGreen)
                        }
                    }
                }
                .chartYAxisLabel("ms")
                .frame(height: 170)
            }
        }
        .npCard()
    }

    private var homeNetworkCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ev Ağı & Modem Durumu")
                        .font(.subheadline.weight(.bold))
                    Text(homeNetworkSubtitle)
                        .font(.caption)
                        .foregroundStyle(Color.npMuted)
                }
                Spacer()
                if let wan = vm.upnpInfo.wanStatus, vm.upnpInfo.available {
                    StatusPill(
                        text: "WAN: \(wan)",
                        tone: wan.lowercased() == "connected" ? .safe : .bad
                    )
                }
                Button("Yenile") {
                    Task { await vm.refreshUpnpNow() }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }

            if let dsl = vm.modemState.dslStats, dsl.connected {
                HStack(spacing: 8) {
                    StatusPill(text: "DSL \(dsl.lineHealth.label)", tone: dslTone(dsl.lineHealth))
                    Text(
                        String(
                            format: "SNR %.1f/%.1f dB • CRC %d",
                            dsl.snrDownDb ?? 0,
                            dsl.snrUpDb ?? 0,
                            dsl.crcErrors ?? 0
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(Color.npMuted)
                }
            }
        }
        .npCard()
    }

    private var homeNetworkSubtitle: String {
        if vm.upnpInfo.available {
            let downCap = vm.upnpInfo.maxDownMbps.map { String(format: "%.1f", $0) } ?? "—"
            let upCap = vm.upnpInfo.maxUpMbps.map { String(format: "%.1f", $0) } ?? "—"
            return "\(vm.upnpInfo.routerName ?? "Modem") • Hat Kapasitesi \(downCap)/\(upCap) Mbps • Dış IP: \(vm.upnpInfo.wanExternalIP ?? "—")"
        }
        return vm.upnpInfo.note ?? "Wi-Fi üzerinden modem UPnP bilgisi bekleniyor."
    }

    private func dslTone(_ health: DslLineHealth) -> PillTone {
        switch health {
        case .good: return .safe
        case .warn: return .warn
        case .bad: return .bad
        case .unknown: return .muted
        }
    }

    private func fmtMs(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.1f ms", v)
    }

    private func tileColor(reachable: Bool, ms: Double?, warnMs: Double, badMs: Double, loss: Double) -> Color {
        if !reachable || loss >= 5 || (ms ?? 0) >= badMs { return .npRed }
        if loss > 0 || (ms ?? 0) >= warnMs { return .npAmber }
        return .npGreen
    }
}
