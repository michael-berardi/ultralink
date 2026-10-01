import Foundation

enum Fmt {
    /// "142 Mbps" style: the unit is chosen once so the digits stay steady.
    static func rate(_ bps: Double) -> (value: String, unit: String) {
        let units = [("bps", 1.0), ("Kbps", 1e3), ("Mbps", 1e6), ("Gbps", 1e9)]
        var idx = 0
        for (i, u) in units.enumerated() where bps >= u.1 { idx = i }
        let v = bps / units[idx].1
        let text = v >= 100 || idx == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)
        return (text, units[idx].0)
    }

    static func rateText(_ bps: Double) -> String { let r = rate(bps); return "\(r.value) \(r.unit)" }

    /// Compact for the menu bar: always Mbps with no unit, e.g. "142" or "4.2".
    static func mbps(_ bps: Double) -> String {
        let m = bps / 1e6
        return m >= 100 ? String(format: "%.0f", m) : m >= 10 ? String(format: "%.0f", m) : String(format: "%.1f", m)
    }

    static func bytes(_ b: Double) -> String {
        let f = ByteCountFormatter(); f.countStyle = .decimal; f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f.string(fromByteCount: Int64(b))
    }

    static func duration(_ s: TimeInterval) -> String {
        let t = Int(s.rounded())
        if t < 60 { return "\(t)s" }
        if t < 3600 { return "\(t / 60)m \(t % 60)s" }
        if t < 86400 { return "\(t / 3600)h \((t % 3600) / 60)m" }
        return "\(t / 86400)d \((t % 86400) / 3600)h"
    }

    static func percent(_ f: Double) -> String {
        let p = f * 100
        return p == 0 ? "0%" : p < 0.1 ? "<0.1%" : p < 10 ? String(format: "%.1f%%", p) : String(format: "%.0f%%", p)
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.timeStyle = .short
        f.dateStyle = Calendar.current.isDateInToday(d) ? .none : .short
        return f.string(from: d)
    }

    static func compass(_ az: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let a = (az.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return names[Int((a + 22.5) / 45) % 8]
    }
}
