import Foundation

// Remote blocklist sync. Lives in the host app (not the extension) because
// Call Directory Extensions run in a tight memory/time budget and shouldn't
// make network calls. The app pulls the latest list, merges into the shared
// BlocklistStore, and the extension reads from that on its next reload.

struct RemoteBlocklistEntry: Decodable {
    let number: String
    let label: String
}

struct RemoteBlocklistResponse: Decodable {
    let version: String
    let count: Int
    let numbers: [RemoteBlocklistEntry]
}

enum RemoteSyncError: LocalizedError {
    case notConfigured
    case unauthorized
    case http(Int)
    case decode(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Server URL or API key not set."
        case .unauthorized:  return "Server rejected the API key."
        case .http(let code): return "Server returned HTTP \(code)."
        case .decode(let err): return "Couldn't parse server response: \(err.localizedDescription)"
        case .transport(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}

struct SyncResult {
    let remoteCount: Int
    let totalAfterMerge: Int
    let newlyAdded: Int
}

enum RemoteSync {
    static func sync() async throws -> SyncResult {
        let store = BlocklistStore.shared
        guard let baseURL = store.serverURL, !store.apiKey.isEmpty else {
            throw RemoteSyncError.notConfigured
        }

        var req = URLRequest(url: baseURL.appendingPathComponent("api/blocklist"))
        req.setValue("Bearer \(store.apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw RemoteSyncError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RemoteSyncError.http(0)
        }
        if http.statusCode == 401 { throw RemoteSyncError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw RemoteSyncError.http(http.statusCode)
        }

        let decoded: RemoteBlocklistResponse
        do {
            decoded = try JSONDecoder().decode(RemoteBlocklistResponse.self, from: data)
        } catch {
            throw RemoteSyncError.decode(error)
        }

        // Build remote map; ignore entries that don't parse as Int64.
        var remoteByNumber: [Int64: String] = [:]
        for entry in decoded.numbers {
            if let n = Int64(entry.number) {
                remoteByNumber[n] = entry.label
            }
        }

        // Merge: remote is authoritative for labels on numbers it knows about,
        // but local-only numbers (added directly on the phone) are kept.
        let existingBlocked = Set(store.blockedNumbers())
        var labeledByNumber = Dictionary(
            store.labeledNumbers().map { ($0.number, $0.label) },
            uniquingKeysWith: { first, _ in first }
        )

        var merged = existingBlocked
        var newlyAdded = 0
        for (n, label) in remoteByNumber {
            if !merged.contains(n) { newlyAdded += 1 }
            merged.insert(n)
            labeledByNumber[n] = label
        }

        let sortedNumbers = merged.sorted()
        store.setBlockedNumbers(sortedNumbers)
        store.setLabeledNumbers(labeledByNumber.map { LabeledNumber(number: $0.key, label: $0.value) })
        store.setLastSyncedAt(Date())

        return SyncResult(
            remoteCount: decoded.count,
            totalAfterMerge: sortedNumbers.count,
            newlyAdded: newlyAdded
        )
    }
}
