import XCTest
@testable import NetPulse

final class NetPulseCoreTests: XCTestCase {
    func testValidatePrivateLANHostAcceptsAndRejectsProperly() throws {
        XCTAssertEqual(try validatePrivateLANHost("192.168.2.1"), "192.168.2.1")
        XCTAssertEqual(try validatePrivateLANHost("http://192.168.2.1/login.html"), "192.168.2.1")
        XCTAssertEqual(try validatePrivateLANHost("https://10.0.0.1:8080/"), "10.0.0.1")
        XCTAssertEqual(try validatePrivateLANHost("172.16.4.2"), "172.16.4.2")

        XCTAssertThrowsError(try validatePrivateLANHost("8.8.8.8"))
        XCTAssertThrowsError(try validatePrivateLANHost("127.0.0.1"))
        XCTAssertThrowsError(try validatePrivateLANHost("169.254.1.1"))
        XCTAssertThrowsError(try validatePrivateLANHost("172.32.0.1"))
        XCTAssertThrowsError(try validatePrivateLANHost("not-an-ip"))
    }

    func testAirTiesXMLParserMultiKeyAndErrorCodes() {
        let realXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <response version="1.0.1">
            <webapp><key>error</key><value>23</value></webapp>
            <dsl-0>
                <key>status.training_stat</key><value>Showtime</value>
                <key>status.mode</key><value>VDSL2</value>
                <key>physLinkStatus</key><value>Up</value>
                <key>downlink.snr</key><value>10.9</value>
                <key>downlink.rate</key><value>23385</value>
                <key>uplink.snr</key><value>8.2</value>
                <key>uplink.rate</key><value>4423</value>
                <key>CRCErrors</key><value>76221</value>
                <key>ATUCCRCErrors</key><value>19149</value>
            </dsl-0>
            <sysmgr-0>
                <key>productid</key><value>Air5650TT</value>
                <key>fwversion</key><value>1.3.0.14.4172</value>
            </sysmgr-0>
        </response>
        """
        let parsed = AirTiesXMLParser.parse(realXML)
        XCTAssertNil(parsed.sessionError)
        XCTAssertEqual(parsed.values["webapp.error"], "23")
        XCTAssertEqual(parsed.values["dsl-0.status.training_stat"], "Showtime")
        XCTAssertEqual(parsed.values["dsl-0.downlink.rate"], "23385")
        XCTAssertEqual(parsed.values["dsl-0.downlink.snr"], "10.9")
        XCTAssertEqual(parsed.values["dsl-0.CRCErrors"], "76221")
        XCTAssertEqual(parsed.values["sysmgr-0.productid"], "Air5650TT")

        let err1 = AirTiesXMLParser.parse("<response version=\"1.0.1\"><webapp><key>error</key><value>1</value></webapp></response>")
        XCTAssertEqual(err1.sessionError, "1")

        let err4 = AirTiesXMLParser.parse("<response version=\"1.0.1\"><webapp><key>error</key><value>4</value></webapp></response>")
        XCTAssertEqual(err4.sessionError, "4")
    }

    func testAirTiesLoginErrorParsingAndDoubleQuotedXML() {
        let meta6 = "<html><head><meta http-equiv=\"Refresh\" content=\"0; url=/login.html?ErrorCode=6\"></head></html>"
        let msg6 = AirTiesModemClient.parseLoginErrorMessage(finalURL: "http://192.168.2.1/cgi-bin/login", body: meta6)
        XCTAssertNotNil(msg6)
        XCTAssertTrue(msg6?.contains("ErrorCode=6") == true)

        let msgOk = AirTiesModemClient.parseLoginErrorMessage(finalURL: "http://192.168.2.1/main.html", body: "<html></html>")
        XCTAssertNil(msgOk)

        let dslXML = AirTiesModemClient.buildDslQueryXML()
        XCTAssertTrue(dslXML.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(dslXML.contains("<xmlrequest version=\"1.0.1\">"))
        XCTAssertFalse(dslXML.contains("version='1.0.1'"))

        let rebootXML = AirTiesModemClient.buildRebootXML()
        XCTAssertTrue(rebootXML.contains("<command inst=\"sysmgr-0\"><key>reboot</key><value></value></command>"))
        XCTAssertFalse(rebootXML.contains("version='1.0.1'"))
    }

    func testDnsWirePacketAndDoHMobileConfig() {
        let pkt = DnsProbeService.buildDnsQueryPacket(domain: "cloudflare.com", transactionID: 0x1234)
        XCTAssertEqual(pkt[0], 0x12)
        XCTAssertEqual(pkt[1], 0x34)
        XCTAssertGreaterThan(pkt.count, 20)

        // Simüle yanıt: Header(tx=0x1234, QD=1, AN=1) + Question + Compression Ptr Answer(1.1.1.1)
        var fakeResp = Data([
            0x12, 0x34, 0x81, 0x80,
            0x00, 0x01, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x00,
        ])
        fakeResp.append(contentsOf: pkt.dropFirst(12))
        fakeResp.append(contentsOf: [
            0xC0, 0x0C, // Name pointer -> offset 12
            0x00, 0x01, // Type A
            0x00, 0x01, // Class IN
            0x00, 0x00, 0x00, 0x3C, // TTL
            0x00, 0x04, // RDLENGTH 4
            0x01, 0x01, 0x01, 0x01, // 1.1.1.1
        ])
        XCTAssertEqual(DnsProbeService.parseDnsResponseIPv4(data: fakeResp, expectedTransactionID: 0x1234), "1.1.1.1")
        XCTAssertNil(DnsProbeService.parseDnsResponseIPv4(data: fakeResp, expectedTransactionID: 0x9999))

        let mobilecfg = DnsProbeService.generateDoHMobileConfig(
            providerName: "Cloudflare",
            primaryIP: "1.1.1.1",
            secondaryIP: "1.0.0.1",
            dohURL: "https://cloudflare-dns.com/dns-query"
        )
        XCTAssertTrue(mobilecfg.contains("com.apple.dnsSettings.managed"))
        XCTAssertTrue(mobilecfg.contains("https://cloudflare-dns.com/dns-query"))
    }

    func testUpnpWraparoundAndDiagnosisHysteresisAndModemCauses() {
        XCTAssertEqual(UpnpWanService.computeU32Delta(previous: 0xFFFFFFF0, current: 10), 26)

        let path = NetworkPathSnapshot(
            connectionType: .wifi,
            isConnected: true,
            isExpensive: false,
            isConstrained: false,
            isVPNActive: false,
            localIPv4: "192.168.2.117",
            inferredGatewayIP: "192.168.2.1"
        )

        func mkSample(inetMs: Double, inetLoss: Double = 0, inetReach: Bool = true) -> TelemetrySample {
            TelemetrySample(
                timestamp: 1_795_500_000,
                gateway: ProbeMetrics(target: "192.168.2.1", sent: 2, received: 2, lossPct: 0, avgMs: 3.0, maxMs: 4.0, jitterMs: 0.4, reachable: true),
                internet: ProbeMetrics(target: "1.1.1.1", sent: 2, received: inetReach ? 2 : 0, lossPct: inetLoss, avgMs: inetReach ? inetMs : nil, maxMs: inetReach ? inetMs : nil, jitterMs: 1.0, reachable: inetReach),
                dnsMs: 16.0,
                pathType: .wifi
            )
        }

        // Tek ani sıçramada histerezis sağlıklı kalır
        let histHealthy = [mkSample(inetMs: 22), mkSample(inetMs: 24)]
        let spikeRep = DiagnosisEngine.analyze(sample: mkSample(inetMs: 185, inetLoss: 15), path: path, history: histHealthy)
        XCTAssertEqual(spikeRep.status, .healthy)

        // Modem WAN kopuk + yüksek CRC hatası -> kritik + onaylı kurtarma aksiyonları
        let upnpDown = UpnpRouterInfo(available: true, routerName: "Air5650TT", wanStatus: "Disconnected", wanLastError: "ERROR_ISP_TIME_OUT", wanControlAvailable: true)
        let dslBad = ModemState(
            credentialsSaved: true,
            savedHost: "192.168.2.1",
            savedUsername: "admin",
            dslStats: ModemDslStats(
                connected: true,
                routerModel: "Air5650TT",
                dslStatus: "Showtime",
                downlinkKbps: 23385,
                uplinkKbps: 4423,
                crcErrors: 76221,
                atucCrcErrors: 19149,
                snrDownDb: 10.9,
                lineHealth: .bad,
                healthNote: "Yüksek CRC hatası"
            )
        )
        let critRep = DiagnosisEngine.analyze(
            sample: mkSample(inetMs: 0, inetLoss: 100, inetReach: false),
            path: path,
            history: histHealthy,
            upnpInfo: upnpDown,
            modemState: dslBad
        )
        XCTAssertEqual(critRep.status, .critical)
        XCTAssertTrue(critRep.actions.contains(where: { $0.actionID == .modemReconnectWAN && $0.requiresConfirmation }))
        XCTAssertTrue(critRep.actions.contains(where: { $0.actionID == .modemReboot && $0.requiresConfirmation }))

        // Rapor özeti gizli şifre içermez ve DSL verilerini taşır
        let sum = ReportGenerator.buildSupportSummaryText(
            path: path,
            sample: mkSample(inetMs: 25),
            diagnosis: critRep,
            upnpInfo: upnpDown,
            modemState: dslBad,
            sevenDay: SevenDaySummary(totalSamples: 10, totalIncidents: 1, avgInetMs: 25, maxInetMs: 180, worstHourRange: "20:00–21:00")
        )
        XCTAssertTrue(sum.contains("76221"))
        XCTAssertTrue(sum.contains("10.9"))
        XCTAssertTrue(sum.contains("Air5650TT"))
    }

    func testStorageServiceHysteresisPersistence() async {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("netpulse_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = StorageService(fileURL: tmp)
        let path = NetworkPathSnapshot.empty
        let badSample = TelemetrySample(
            timestamp: 1_795_500_000,
            gateway: ProbeMetrics.unreachable("192.168.2.1", sent: 2),
            internet: ProbeMetrics.unreachable("1.1.1.1", sent: 2),
            dnsMs: nil,
            pathType: .wifi
        )
        let badDiag = DiagnosisEngine.analyze(sample: badSample, path: path)

        await store.recordTick(sample: badSample, diagnosis: badDiag)
        var incs = await store.recentIncidents()
        XCTAssertEqual(incs.count, 0) // İlk kötü tick olay açmaz

        await store.recordTick(sample: badSample, diagnosis: badDiag)
        incs = await store.recentIncidents()
        XCTAssertEqual(incs.count, 1) // 2. ardışık kötü tick olayı açar
    }
}
