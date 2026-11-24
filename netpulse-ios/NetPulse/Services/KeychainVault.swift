import Foundation
import Security

enum ModemValidationError: LocalizedError, Equatable {
    case invalidPrivateHost
    case invalidUsername
    case passwordTooLong
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidPrivateHost:
            return "Güvenlik gereği yalnızca yerel ağ (LAN) IPv4 modem adresine bağlanılabilir (örn. 192.168.2.1)."
        case .invalidUsername:
            return "Geçerli bir modem kullanıcı adı girin."
        case .passwordTooLong:
            return "Modem şifresi 128 karakterden uzun olamaz."
        case .keychainFailure(let status):
            return "iOS Keychain işlem hatası (OSStatus \(status))."
        }
    }
}

/// SSRF koruması: protokol/yol/port önekini temizler ve yalnızca RFC1918 özel IPv4 LAN adreslerine izin verir.
func validatePrivateLANHost(_ host: String) throws -> String {
    var clean = host.trimmingCharacters(in: .whitespacesAndNewlines)
    if let range = clean.range(of: #"^https?://"#, options: [.regularExpression, .caseInsensitive]) {
        clean.removeSubrange(range)
    }
    if let slashIdx = clean.firstIndex(of: "/") {
        clean = String(clean[..<slashIdx])
    }
    if let colonIdx = clean.firstIndex(of: ":") {
        clean = String(clean[..<colonIdx])
    }
    clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)

    let parts = clean.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { throw ModemValidationError.invalidPrivateHost }
    var octets: [Int] = []
    for p in parts {
        guard !p.isEmpty, p.allSatisfy(\.isASCII), p.allSatisfy(\.isNumber),
              let val = Int(p), (0...255).contains(val) else {
            throw ModemValidationError.invalidPrivateHost
        }
        octets.append(val)
    }

    let isPrivateRFC1918 =
        octets[0] == 10
        || (octets[0] == 172 && (16...31).contains(octets[1]))
        || (octets[0] == 192 && octets[1] == 168)

    guard isPrivateRFC1918 else {
        throw ModemValidationError.invalidPrivateHost
    }
    return "\(octets[0]).\(octets[1]).\(octets[2]).\(octets[3])"
}

struct KeychainCredentialPayload: Codable, Equatable, Sendable {
    let host: String
    let username: String
    let password: String
}

/// Modem giriş bilgilerini yalnızca iOS Keychain içinde donanım şifreli saklar; parolayı API/raporlara döndürmez.
final class KeychainVault: @unchecked Sendable {
    private let service: String
    private let account: String

    init(service: String = "com.netpulse.ios.modem", account: String = "modem_credentials") {
        self.service = service
        self.account = account
    }

    func save(host: String, username: String, password: String) throws {
        let cleanHost = try validatePrivateLANHost(host)
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty, cleanUser.count <= 64 else {
            throw ModemValidationError.invalidUsername
        }
        guard password.count <= 128 else {
            throw ModemValidationError.passwordTooLong
        }

        let payload = KeychainCredentialPayload(host: cleanHost, username: cleanUser, password: password)
        let data = try JSONEncoder().encode(payload)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw ModemValidationError.keychainFailure(updateStatus)
            }
        } else {
            var newItem = query.merging(attrs) { _, new in new }
            newItem[kSecAttrLabel as String] = "NetPulse Modem (\(cleanHost))"
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw ModemValidationError.keychainFailure(addStatus)
            }
        }
    }

    func load() -> KeychainCredentialPayload? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let decoded = try? JSONDecoder().decode(KeychainCredentialPayload.self, from: data),
              let validHost = try? validatePrivateLANHost(decoded.host) else {
            return nil
        }
        return KeychainCredentialPayload(host: validHost, username: decoded.username, password: decoded.password)
    }

    func metadata() -> (saved: Bool, host: String?, username: String?) {
        guard let loaded = load() else { return (false, nil, nil) }
        return (true, loaded.host, loaded.username)
    }

    @discardableResult
    func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
