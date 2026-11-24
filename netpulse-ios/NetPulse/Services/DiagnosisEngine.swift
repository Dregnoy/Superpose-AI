import Foundation

enum DiagnosisEngine {
    static func analyze(
        sample: TelemetrySample,
        path: NetworkPathSnapshot,
        history: [TelemetrySample] = [],
        bufferbloat: BufferbloatResult? = nil,
        upnpInfo: UpnpRouterInfo? = nil,
        modemState: ModemState? = nil
    ) -> DiagnosisReport {
        var score = 100
        var causes: [RootCause] = []
        var actions: [RecommendedAction] = []

        func addAction(_ act: RecommendedAction) {
            if !actions.contains(where: { $0.actionID == act.actionID }) {
                actions.append(act)
            }
        }

        // Histerezis: anlık tek sıçramada panik yapmamak için son 3 örnekten en az 2'sinde bozulma aranır.
        let recent = Array((history + [sample]).suffix(3))
        let sustainCount = recent.filter {
            !$0.internet.reachable || $0.internet.lossPct >= 5.0 || ($0.internet.avgMs ?? 0) >= 115.0
        }.count
        let sustainedExternalIssue = history.count < 2 || sustainCount >= 2 || !sample.internet.reachable

        let isWiFiOrWired = (path.connectionType == .wifi || path.connectionType == .wired)

        // 1. Modem WAN kopması
        if let wanSt = upnpInfo?.wanStatus?.lowercased(),
           upnpInfo?.available == true,
           wanSt != "connected" {
            let errTxt = upnpInfo?.wanLastError ?? "Yok"
            score -= 55
            causes.append(
                RootCause(
                    layer: .modemWan,
                    severity: .critical,
                    title: "Modem WAN (İnternet) Oturumu Kopuk",
                    evidence: "\(upnpInfo?.routerName ?? "Modem") WAN durumu '\(upnpInfo?.wanStatus ?? "—")' (Son hata: \(errTxt))."
                )
            )
            addAction(
                RecommendedAction(
                    actionID: .modemReconnectWAN,
                    label: "WAN Bağlantısını Tazele (UPnP)",
                    description: "Şifresiz UPnP üzerinden modem WAN/PPPoE bağlantısını yeniden başlatır (5–15 sn kesinti).",
                    safety: .disruptive,
                    requiresConfirmation: true
                )
            )
            addAction(
                RecommendedAction(
                    actionID: .modemReboot,
                    label: "Modemi Yeniden Başlat",
                    description: "Kayıtlı modem oturumu ile modemi tamamen yeniden başlatır (60–90 sn kesinti).",
                    safety: .disruptive,
                    requiresConfirmation: true
                )
            )
        }

        // 2. Fiziksel DSL hat sağlığı (SNR / CRC / Link)
        if let dsl = modemState?.dslStats, dsl.connected {
            if dsl.lineHealth == .bad {
                score -= 35
                causes.append(
                    RootCause(
                        layer: .modemWan,
                        severity: .critical,
                        title: "Fiziksel DSL Hattında Gürültü / CRC Hatası",
                        evidence: "\(dsl.healthNote) (SNR: \(dsl.snrDownDb.map { String(format: "%.1f", $0) } ?? "—") dB • CRC: \(dsl.crcErrors ?? 0) / ATUC: \(dsl.atucCrcErrors ?? 0))."
                    )
                )
                addAction(
                    RecommendedAction(
                        actionID: .modemReboot,
                        label: "Modemi Yeniden Başlat (Yeniden Sync)",
                        description: "Modem yeniden başlatılarak DSL fiziksel bağlantısının temiz senkron kurması denenir.",
                        safety: .disruptive,
                        requiresConfirmation: true
                    )
                )
            } else if dsl.lineHealth == .warn {
                score -= 14
                causes.append(
                    RootCause(
                        layer: .modemWan,
                        severity: .warning,
                        title: "DSL Hattında Orta Düzey Gürültü",
                        evidence: "SNR: \(dsl.snrDownDb.map { String(format: "%.1f", $0) } ?? "—") dB • CRC Hata: \(dsl.crcErrors ?? 0)."
                    )
                )
            }
        }

        // 3. Yerel Wi-Fi -> Modem erişim katmanı
        if isWiFiOrWired {
            let gw = sample.gateway
            if !gw.reachable {
                score -= 45
                causes.append(
                    RootCause(
                        layer: .wifiLan,
                        severity: .critical,
                        title: "iPhone Modeme Erişemiyor",
                        evidence: "\(gw.target) adresine TCP bağlantısı yanıt vermedi (kayıp %\(Int(gw.lossPct)))."
                    )
                )
            } else if gw.lossPct >= 5.0 || (gw.avgMs ?? 0) >= 35.0 || (gw.jitterMs ?? 0) >= 20.0 {
                let gwAvg = gw.avgMs.map { String(format: "%.1f", $0) } ?? "—"
                score -= 22
                causes.append(
                    RootCause(
                        layer: .wifiLan,
                        severity: .warning,
                        title: "Ev İçi Wi-Fi → Modem Gecikmesi Yüksek",
                        evidence: "Modeme ping \(gwAvg) ms (kayıp %\(Int(gw.lossPct))); modeme yaklaşmayı veya 5 GHz ağı seçmeyi deneyin."
                    )
                )
            }
        }

        // 4. Dış İnternet / ISS katmanı
        let inet = sample.internet
        if !inet.reachable {
            score -= 55
            causes.append(
                RootCause(
                    layer: .ispLine,
                    severity: .critical,
                    title: "İnternet Çıkışı Kesik",
                    evidence: "\(inet.target) hedefinden yanıt alınamıyor (%100 kayıp)."
                )
            )
            if upnpInfo?.wanControlAvailable == true {
                addAction(
                    RecommendedAction(
                        actionID: .modemReconnectWAN,
                        label: "WAN Bağlantısını Tazele (UPnP)",
                        description: "Modemin dış internet bağlantısını UPnP ile tazeler (5–15 sn kesinti).",
                        safety: .disruptive,
                        requiresConfirmation: true
                    )
                )
            }
        } else if sustainedExternalIssue && (inet.lossPct >= 4.0 || (inet.avgMs ?? 0) >= 115.0) {
            let avgTxt = inet.avgMs.map { String(format: "%.1f", $0) } ?? "—"
            let penalty = inet.lossPct >= 10.0 ? 36 : 22
            score -= penalty
            causes.append(
                RootCause(
                    layer: .ispLine,
                    severity: inet.lossPct >= 10.0 ? .critical : .warning,
                    title: "ISS / Dış Hat Gecikmesi veya Paket Kaybı",
                    evidence: "\(inet.target): ort. \(avgTxt) ms • kayıp %\(String(format: "%.1f", inet.lossPct))."
                )
            )
            addAction(
                RecommendedAction(
                    actionID: .runBufferbloat,
                    label: "Bufferbloat Testi Çalıştır",
                    description: "Yük altında gecikme şişmesi olup olmadığını ölçer.",
                    safety: .safe,
                    requiresConfirmation: false
                )
            )
        }

        // 5. DNS yavaşlığı
        if let dnsMs = sample.dnsMs, dnsMs >= 140.0 {
            score -= 12
            causes.append(
                RootCause(
                    layer: .dns,
                    severity: dnsMs >= 250 ? .warning : .info,
                    title: "DNS Çözümleme Süresi Yavaş",
                    evidence: String(format: "UDP DNS sorgusu %.1f ms sürdü.", dnsMs)
                )
            )
            addAction(
                RecommendedAction(
                    actionID: .runDnsTest,
                    label: "En Hızlı DNS & DoH Profili Bul",
                    description: "Cloudflare, Google, Quad9, OpenDNS ve AdGuard hızlarını ölçüp iOS DoH profili üretir.",
                    safety: .safe,
                    requiresConfirmation: false
                )
            )
        }

        // 6. VPN etkisi
        if path.isVPNActive && ((inet.avgMs ?? 0) >= 85.0 || inet.lossPct > 0) {
            score -= 10
            causes.append(
                RootCause(
                    layer: .vpn,
                    severity: .warning,
                    title: "Aktif VPN Tüneli Gecikmeyi Artırıyor Olabilir",
                    evidence: "Cihazda aktif VPN arayüzü algılandı; kısa süreliğine kapatıp test etmeniz önerilir."
                )
            )
        }

        // 7. Bilinen Bufferbloat skoru D veya F ise
        if let bloat = bufferbloat, ["D", "F"].contains(bloat.grade) {
            score -= 10
            causes.append(
                RootCause(
                    layer: .bufferbloat,
                    severity: .warning,
                    title: "Yük Altında Şişme (Bufferbloat: \(bloat.grade))",
                    evidence: bloat.summary
                )
            )
        }

        score = max(0, min(100, score))
        let hasCrit = causes.contains { $0.severity == .critical }
        let hasWarn = causes.contains { $0.severity == .warning }
        let status: HealthStatus = hasCrit || score < 55 ? .critical : (hasWarn || score < 82 ? .degraded : .healthy)

        if causes.isEmpty {
            causes.append(
                RootCause(
                    layer: .healthy,
                    severity: .info,
                    title: "Tüm Ağ Katmanları Stabil",
                    evidence: "Modem, dış hat ve DNS yanıt süreleri sağlıklı aralıkta."
                )
            )
        }

        let headline: String
        switch status {
        case .healthy:
            headline = "Bağlantınız Sağlıklı"
        case .degraded:
            headline = causes.first?.title ?? "Bağlantıda Yavaşlama Var"
        case .critical:
            headline = causes.first?.title ?? "Kritik Bağlantı Sorunu"
        }

        return DiagnosisReport(
            timestamp: sample.timestamp,
            healthScore: score,
            status: status,
            headline: headline,
            summary: causes.first?.evidence ?? "",
            rootCauses: causes,
            actions: actions
        )
    }
}
