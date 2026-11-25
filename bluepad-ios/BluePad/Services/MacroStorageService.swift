import Foundation

/// Atomic JSON persistence under `Application Support/BluePad/`.
final class MacroStorageService {
    private let directoryURL: URL
    private let settingsURL: URL
    private let macrosURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseDirectory: URL? = nil) {
        let root = baseDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("BluePad", isDirectory: true)
        self.directoryURL = root
        self.settingsURL = root.appendingPathComponent("settings.json")
        self.macrosURL = root.appendingPathComponent("macros.json")

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc
        self.decoder = JSONDecoder()
    }

    func loadSettings() -> BluePadSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              var decoded = try? decoder.decode(BluePadSettings.self, from: data) else {
            return .default
        }
        decoded.clampToValidRanges()
        return decoded
    }

    func saveSettings(_ settings: BluePadSettings) {
        var clamped = settings
        clamped.clampToValidRanges()
        writeJSON(clamped, to: settingsURL)
    }

    func loadMacros() -> [CustomMacro] {
        guard let data = try? Data(contentsOf: macrosURL),
              let decoded = try? decoder.decode([CustomMacro].self, from: data),
              !decoded.isEmpty else {
            return CustomMacro.defaultPresets
        }
        return decoded
    }

    func saveMacros(_ macros: [CustomMacro]) {
        writeJSON(macros, to: macrosURL)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            // Non-fatal persistence failure; keep operating with in-memory state.
        }
    }
}
