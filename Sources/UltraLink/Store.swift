import Foundation

/// What UltraLink keeps on disk: a week of per-minute readings and a year of daily totals.
/// Everything stays in ~/Library/Application Support/UltraLink/history.json. Nothing leaves the Mac.
struct StoredHistory: Codable {
    var buckets: [Bucket] = []
    /// "yyyy-MM-dd" → [bytes down, bytes up]
    var daily: [String: [Double]] = [:]
    /// Unix seconds of the newest dish sample already counted.
    var lastSample: Double = 0
    /// Outages the dish reported, kept longer than its own 15-minute buffer.
    var outages: [DishOutage] = []
}

enum Store {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UltraLink", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    static func load() -> StoredHistory {
        guard let data = try? Data(contentsOf: url) else { return StoredHistory() }
        do { return try JSONDecoder().decode(StoredHistory.self, from: data) }
        catch {
            // Keep the unreadable file for inspection instead of silently overwriting it.
            let backup = url.deletingLastPathComponent().appendingPathComponent("history.unreadable.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            NSLog("UltraLink: history.json was unreadable (\(error)); moved to \(backup.path)")
            return StoredHistory()
        }
    }

    static func save(_ h: StoredHistory) {
        do {
            let data = try JSONEncoder().encode(h)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("UltraLink: could not save history: \(error.localizedDescription)")
        }
    }

    static func erase() { try? FileManager.default.removeItem(at: url) }

    static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
}
