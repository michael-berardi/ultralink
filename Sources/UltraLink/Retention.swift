import Foundation

/// Bounded lifetimes for everything UltraLink leaves on this Mac outside the rolling history file.
///
/// `history.json` prunes itself while the app runs (one week of per-minute buckets, 400 daily
/// totals, 200 outages). Everything else is covered here: `sweep()` runs once at launch and
/// removes anything older than its bound, so update downloads, unreadable-history copies and
/// temporary files cannot pile up. Sweep only deletes: it never creates a directory and never
/// writes a file, and it is skipped in demo mode. Each file is judged by its own modification
/// date, so an old folder cannot take a freshly downloaded update with it.
enum Retention {
    /// An unreadable-history copy is kept a week so it can be inspected, then removed.
    static let unreadableHistory: TimeInterval = 7 * 86_400
    /// A downloaded or half-downloaded update in the app cache is removed after a week.
    static let updateDownload: TimeInterval = 7 * 86_400
    /// Temporary files UltraLink itself creates (none today) live at most a day.
    static let temporary: TimeInterval = 86_400

    /// The backup `Store.load()` writes when `history.json` cannot be decoded.
    static let unreadableName = "history.unreadable.json"

    /// Sparkle's per-app cache, where a downloaded update waits: `~/Library/Caches/<bundle id>`.
    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.libertydesignstudio.ultralink",
                                           isDirectory: true)
    }

    /// Private scratch space; no file is kept here today.
    static var temporaryDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("UltraLink", isDirectory: true)
    }

    /// Removes entries in `directory` whose modification date is older than `age`, optionally
    /// limited to `names`. Returns the removed paths; nested paths are relative to `directory`.
    /// A missing directory is not an error, and nothing is created. Folders are walked file by
    /// file: stale files go, fresh files (and their folders) stay, and an emptied old folder is
    /// removed. Symbolic links are treated as files and never followed.
    @discardableResult
    static func removeStale(in directory: URL, olderThan age: TimeInterval, names: Set<String>? = nil,
                            now: Date = Date(), fileManager: FileManager = .default) -> [String] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? fileManager.contentsOfDirectory(at: directory,
                                                                 includingPropertiesForKeys: Array(keys))
        else { return [] }
        var removed: [String] = []
        for entry in entries {
            if let names, !names.contains(entry.lastPathComponent) { continue }
            guard let values = try? entry.resourceValues(forKeys: keys),
                  let modified = values.contentModificationDate else { continue }
            if values.isDirectory == true && values.isSymbolicLink != true {
                // A folder's date says when its contents last changed, not when a nested download
                // was written. Look at the files before deleting an apparently old folder.
                let nested = removeStale(in: entry, olderThan: age, now: now, fileManager: fileManager)
                removed += nested.map { "\(entry.lastPathComponent)/\($0)" }
                let empty = (try? fileManager.contentsOfDirectory(atPath: entry.path))?.isEmpty == true
                if empty, now.timeIntervalSince(modified) > age,
                   (try? fileManager.removeItem(at: entry)) != nil {
                    removed.append(entry.lastPathComponent)
                }
            } else if now.timeIntervalSince(modified) > age,
                      (try? fileManager.removeItem(at: entry)) != nil {
                removed.append(entry.lastPathComponent)
            }
        }
        return removed
    }

    /// The launch sweep, before any update check: stale unreadable-history copies, stale update
    /// downloads and stale temporary files. Returns the paths it removed.
    @discardableResult
    static func sweep(now: Date = Date(), historyDirectory: URL = Store.directoryPath,
                      cache: URL = cacheDirectory, temp: URL = temporaryDirectory,
                      fileManager: FileManager = .default) -> [String] {
        var removed = removeStale(in: historyDirectory, olderThan: unreadableHistory,
                                  names: [unreadableName], now: now, fileManager: fileManager)
        removed += removeStale(in: cache, olderThan: updateDownload, now: now, fileManager: fileManager)
        removed += removeStale(in: temp, olderThan: temporary, now: now, fileManager: fileManager)
        return removed
    }
}
