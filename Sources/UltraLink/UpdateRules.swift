import Foundation

/// Rules shared by the updater and the standalone tests. Sparkle owns the feed, the daily schedule,
/// skip and remind state, signature checks and the install; these rules cover what UltraLink adds.
enum UpdateRules {
    /// Only stable `x.y.z` versions count, and only when strictly newer. Anything else is not newer.
    static func isNewer(_ available: String, than current: String) -> Bool {
        guard let a = parts(available), let b = parts(current) else { return false }
        return b.lexicographicallyPrecedes(a)
    }

    private static func parts(_ version: String) -> [Int]? {
        let fields = version.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3, fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0 >= "0" && $0 <= "9" } }) else { return nil }
        let numbers = fields.compactMap { Int($0) }
        return numbers.count == 3 ? numbers : nil
    }

    static func notice(available: String, current: String) -> String {
        "UltraLink \(available) is available — you have \(current)."
    }

    /// Scheduled background checks are off under CI, with `ULTRALINK_NO_UPDATE_CHECK=1`, and in the
    /// `--show-…`/`--snapshot` QA modes unless `--scheduled-check` asks for one. Check Now always works.
    static func backgroundChecksAllowed(environment: [String: String], arguments: [String]) -> Bool {
        if environment["CI"] != nil || environment["ULTRALINK_NO_UPDATE_CHECK"] == "1" { return false }
        if arguments.contains("--scheduled-check") { return true }
        return !arguments.contains { $0 == "--snapshot" || $0.hasPrefix("--show-") }
    }
}
