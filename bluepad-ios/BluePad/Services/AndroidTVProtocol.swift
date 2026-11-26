import CryptoKit
import Foundation
import Security

/// Supported local Wi-Fi Smart TV remote control protocols (zero companion app needed on TV).
enum SmartTVKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case androidTV = "android_tv"
    case samsungTizen = "samsung_tizen"
    case lgWebOS = "lg_webos"
    case vestel = "vestel"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .androidTV: return "Google / Android TV"
        case .samsungTizen: return "Samsung TV"
        case .lgWebOS: return "LG webOS TV"
        case .vestel: return "Vestel TV"
        }
    }

    var shortLabel: String {
        switch self {
        case .androidTV: return "Android TV"
        case .samsungTizen: return "Samsung"
        case .lgWebOS: return "LG webOS"
        case .vestel: return "Vestel"
        }
    }

    var defaultPort: UInt16 {
        switch self {
        case .androidTV: return 6466
        case .samsungTizen: return 8002
        case .lgWebOS: return 3001
        case .vestel: return 56789
        }
    }

    var supportsDirectPointer: Bool {
        switch self {
        case .samsungTizen, .lgWebOS:
            return true
        case .androidTV, .vestel:
            return false
        }
    }
}

/// Discovered Smart TV endpoint on the local Wi-Fi LAN.
struct SmartTVEndpoint: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var name: String
    var host: String
    var kind: SmartTVKind
    var isBonjourDiscovered: Bool

    init(
        name: String,
        host: String,
        kind: SmartTVKind,
        isBonjourDiscovered: Bool = true
    ) {
        self.id = "\(kind.rawValue):\(host)"
        self.name = name
        self.host = host
        self.kind = kind
        self.isBonjourDiscovered = isBonjourDiscovered
    }
}

/// Connection lifecycle for the local Wi-Fi Smart TV controller.
enum SmartTVConnectionState: Equatable, Sendable {
    case disconnected
    case connecting(String)
    case awaitingPairingCode(tvName: String, host: String)
    case awaitingTVApproval(tvName: String, host: String, kind: SmartTVKind)
    case verifyingCode
    case connected(tvName: String, host: String, kind: SmartTVKind)
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isAwaitingCode: Bool {
        if case .awaitingPairingCode = self { return true }
        return false
    }

    var isAwaitingApproval: Bool {
        if case .awaitingTVApproval = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .connecting, .verifyingCode, .awaitingTVApproval:
            return true
        default:
            return false
        }
    }

    var connectedKind: SmartTVKind? {
        if case .connected(_, _, let kind) = self { return kind }
        return nil
    }

    var statusText: String {
        switch self {
        case .disconnected:
            return "Bağlı Değil"
        case .connecting(let target):
            return "TV'ye Bağlanıyor: \(target)"
        case .awaitingPairingCode(let tvName, _):
            return "PIN Bekleniyor (\(tvName))"
        case .awaitingTVApproval(let tvName, _, _):
            return "TV ekranında 'İzin Ver'e basın (\(tvName))"
        case .verifyingCode:
            return "Kod Doğrulanıyor..."
        case .connected(let tvName, _, let kind):
            return "\(kind.shortLabel) · \(tvName)"
        case .failed(let reason):
            return "TV Hatası: \(reason)"
        }
    }
}

/// Android KeyEvent key codes used by Android TV / Google TV Remote Protocol v2 (`remotemessage.proto`).
enum AndroidTVKeyCode: Int32, Sendable {
    case home             = 3
    case back             = 4
    case dpadUp           = 19
    case dpadDown         = 20
    case dpadLeft         = 21
    case dpadRight        = 22
    case dpadCenter       = 23
    case volumeUp         = 24
    case volumeDown       = 25
    case power            = 26
    case space            = 62
    case enter            = 66
    case del              = 67
    case menu             = 82
    case search           = 84
    case mediaPlayPause   = 85
    case mediaStop        = 86
    case mediaNext        = 87
    case mediaPrevious    = 88
    case mediaRewind      = 89
    case mediaFastForward = 90
    case forwardDel       = 112
    case volumeMute       = 164
    case channelUp        = 166
    case channelDown      = 167
    case captions         = 175
    case tvInput          = 178
    case sleep            = 223
    case wakeUp           = 224

    static func from(hidKeyCode: HIDKeyCode) -> AndroidTVKeyCode? {
        switch hidKeyCode {
        case .upArrow: return .dpadUp
        case .downArrow: return .dpadDown
        case .leftArrow: return .dpadLeft
        case .rightArrow: return .dpadRight
        case .enter, .kpEnter: return .dpadCenter
        case .escape: return .back
        case .backspace: return .del
        case .deleteForward: return .forwardDel
        case .space: return .space
        case .application: return .menu
        case .home: return .home
        case .pageUp: return .channelUp
        case .pageDown: return .channelDown
        default: return nil
        }
    }

    static func from(consumerUsage: HIDConsumerUsage) -> AndroidTVKeyCode? {
        switch consumerUsage {
        case .power: return .power
        case .menu: return .menu
        case .menuPick: return .dpadCenter
        case .menuUp: return .dpadUp
        case .menuDown: return .dpadDown
        case .menuLeft: return .dpadLeft
        case .menuRight: return .dpadRight
        case .menuEscape, .acBack: return .back
        case .acHome: return .home
        case .acSearch: return .search
        case .playPause: return .mediaPlayPause
        case .stop: return .mediaStop
        case .scanNextTrack: return .mediaNext
        case .scanPreviousTrack: return .mediaPrevious
        case .fastForward: return .mediaFastForward
        case .rewind: return .mediaRewind
        case .mute: return .volumeMute
        case .volumeIncrement: return .volumeUp
        case .volumeDecrement: return .volumeDown
        default: return nil
        }
    }

    static func from(systemUsage: HIDSystemUsage) -> AndroidTVKeyCode? {
        if systemUsage.contains(.powerDown) { return .power }
        if systemUsage.contains(.sleep) { return .sleep }
        if systemUsage.contains(.wakeUp) { return .wakeUp }
        return nil
    }
}

/// Vestel SmartCenter XML key codes (`POST http://<ip>:56789/apps/SmartCenter`).
enum VestelKeyCode: Int, Sendable {
    case back        = 1010
    case power       = 1012
    case mute        = 1013
    case volumeUp    = 1016
    case volumeDown  = 1017
    case down        = 1019
    case up          = 1020
    case left        = 1021
    case right       = 1022
    case stop        = 1024
    case play        = 1025
    case channelUp   = 1032
    case channelDown = 1033
    case source      = 1037
    case menu        = 1048
    case pause       = 1049
    case ok          = 1053
    case home        = 1046

    static func from(hidKeyCode: HIDKeyCode) -> VestelKeyCode? {
        switch hidKeyCode {
        case .upArrow: return .up
        case .downArrow: return .down
        case .leftArrow: return .left
        case .rightArrow: return .right
        case .enter, .kpEnter: return .ok
        case .escape, .backspace: return .back
        case .application: return .menu
        case .home: return .home
        case .pageUp: return .channelUp
        case .pageDown: return .channelDown
        default: return nil
        }
    }

    static func from(consumerUsage: HIDConsumerUsage) -> VestelKeyCode? {
        switch consumerUsage {
        case .power: return .power
        case .menu: return .menu
        case .menuPick: return .ok
        case .menuUp: return .up
        case .menuDown: return .down
        case .menuLeft: return .left
        case .menuRight: return .right
        case .menuEscape, .acBack: return .back
        case .acHome: return .home
        case .playPause: return .play
        case .stop: return .stop
        case .mute: return .mute
        case .volumeIncrement: return .volumeUp
        case .volumeDecrement: return .volumeDown
        default: return nil
        }
    }

    static func from(systemUsage: HIDSystemUsage) -> VestelKeyCode? {
        if systemUsage.contains(.powerDown) || systemUsage.contains(.sleep) { return .power }
        if systemUsage.contains(.wakeUp) { return .ok }
        return nil
    }
}

/// Minimal zero-dependency Protobuf binary wire codec + varint length-prefixed framing.
enum ProtobufWire {
    struct ParsedField: Equatable, Sendable {
        let field: Int
        let wireType: Int
        let varint: UInt64
        let bytes: Data
    }

    static func encodeVarint(_ value: UInt64) -> Data {
        var v = value
        var out = Data()
        while v >= 0x80 {
            out.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        out.append(UInt8(v))
        return out
    }

    static func decodeVarint(from data: Data, offset: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var idx = offset
        while idx < data.count {
            let byte = data[data.startIndex + idx]
            idx += 1
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                offset = idx
                return result
            }
            shift += 7
            if shift >= 64 {
                return nil
            }
        }
        return nil
    }

    static func frame(_ payload: Data) -> Data {
        var framed = encodeVarint(UInt64(payload.count))
        framed.append(payload)
        return framed
    }

    static func extractNextFrame(from buffer: inout Data) -> Data? {
        var cursor = 0
        guard let length = decodeVarint(from: buffer, offset: &cursor) else {
            return nil
        }
        guard length <= 2_097_152 else {
            buffer.removeAll()
            return nil
        }
        let msgLen = Int(length)
        let totalEnd = cursor + msgLen
        guard totalEnd <= buffer.count else {
            return nil
        }
        let start = buffer.index(buffer.startIndex, offsetBy: cursor)
        let end = buffer.index(buffer.startIndex, offsetBy: totalEnd)
        let message = Data(buffer[start..<end])
        buffer.removeSubrange(buffer.startIndex..<end)
        return message
    }

    static func appendVarintField(_ field: Int, value: UInt64, to data: inout Data) {
        let tag = UInt64((field << 3) | 0)
        data.append(encodeVarint(tag))
        data.append(encodeVarint(value))
    }

    static func appendBytesField(_ field: Int, value: Data, to data: inout Data) {
        let tag = UInt64((field << 3) | 2)
        data.append(encodeVarint(tag))
        data.append(encodeVarint(UInt64(value.count)))
        data.append(value)
    }

    static func appendStringField(_ field: Int, value: String, to data: inout Data) {
        appendBytesField(field, value: Data(value.utf8), to: &data)
    }

    static func parseFields(from data: Data) -> [ParsedField] {
        var fields: [ParsedField] = []
        var offset = 0
        while offset < data.count {
            guard let tag = decodeVarint(from: data, offset: &offset) else { break }
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x07)
            switch wireType {
            case 0:
                guard let val = decodeVarint(from: data, offset: &offset) else { return fields }
                fields.append(ParsedField(field: fieldNumber, wireType: 0, varint: val, bytes: Data()))
            case 1:
                guard offset + 8 <= data.count else { return fields }
                let s = data.index(data.startIndex, offsetBy: offset)
                let e = data.index(s, offsetBy: 8)
                fields.append(ParsedField(field: fieldNumber, wireType: 1, varint: 0, bytes: Data(data[s..<e])))
                offset += 8
            case 2:
                guard let len = decodeVarint(from: data, offset: &offset), len <= UInt64(data.count - offset) else {
                    return fields
                }
                let s = data.index(data.startIndex, offsetBy: offset)
                let e = data.index(s, offsetBy: Int(len))
                fields.append(ParsedField(field: fieldNumber, wireType: 2, varint: 0, bytes: Data(data[s..<e])))
                offset += Int(len)
            case 5:
                guard offset + 4 <= data.count else { return fields }
                let s = data.index(data.startIndex, offsetBy: offset)
                let e = data.index(s, offsetBy: 4)
                fields.append(ParsedField(field: fieldNumber, wireType: 5, varint: 0, bytes: Data(data[s..<e])))
                offset += 4
            default:
                return fields
            }
        }
        return fields
    }
}

/// Wire builders for Android TV Remote Protocol v2 (`polo.proto` on 6467 & `remotemessage.proto` on 6466).
enum AndroidTVWireMessages {
    /// Feature bits: PING (1) | KEY (2) | IME (4) | POWER (32) | VOLUME (64) | APP_LINK (512) = 615
    static let defaultFeatureMask: UInt64 = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 5) | (1 << 6) | (1 << 9)

    // MARK: Pairing Messages (Port 6467)

    static func pairingRequest(clientName: String) -> Data {
        var req = Data()
        ProtobufWire.appendStringField(1, value: "atvremote", to: &req)
        ProtobufWire.appendStringField(2, value: clientName, to: &req)

        var outer = Data()
        ProtobufWire.appendVarintField(1, value: 2, to: &outer)
        ProtobufWire.appendVarintField(2, value: 200, to: &outer)
        ProtobufWire.appendBytesField(10, value: req, to: &outer)
        return outer
    }

    static func pairingOptions() -> Data {
        var encoding = Data()
        ProtobufWire.appendVarintField(1, value: 3, to: &encoding) // ENCODING_TYPE_HEXADECIMAL
        ProtobufWire.appendVarintField(2, value: 6, to: &encoding) // 6 hex chars

        var opts = Data()
        ProtobufWire.appendBytesField(1, value: encoding, to: &opts)
        ProtobufWire.appendVarintField(3, value: 1, to: &opts) // ROLE_TYPE_INPUT

        var outer = Data()
        ProtobufWire.appendVarintField(1, value: 2, to: &outer)
        ProtobufWire.appendVarintField(2, value: 200, to: &outer)
        ProtobufWire.appendBytesField(20, value: opts, to: &outer)
        return outer
    }

    static func pairingConfiguration() -> Data {
        var encoding = Data()
        ProtobufWire.appendVarintField(1, value: 3, to: &encoding) // ENCODING_TYPE_HEXADECIMAL
        ProtobufWire.appendVarintField(2, value: 6, to: &encoding)

        var cfg = Data()
        ProtobufWire.appendBytesField(1, value: encoding, to: &cfg)
        ProtobufWire.appendVarintField(2, value: 1, to: &cfg) // ROLE_TYPE_INPUT

        var outer = Data()
        ProtobufWire.appendVarintField(1, value: 2, to: &outer)
        ProtobufWire.appendVarintField(2, value: 200, to: &outer)
        ProtobufWire.appendBytesField(30, value: cfg, to: &outer)
        return outer
    }

    static func pairingSecret(_ digest: Data) -> Data {
        var secretMsg = Data()
        ProtobufWire.appendBytesField(1, value: digest, to: &secretMsg)

        var outer = Data()
        ProtobufWire.appendVarintField(1, value: 2, to: &outer)
        ProtobufWire.appendVarintField(2, value: 200, to: &outer)
        ProtobufWire.appendBytesField(40, value: secretMsg, to: &outer)
        return outer
    }

    // MARK: Remote Control Session Messages (Port 6466)

    static func remoteConfigureResponse(activeFeatures: UInt64) -> Data {
        var info = Data()
        ProtobufWire.appendStringField(1, value: "iPhone", to: &info)
        ProtobufWire.appendStringField(2, value: "BluePad", to: &info)
        ProtobufWire.appendVarintField(3, value: 1, to: &info)
        ProtobufWire.appendStringField(4, value: "1", to: &info)
        ProtobufWire.appendStringField(5, value: "atvremote", to: &info)
        ProtobufWire.appendStringField(6, value: "2.0.0", to: &info)

        var cfg = Data()
        ProtobufWire.appendVarintField(1, value: activeFeatures, to: &cfg)
        ProtobufWire.appendBytesField(2, value: info, to: &cfg)

        var msg = Data()
        ProtobufWire.appendBytesField(1, value: cfg, to: &msg)
        return msg
    }

    static func remoteSetActive(_ activeFeatures: UInt64) -> Data {
        var setActive = Data()
        ProtobufWire.appendVarintField(1, value: activeFeatures, to: &setActive)

        var msg = Data()
        ProtobufWire.appendBytesField(2, value: setActive, to: &msg)
        return msg
    }

    static func remotePingResponse(val1: UInt64) -> Data {
        var resp = Data()
        ProtobufWire.appendVarintField(1, value: val1, to: &resp)

        var msg = Data()
        ProtobufWire.appendBytesField(9, value: resp, to: &msg)
        return msg
    }

    static func remoteKeyInject(keyCode: Int32, direction: Int32 = 3) -> Data {
        var inject = Data()
        ProtobufWire.appendVarintField(1, value: UInt64(UInt32(bitPattern: keyCode)), to: &inject)
        ProtobufWire.appendVarintField(2, value: UInt64(UInt32(bitPattern: direction)), to: &inject)

        var msg = Data()
        ProtobufWire.appendBytesField(10, value: inject, to: &msg)
        return msg
    }

    static func remoteImeText(_ text: String, imeCounter: Int32, fieldCounter: Int32) -> Data {
        let len = UInt64(max(0, text.utf16.count))

        var imeObj = Data()
        ProtobufWire.appendVarintField(1, value: len, to: &imeObj)
        ProtobufWire.appendVarintField(2, value: len, to: &imeObj)
        ProtobufWire.appendStringField(3, value: text, to: &imeObj)

        var editInfo = Data()
        ProtobufWire.appendVarintField(1, value: 1, to: &editInfo) // insert
        ProtobufWire.appendBytesField(2, value: imeObj, to: &editInfo)

        var batch = Data()
        ProtobufWire.appendVarintField(1, value: UInt64(UInt32(bitPattern: imeCounter)), to: &batch)
        ProtobufWire.appendVarintField(2, value: UInt64(UInt32(bitPattern: fieldCounter)), to: &batch)
        ProtobufWire.appendBytesField(3, value: editInfo, to: &batch)

        var msg = Data()
        ProtobufWire.appendBytesField(21, value: batch, to: &msg)
        return msg
    }

    static func remoteAppLinkLaunch(_ url: String) -> Data {
        var req = Data()
        ProtobufWire.appendStringField(1, value: url, to: &req)

        var msg = Data()
        ProtobufWire.appendBytesField(90, value: req, to: &msg)
        return msg
    }
}

/// Validation errors for Android TV 6-character HEX pairing codes.
enum AndroidTVPairingCodeError: Error, Equatable, LocalizedError {
    case invalidLength
    case invalidHex
    case codeMismatch

    var errorDescription: String? {
        switch self {
        case .invalidLength:
            return "Eşleştirme kodu 6 karakter olmalıdır."
        case .invalidHex:
            return "Eşleştirme kodu yalnızca 0-9 ve A-F karakterlerinden oluşmalıdır."
        case .codeMismatch:
            return "Eşleştirme kodu veya sertifika özeti eşleşmedi; kodu tekrar kontrol edin."
        }
    }
}

/// Minimal DER ASN.1 builder & PKCS#1 reader for generating compliant self-signed X.509 v3 client certs.
enum ASN1DER {
    struct Node {
        let tag: UInt8
        let value: Data
    }

    static func stripLeadingZeros(_ data: Data) -> Data {
        var idx = data.startIndex
        while idx < data.index(before: data.endIndex) && data[idx] == 0x00 {
            idx = data.index(after: idx)
        }
        return Data(data[idx..<data.endIndex])
    }

    static func encodeLength(_ length: Int) -> Data {
        if length < 0x80 {
            return Data([UInt8(length)])
        }
        var len = length
        var bytes: [UInt8] = []
        while len > 0 {
            bytes.insert(UInt8(len & 0xFF), at: 0)
            len >>= 8
        }
        var out = Data([UInt8(0x80 | bytes.count)])
        out.append(contentsOf: bytes)
        return out
    }

    static func tlv(tag: UInt8, content: Data) -> Data {
        var out = Data([tag])
        out.append(encodeLength(content.count))
        out.append(content)
        return out
    }

    static func sequence(_ content: Data) -> Data {
        tlv(tag: 0x30, content: content)
    }

    static func set(_ content: Data) -> Data {
        tlv(tag: 0x31, content: content)
    }

    static func octetString(_ content: Data) -> Data {
        tlv(tag: 0x04, content: content)
    }

    static func utf8String(_ string: String) -> Data {
        tlv(tag: 0x0C, content: Data(string.utf8))
    }

    static func utcTime(_ ascii: String) -> Data {
        tlv(tag: 0x17, content: Data(ascii.utf8))
    }

    static func integer(unsignedBigEndian data: Data) -> Data {
        var clean = stripLeadingZeros(data)
        if clean.isEmpty {
            clean = Data([0x00])
        } else if (clean[clean.startIndex] & 0x80) != 0 {
            clean.insert(0x00, at: clean.startIndex)
        }
        return tlv(tag: 0x02, content: clean)
    }

    static func bitString(_ data: Data, unusedBits: UInt8 = 0) -> Data {
        var content = Data([unusedBits])
        content.append(data)
        return tlv(tag: 0x03, content: content)
    }

    static func contextExplicit(_ number: UInt8, content: Data) -> Data {
        tlv(tag: 0xA0 | (number & 0x1F), content: content)
    }

    static func readNode(from data: Data, offset: inout Int) -> Node? {
        guard offset < data.count else { return nil }
        let tag = data[data.startIndex + offset]
        offset += 1
        guard offset < data.count else { return nil }
        let firstLen = data[data.startIndex + offset]
        offset += 1

        let length: Int
        if (firstLen & 0x80) == 0 {
            length = Int(firstLen)
        } else {
            let count = Int(firstLen & 0x7F)
            guard count > 0, count <= 4, offset + count <= data.count else { return nil }
            var val = 0
            for i in 0..<count {
                val = (val << 8) | Int(data[data.startIndex + offset + i])
            }
            offset += count
            length = val
        }

        guard offset + length <= data.count else { return nil }
        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: length)
        offset += length
        return Node(tag: tag, value: Data(data[start..<end]))
    }
}

/// Cryptographic helpers for Android TV Remote v2 X.509 certificate creation & Polo secret verification.
enum AndroidTVCrypto {
    /// OID 1.2.840.113549.1.1.1 (rsaEncryption) + NULL
    private static let rsaAlgIdentifier = ASN1DER.sequence(
        Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00])
    )

    /// OID 1.2.840.113549.1.1.11 (sha256WithRSAEncryption) + NULL
    private static let sha256WithRSAAlgIdentifier = ASN1DER.sequence(
        Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B, 0x05, 0x00])
    )

    static func extractRSAModulusAndExponent(fromPKCS1 pkcs1DER: Data) -> (modulus: Data, exponent: Data)? {
        var topOffset = 0
        guard let seq = ASN1DER.readNode(from: pkcs1DER, offset: &topOffset), seq.tag == 0x30 else {
            return nil
        }
        var innerOffset = 0
        guard let modNode = ASN1DER.readNode(from: seq.value, offset: &innerOffset), modNode.tag == 0x02,
              let expNode = ASN1DER.readNode(from: seq.value, offset: &innerOffset), expNode.tag == 0x02 else {
            return nil
        }
        let modulus = ASN1DER.stripLeadingZeros(modNode.value)
        let exponent = ASN1DER.stripLeadingZeros(expNode.value)
        guard !modulus.isEmpty, !exponent.isEmpty else { return nil }
        return (modulus, exponent)
    }

    static func extractRSAPublicKey(from certificate: SecCertificate) -> (modulus: Data, exponent: Data)? {
        guard let pubKey = SecCertificateCopyKey(certificate),
              let extData = SecKeyCopyExternalRepresentation(pubKey, nil) as Data? else {
            return nil
        }
        return extractRSAModulusAndExponent(fromPKCS1: extData)
    }

    static func buildSelfSignedX509DER(privateKey: SecKey, commonName: String = "BluePad") -> Data? {
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let pkcs1Pub = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }

        // Serial number: 8 positive non-zero random bytes
        var serialBytes = [UInt8](repeating: 0, count: 8)
        let status = SecRandomCopyBytes(kSecRandomDefault, serialBytes.count, &serialBytes)
        if status != errSecSuccess {
            serialBytes = [0x42, 0x6C, 0x75, 0x65, 0x50, 0x61, 0x64, 0x01]
        }
        serialBytes[0] = (serialBytes[0] & 0x7F) | 0x01

        // Common Name RDN (OID 2.5.4.3 = 55 04 03)
        var cnAttr = Data([0x06, 0x03, 0x55, 0x04, 0x03])
        cnAttr.append(ASN1DER.utf8String(commonName))
        let nameRDN = ASN1DER.sequence(ASN1DER.set(ASN1DER.sequence(cnAttr)))

        // Validity (2024-01-01 to 2049-12-31)
        var validityContent = ASN1DER.utcTime("240101000000Z")
        validityContent.append(ASN1DER.utcTime("491231235959Z"))
        let validity = ASN1DER.sequence(validityContent)

        // SubjectPublicKeyInfo
        var spkiContent = rsaAlgIdentifier
        spkiContent.append(ASN1DER.bitString(pkcs1Pub))
        let spki = ASN1DER.sequence(spkiContent)

        // Extensions (BasicConstraints CA=false, KeyUsage, ExtendedKeyUsage clientAuth)
        var basicConstraints = Data([0x06, 0x03, 0x55, 0x1D, 0x13, 0x01, 0x01, 0xFF])
        basicConstraints.append(ASN1DER.octetString(ASN1DER.sequence(Data())))

        var keyUsage = Data([0x06, 0x03, 0x55, 0x1D, 0x0F, 0x01, 0x01, 0xFF])
        keyUsage.append(ASN1DER.octetString(ASN1DER.bitString(Data([0xA0]), unusedBits: 5)))

        let clientAuthOID = Data([0x06, 0x08, 0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x02])
        var extKeyUsage = Data([0x06, 0x03, 0x55, 0x1D, 0x25])
        extKeyUsage.append(ASN1DER.octetString(ASN1DER.sequence(clientAuthOID)))

        var extSeqContent = ASN1DER.sequence(basicConstraints)
        extSeqContent.append(ASN1DER.sequence(keyUsage))
        extSeqContent.append(ASN1DER.sequence(extKeyUsage))
        let extensions = ASN1DER.contextExplicit(3, content: ASN1DER.sequence(extSeqContent))

        // Assemble TBSCertificate
        var tbsContent = ASN1DER.contextExplicit(0, content: ASN1DER.integer(unsignedBigEndian: Data([0x02])))
        tbsContent.append(ASN1DER.integer(unsignedBigEndian: Data(serialBytes)))
        tbsContent.append(sha256WithRSAAlgIdentifier)
        tbsContent.append(nameRDN) // issuer
        tbsContent.append(validity)
        tbsContent.append(nameRDN) // subject
        tbsContent.append(spki)
        tbsContent.append(extensions)
        let tbsDER = ASN1DER.sequence(tbsContent)

        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            tbsDER as CFData,
            nil
        ) as Data? else {
            return nil
        }

        var certContent = tbsDER
        certContent.append(sha256WithRSAAlgIdentifier)
        certContent.append(ASN1DER.bitString(signature))
        return ASN1DER.sequence(certContent)
    }

    static func computePairingSecret(
        clientModulus: Data,
        clientExponent: Data,
        serverModulus: Data,
        serverExponent: Data,
        hexCode: String
    ) -> Result<Data, AndroidTVPairingCodeError> {
        let cleaned = hexCode.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        guard cleaned.count == 6 else {
            return .failure(.invalidLength)
        }
        guard let codeBytes = decodeHex(cleaned), codeBytes.count == 3 else {
            return .failure(.invalidHex)
        }

        var hasher = SHA256()
        hasher.update(data: clientModulus)
        hasher.update(data: clientExponent)
        hasher.update(data: serverModulus)
        hasher.update(data: serverExponent)
        hasher.update(data: codeBytes.subdata(in: 1..<3))
        let digest = Data(hasher.finalize())

        guard digest.first == codeBytes[0] else {
            return .failure(.codeMismatch)
        }
        return .success(digest)
    }

    private static func decodeHex(_ hex: String) -> Data? {
        guard hex.count % 2 == 0 else { return nil }
        var data = Data()
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let nextIdx = hex.index(idx, offsetBy: 2)
            guard let byte = UInt8(hex[idx..<nextIdx], radix: 16) else { return nil }
            data.append(byte)
            idx = nextIdx
        }
        return data
    }
}

/// Persistent iOS Keychain RSA-2048 identity store for Android TV Remote v2 mTLS authentication.
enum AndroidTVIdentityStore {
    private static let keyTagData = Data("com.bluepad.ios.atvremote.rsa2048".utf8)
    private static let certLabel = "com.bluepad.ios.atvremote.cert"

    static func loadOrCreateIdentity() -> (identity: SecIdentity, certificate: SecCertificate)? {
        if let existing = findExistingIdentity() {
            return existing
        }

        deleteStoredKeyAndCert()

        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTagData
            ]
        ]

        var keyError: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyAttrs as CFDictionary, &keyError),
              let certDER = AndroidTVCrypto.buildSelfSignedX509DER(privateKey: privateKey, commonName: "BluePad"),
              let cert = SecCertificateCreateWithData(nil, certDER as CFData) else {
            return nil
        }

        let addCertQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: cert,
            kSecAttrLabel as String: certLabel
        ]
        let addStatus = SecItemAdd(addCertQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            return nil
        }

        return findExistingIdentity(matchingCertDER: certDER)
    }

    private static func findExistingIdentity(matchingCertDER targetDER: Data? = nil) -> (SecIdentity, SecCertificate)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let identities = result as? [SecIdentity] else {
            return nil
        }

        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: certLabel,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var certRef: CFTypeRef?
        let expectedDER: Data?
        if let targetDER {
            expectedDER = targetDER
        } else if SecItemCopyMatching(certQuery as CFDictionary, &certRef) == errSecSuccess,
                  let cfRef = certRef,
                  CFGetTypeID(cfRef) == SecCertificateGetTypeID() {
            let storedCert = unsafeBitCast(cfRef, to: SecCertificate.self)
            expectedDER = SecCertificateCopyData(storedCert) as Data
        } else {
            expectedDER = nil
        }

        for identity in identities {
            var idCert: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &idCert) == errSecSuccess, let cert = idCert else {
                continue
            }
            if let expectedDER {
                let der = SecCertificateCopyData(cert) as Data
                if der == expectedDER {
                    return (identity, cert)
                }
            } else {
                return (identity, cert)
            }
        }
        return nil
    }

    private static func deleteStoredKeyAndCert() {
        let certDel: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: certLabel
        ]
        SecItemDelete(certDel as CFDictionary)

        let keyDel: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTagData
        ]
        SecItemDelete(keyDel as CFDictionary)
    }
}
