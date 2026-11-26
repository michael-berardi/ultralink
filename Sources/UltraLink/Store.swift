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
    static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UltraLink", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            // createDirectory does not change an existing directory's mode.
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        } catch { NSLog("UltraLink: could not protect the history directory") }
        return dir
    }

    static var url: URL { directory.appendingPathComponent("history.json") }

    static func protect(_ url: URL, _ mode: Int) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    static func load() -> StoredHistory {
        guard let data = try? Data(contentsOf: url) else { return StoredHistory() }
        do { return try JSONDecoder().decode(StoredHistory.self, from: data) }
        catch {
            // Keep the unreadable file for inspection instead of silently overwriting it.
            let backup = url.deletingLastPathComponent().appendingPathComponent("history.unreadable.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            protect(backup, 0o600)
            NSLog("UltraLink: history.json was unreadable; kept a private backup")
            return StoredHistory()
        }
    }

    static func save(_ h: StoredHistory) {
        do {
            let data = try JSONEncoder().encode(h)
            protect(url, 0o600)
            try data.write(to: url, options: .atomic)
            protect(url, 0o600)
        } catch {
            NSLog("UltraLink: could not save history")
        }
    }

    static func erase() {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("history.unreadable.json"))
    }

    static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
}
