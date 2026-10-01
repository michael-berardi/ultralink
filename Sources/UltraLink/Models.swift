import Foundation

enum DishError: LocalizedError {
    case malformed(String)
    case unreachable(String)
    case grpc(Int, String)
    case http(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .malformed(let m): return "The dish sent data UltraLink could not read (\(m))."
        case .unreachable(let m): return m
        case .grpc(let code, let m): return "The dish refused the request (gRPC status \(code)\(m.isEmpty ? "" : ": \(m)"))."
        case .http(let c): return "The dish answered with HTTP \(c)."
        case .emptyResponse: return "The dish answered with an empty response."
        }
    }
}

/// One reading of the dish: everything the live view shows.
struct DishStatus: Equatable {
    var dishID = ""
    var hardware = ""
    var software = ""
    var country = ""
    var uptime: TimeInterval = 0
    var downBps = 0.0
    var upBps = 0.0
    var latencyMs = 0.0
    var dropRate = 0.0
    var fractionObstructed = 0.0
    var currentlyObstructed = false
    var azimuth = 0.0
    var elevation = 0.0
    var desiredAzimuth: Double?
    var desiredElevation: Double?
    var tilt: Double?
    var gpsValid = false
    var gpsSats = 0
    var ethernetMbps = 0
    var snrAboveNoise = true
    var snrPersistentlyLow = false
    var disablement = 1
    var outageCause: Int?
    var alerts: [DishAlert] = []
    var updateState = 1
    var connectedRouters = 0
    var downRestricted = false
    var upRestricted = false
    var readyStates: [String: Bool] = [:]
    var received = Date()

    var disablementText: String? { DishNames.disablement[disablement] }
    var hardwareName: String { DishNames.hardware(hardware) }
}

struct DishAlert: Equatable, Identifiable {
    var id: String { key }
    let key: String
    let title: String
    let critical: Bool
}

/// The 15-minute ring buffer the dish keeps: one sample per second.
struct DishHistory {
    var current: UInt64 = 0
    var dropRate: [Float] = []
    var latencyMs: [Float] = []
    var downBps: [Float] = []
    var upBps: [Float] = []
    var powerW: [Float] = []
    var outages: [DishOutage] = []

    /// The most recent `count` samples, oldest first, as indices into the arrays.
    func recentIndices(_ count: Int) -> [Int] {
        let size = downBps.count
        guard size > 0 else { return [] }
        let n = min(count, size, Int(clamping: current))
        guard n > 0 else { return [] }
        return (0..<n).map { k in Int((current - UInt64(n - k)) % UInt64(size)) }
    }
}

struct DishOutage: Equatable, Identifiable, Codable {
    var id: Date { start }
    let cause: Int
    let start: Date
    let duration: TimeInterval
    var causeText: String { DishNames.outageCause[cause] ?? "Unknown" }
}

struct ObstructionMap {
    var rows = 0
    var cols = 0
    var snr: [Float] = []
    var maxThetaDeg = 80.0
    var minElevationDeg = 10.0
}

enum DishNames {
    static let disablement: [Int: String] = [
        2: "No active Starlink account", 3: "Too far from the service address", 4: "In the ocean",
        6: "Service blocked in this country", 7: "Data overage policy", 8: "Cell disabled", 10: "Roaming restricted",
        11: "Location unknown", 12: "Account disabled", 13: "Unsupported software version",
        14: "Moving too fast for the plan", 15: "Aviation limits", 16: "Blocked area",
    ]
    static let outageCause: [Int: String] = [
        1: "Booting", 2: "Stowed", 3: "Thermal shutdown", 4: "No satellite schedule", 5: "No satellites",
        6: "Obstructed", 7: "No downlink", 8: "No pings", 9: "Motors moving", 10: "Cable test",
        11: "Sleeping", 13: "Searching the sky", 14: "RF inhibited",
    ]
    static let updateState: [Int: String] = [
        1: "Up to date", 2: "Downloading an update", 3: "Preparing an update", 4: "Installing an update",
        5: "Checking an update", 6: "Restart needed", 7: "Updates disabled", 8: "Update failed",
    ]
    static func hardware(_ id: String) -> String {
        if id.hasPrefix("rev4_panda") { return "Standard (Gen 3)" }
        if id.hasPrefix("rev3_proto") || id.hasPrefix("rev2_proto") { return "Standard (Gen 2)" }
        if id.hasPrefix("rev1_pre") || id.hasPrefix("rev1_proto") { return "Original (Gen 1)" }
        if id.hasPrefix("mini") { return "Mini" }
        if id.hasPrefix("rev3_") { return "Standard (Gen 2)" }
        return id.isEmpty ? "Starlink" : id
    }
}

/// Which health the menu bar icon shows.
enum LinkState: Equatable {
    case connecting
    case online
    case degraded(String)
    case outage(String)
    case offline(String)

    var isProblem: Bool {
        switch self { case .outage, .offline: return true; default: return false }
    }
    var title: String {
        switch self {
        case .connecting: return "Connecting…"
        case .online: return "Online"
        case .degraded: return "Degraded"
        case .outage: return "Outage"
        case .offline: return "Dish not found"
        }
    }
    var detail: String? {
        switch self {
        case .degraded(let s), .outage(let s), .offline(let s): return s
        default: return nil
        }
    }
}

/// One minute of history stored as sums, so partial minutes merge exactly and a week stays small.
struct Bucket: Codable, Equatable {
    var t: Int            // minute since the Unix epoch
    var n = 0             // seconds summed
    var down = 0.0        // sum of bits per second, one sample per second
    var up = 0.0
    var lat = 0.0         // sum of ms over the seconds that had a reply
    var latN = 0
    var drop = 0.0        // sum of ping-loss fractions
    var power = 0.0       // sum of watts
    var powerN = 0

    var date: Date { Date(timeIntervalSince1970: TimeInterval(t) * 60) }
    var downMean: Double { n > 0 ? down / Double(n) : 0 }
    var upMean: Double { n > 0 ? up / Double(n) : 0 }
    var latMean: Double? { latN > 0 ? lat / Double(latN) : nil }
    var dropMean: Double { n > 0 ? drop / Double(n) : 0 }
    var powerMean: Double? { powerN > 0 ? power / Double(powerN) : nil }
}
