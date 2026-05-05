import Foundation

// Shared between the host app and the Call Directory Extension via App Group.
// The extension reads this on every reload to know which numbers to block / label.

struct LabeledNumber: Codable, Equatable {
    let number: Int64
    let label: String
}

enum BlocklistStoreError: Error {
    case appGroupUnavailable
}

final class BlocklistStore {
    static let appGroup = "group.com.thomashart.SpamShield"
    static let shared = BlocklistStore()

    private static let blockedKey = "blockedNumbers"
    private static let labeledKey = "labeledNumbers"

    private let defaults: UserDefaults

    private init() {
        guard let suite = UserDefaults(suiteName: Self.appGroup) else {
            // App Group misconfigured. Fall back to standard so we don't crash the extension,
            // but reads/writes here won't cross the app/extension boundary until fixed.
            self.defaults = .standard
            return
        }
        self.defaults = suite
    }

    func blockedNumbers() -> [Int64] {
        guard let raw = defaults.array(forKey: Self.blockedKey) as? [NSNumber] else { return [] }
        return raw.map { $0.int64Value }
    }

    func setBlockedNumbers(_ numbers: [Int64]) {
        let raw = numbers.map { NSNumber(value: $0) }
        defaults.set(raw, forKey: Self.blockedKey)
    }

    func labeledNumbers() -> [LabeledNumber] {
        guard let data = defaults.data(forKey: Self.labeledKey),
              let decoded = try? JSONDecoder().decode([LabeledNumber].self, from: data)
        else { return [] }
        return decoded
    }

    func setLabeledNumbers(_ entries: [LabeledNumber]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.labeledKey)
    }

    // MARK: - Server config (host app only; extension never makes network calls)

    private static let serverURLKey = "serverURL"
    private static let apiKeyKey = "apiKey"
    private static let lastSyncKey = "lastSyncedAt"

    var serverURL: URL? {
        guard let s = defaults.string(forKey: Self.serverURLKey),
              let u = URL(string: s)
        else { return nil }
        return u
    }

    var apiKey: String {
        defaults.string(forKey: Self.apiKeyKey) ?? ""
    }

    var lastSyncedAt: Date? {
        defaults.object(forKey: Self.lastSyncKey) as? Date
    }

    func setServerConfig(url: String, apiKey: String) {
        defaults.set(url.trimmingCharacters(in: .whitespaces), forKey: Self.serverURLKey)
        defaults.set(apiKey.trimmingCharacters(in: .whitespaces), forKey: Self.apiKeyKey)
    }

    func setLastSyncedAt(_ date: Date) {
        defaults.set(date, forKey: Self.lastSyncKey)
    }
}
