import Foundation

enum ReportGenerator {
    static func buildSupportSummaryText(
        path: NetworkPathSnapshot,
        sample: TelemetrySample?,
        diagnosis: DiagnosisReport?,
        upnpInfo: UpnpRouterInfo?,
        modemState: ModemState?,
        sevenDay: SevenDaySummary
    ) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        let nowTxt = fmt.string(from: Date())

        var lines: [String] = [
            "=== NetPulse iOS — ISS / Teknik Destek Özeti (\(nowTxt)) ===",
            "Bağlantı Türü: \(path.connectionType.rawValue) | Yerel IP: \(path.localIPv4 ?? "—") | Ağ Geçidi: \(path.inferredGatewayIP ?? "—")",
        ]

        if let s = sample {
            let gwStr = s.gateway.reachable ? String(format: "%.1f ms (%%%.0f kayıp)", s.gateway.avgMs ?? 0, s.gateway.lossPct) : "Erişilemiyor"
            let inStr = s.internet.reachable ? String(format: "%.1f ms (%%%.0f kayıp)", s.internet.avgMs ?? 0, s.internet.lossPct) : "Erişilemiyor"
            let dnsStr = s.dnsMs.map { String(format: "%.1f ms", $0) } ?? "—"
            lines.append("Ölçüm Özeti: Modem \(gwStr) | İnternet (1.1.1.1) \(inStr) | DNS \(dnsStr)")
        }

        if let d = diagnosis {
            lines.append("Teşhis (\(d.status.titleTR) • \(d.healthScore)/100): \(d.headline)")
            lines.append("Kanıt: \(d.summary)")
        }

        if let u = upnpInfo, u.available {
            lines.append("Modem UPnP (\(u.routerName ?? "Router")): WAN \(u.wanStatus ?? "—") | Dış IP: \(u.wanExternalIP ?? "—") | Hata: \(u.wanLastError ?? "—")")
        }

        if let dsl = modemState?.dslStats, dsl.connected {
            let downMbps = dsl.downlinkKbps.map { String(format: "%.1f", Double($0) / 1000.0) } ?? "—"
            let upMbps = dsl.uplinkKbps.map { String(format: "%.1f", Double($0) / 1000.0) } ?? "—"
            lines.append(
                "Fiziksel DSL (\(dsl.routerModel ?? "Modem")): Durum=\(dsl.dslStatus ?? "—") | Sync=\(downMbps)/\(upMbps) Mbps | SNR=\(dsl.snrDownDb.map { String(format: "%.1f", $0) } ?? "—")/\(dsl.snrUpDb.map { String(format: "%.1f", $0) } ?? "—") dB | CRC=\(dsl.crcErrors.map(String.init) ?? "—")/\(dsl.atucCrcErrors.map(String.init) ?? "—") | Zayıflama=\(dsl.attenDownDb.map { String(format: "%.1f", $0) } ?? "—")/\(dsl.attenUpDb.map { String(format: "%.1f", $0) } ?? "—") dB"
            )
        }

        lines.append(
            "7 Günlük Hafıza: \(sevenDay.totalIncidents) olay | Ort: \(sevenDay.avgInetMs.map { String(format: "%.1f ms", $0) } ?? "—") | Tepe: \(sevenDay.maxInetMs.map { String(format: "%.1f ms", $0) } ?? "—") | En Sorunlu Saat: \(sevenDay.worstHourRange ?? "Yok")"
        )
        return lines.joined(separator: "\n")
    }

    static func generateHTMLReport(
        path: NetworkPathSnapshot,
        sample: TelemetrySample?,
        diagnosis: DiagnosisReport?,
        upnpInfo: UpnpRouterInfo?,
        modemState: ModemState?,
        bufferbloat: BufferbloatResult?,
        sevenDay: SevenDaySummary,
        incidents: [IncidentRecord]
    ) -> (html: String, fileURL: URL?) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        let fname = "netpulse_ios_report_\(fmt.string(from: Date())).html"

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let genTime = timeFmt.string(from: Date())

        let causesHTML = (diagnosis?.rootCauses ?? []).map { rc in
            "<li><strong>\(esc(rc.title))</strong> — \(esc(rc.evidence))</li>"
        }.joined(separator: "\n")

        let incidentsHTML: String
        if incidents.isEmpty {
            incidentsHTML = "<tr><td colspan='4'>Son 7 günde kaydedilmiş yavaşlama olayı yok.</td></tr>"
        } else {
            incidentsHTML = incidents.prefix(15).map { inc in
                let t0 = timeFmt.string(from: Date(timeIntervalSince1970: inc.startedAt))
                return "<tr><td>\(esc(t0))</td><td>\(esc(inc.severity.rawValue.uppercased()))</td><td>\(esc(inc.title))</td><td>\(Int(inc.peakPingMs)) ms / %\(String(format: "%.1f", inc.peakLossPct))</td></tr>"
            }.joined(separator: "\n")
        }

        let dslSectionHTML: String
        if let dsl = modemState?.dslStats, dsl.connected {
            let downM = dsl.downlinkKbps.map { String(format: "%.1f Mbps", Double($0) / 1000.0) } ?? "—"
            let upM = dsl.uplinkKbps.map { String(format: "%.1f Mbps", Double($0) / 1000.0) } ?? "—"
            dslSectionHTML = """
            <div class="card">
              <h2>Modem Fiziksel DSL Hat Sağlığı (\(esc(dsl.routerModel ?? "Modem")))</h2>
              <p>Durum: <strong>\(esc(dsl.dslStatus ?? "—"))</strong> • Sync: <strong>\(esc(downM)) / \(esc(upM))</strong> • SNR: <strong>\(dsl.snrDownDb.map { String(format: "%.1f", $0) } ?? "—") / \(dsl.snrUpDb.map { String(format: "%.1f", $0) } ?? "—") dB</strong> • CRC: <strong>\(dsl.crcErrors.map(String.init) ?? "—") / \(dsl.atucCrcErrors.map(String.init) ?? "—")</strong> • Zayıflama: <strong>\(dsl.attenDownDb.map { String(format: "%.1f", $0) } ?? "—") / \(dsl.attenUpDb.map { String(format: "%.1f", $0) } ?? "—") dB</strong></p>
              <p>\(esc(dsl.healthNote))</p>
            </div>
            """
        } else {
            dslSectionHTML = ""
        }

        let html = """
<!doctype html>
<html lang="tr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>NetPulse iOS — ISS Teknik Kanıt Raporu</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 24px; color: #0f172a; line-height: 1.5; }
    h1 { margin-bottom: 4px; }
    .muted { color: #475569; font-size: 13px; }
    .card { border: 1px solid #cbd5e1; border-radius: 10px; padding: 14px 16px; margin: 14px 0; background: #f8fafc; }
    table { width: 100%; border-collapse: collapse; margin-top: 8px; font-size: 13px; }
    th, td { border-bottom: 1px solid #e2e8f0; padding: 8px; text-align: left; }
    th { background: #e2e8f0; }
  </style>
</head>
<body>
  <h1>NetPulse iOS — ISS Teknik Kanıt Raporu</h1>
  <p class="muted">Oluşturulma: \(esc(genTime)) • Bağlantı: \(esc(path.connectionType.rawValue)) • Yerel IP: \(esc(path.localIPv4 ?? "—")) • Ağ Geçidi: \(esc(path.inferredGatewayIP ?? "—"))</p>

  <div class="card">
    <h2>Teşhis Özeti (\(diagnosis?.healthScore ?? 0)/100 — \(esc(diagnosis?.status.titleTR ?? "—")))</h2>
    <p><strong>\(esc(diagnosis?.headline ?? "Veri bekleniyor"))</strong></p>
    <ul>\(causesHTML)</ul>
  </div>

  <div class="card">
    <h2>Modem UPnP WAN &amp; Ölçümler</h2>
    <p>UPnP Modem: \(esc(upnpInfo?.routerName ?? "Bulunamadı")) • WAN Durumu: <strong>\(esc(upnpInfo?.wanStatus ?? "—"))</strong> • Dış IP: \(esc(upnpInfo?.wanExternalIP ?? "—"))</p>
    <p>Son Örnek: Modem \(sample?.gateway.avgMs.map { String(format: "%.1f ms", $0) } ?? "—") • İnternet (1.1.1.1) \(sample?.internet.avgMs.map { String(format: "%.1f ms", $0) } ?? "—") • DNS \(sample?.dnsMs.map { String(format: "%.1f ms", $0) } ?? "—") • Bufferbloat Notu: <strong>\(esc(bufferbloat?.grade ?? "—"))</strong></p>
    <p>7 Günlük Özet: \(sevenDay.totalIncidents) olay • Ort: \(sevenDay.avgInetMs.map { String(format: "%.1f ms", $0) } ?? "—") • Tepe: \(sevenDay.maxInetMs.map { String(format: "%.1f ms", $0) } ?? "—")</p>
  </div>

  \(dslSectionHTML)

  <div class="card">
    <h2>Son Yavaşlama Olayları</h2>
    <table>
      <thead><tr><th>Tarih</th><th>Seviye</th><th>Başlık</th><th>Tepe Ping / Kayıp</th></tr></thead>
      <tbody>\(incidentsHTML)</tbody>
    </table>
  </div>
</body>
</html>
"""
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent(fname)
        do {
            try html.write(to: outURL, atomically: true, encoding: .utf8)
            return (html, outURL)
        } catch {
            return (html, nil)
        }
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
