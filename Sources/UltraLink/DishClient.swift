import Foundation

/// Where readings come from: the real dish, or the built-in demo.
protocol DishSource: Sendable {
    func status() async throws -> DishStatus
    func history() async throws -> DishHistory
    func obstructionMap() async throws -> ObstructionMap
}

/// Talks to the dish's local gRPC-web endpoint (`SpaceX.API.Device.Device/Handle`, port 9201).
/// The API is unofficial and read-only here: UltraLink never sends a command that changes the dish.
struct DishClient: DishSource {
    var host: String
    var port = 9201
    var timeout: TimeInterval = 4

    private enum Request {
        static let getStatus = 1004
        static let getHistory = 1007
        static let getObstructionMap = 2008
    }
    private enum Response {
        static let status = 2004
        static let history = 2006
        static let obstructionMap = 2008
    }

    func status() async throws -> DishStatus {
        var r = try await call(Request.getStatus, expect: Response.status)
        return try Self.decodeStatus(&r)
    }

    func history() async throws -> DishHistory {
        var r = try await call(Request.getHistory, expect: Response.history)
        return try Self.decodeHistory(&r)
    }

    func obstructionMap() async throws -> ObstructionMap {
        var r = try await call(Request.getObstructionMap, expect: Response.obstructionMap)
        return try Self.decodeObstructionMap(&r)
    }

    // MARK: Transport

    private func call(_ requestField: Int, expect responseField: Int) async throws -> PBReader {
        let reply = try await Transport.post(host: host, port: port, path: "/SpaceX.API.Device.Device/Handle",
                                             headers: ["Content-Type": "application/grpc-web+proto", "X-Grpc-Web": "1"],
                                             body: Self.frame(pbEmptySubmessage(field: requestField)), timeout: timeout)
        guard reply.status == 200 else { throw DishError.http(reply.status) }
        if let s = reply.headers["grpc-status"], let code = Int(s), code != 0 {
            throw DishError.grpc(code, reply.headers["grpc-message"] ?? "")
        }
        let data = reply.body

        var message: Data?
        var offset = 0
        while offset + 5 <= data.count {
            let flag = data[data.startIndex + offset]
            let len = (0..<4).reduce(0) { ($0 << 8) | Int(data[data.startIndex + offset + 1 + $1]) }
            offset += 5
            guard offset + len <= data.count else { throw DishError.malformed("truncated gRPC frame") }
            let payload = data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + len))
            offset += len
            if flag & 0x80 != 0 {
                let text = String(decoding: payload, as: UTF8.self)
                for line in text.split(whereSeparator: \.isNewline) {
                    let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2, parts[0].lowercased() == "grpc-status", let code = Int(parts[1]), code != 0 {
                        let msg = text.split(whereSeparator: \.isNewline).first { $0.lowercased().hasPrefix("grpc-message") }
                            .map { String($0.drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces) } ?? ""
                        throw DishError.grpc(code, msg.removingPercentEncoding ?? msg)
                    }
                }
            } else { message = payload }
        }
        guard let message else { throw DishError.emptyResponse }

        var r = PBReader(message)
        while let (n, v) = try r.next() {
            if n == responseField, let sub = v.message { return sub }
        }
        throw DishError.malformed("no field \(responseField) in the reply")
    }

    static func frame(_ message: Data) -> Data {
        var d = Data([0])
        let n = UInt32(message.count)
        d.append(contentsOf: [UInt8(n >> 24 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)])
        d.append(message)
        return d
    }

    // MARK: Decoding

    static func decodeStatus(_ r: inout PBReader) throws -> DishStatus {
        var s = DishStatus()
        while let (n, v) = try r.next() {
            switch n {
            case 1: // device_info
                guard var m = v.message else { break }
                while let (k, x) = try m.next() {
                    switch k {
                    case 1: s.dishID = x.string ?? ""
                    case 2: s.hardware = x.string ?? ""
                    case 3: s.software = x.string ?? ""
                    case 4: s.country = x.string ?? ""
                    default: break
                    }
                }
            case 2: // device_state
                guard var m = v.message else { break }
                while let (k, x) = try m.next() { if k == 1 { s.uptime = TimeInterval(x.uint ?? 0) } }
            case 1004: // obstruction_stats
                guard var m = v.message else { break }
                while let (k, x) = try m.next() {
                    if k == 1 { s.fractionObstructed = x.double ?? 0 }
                    if k == 5 { s.currentlyObstructed = x.bool ?? false }
                }
            case 1005: // alerts
                guard var m = v.message else { break }
                while let (k, x) = try m.next() {
                    if x.bool == true, let a = alertTable[k] { s.alerts.append(DishAlert(key: a.0, title: a.1, critical: a.2)) }
                }
            case 1014: // outage
                guard var m = v.message else { break }
                while let (k, x) = try m.next() { if k == 1 { s.outageCause = x.int } }
            case 1015: // gps_stats
                guard var m = v.message else { break }
                while let (k, x) = try m.next() {
                    if k == 1 { s.gpsValid = x.bool ?? false }
                    if k == 2 { s.gpsSats = x.int ?? 0 }
                }
            case 1003: s.dropRate = v.double ?? 0
            case 1007: s.downBps = v.double ?? 0
            case 1008: s.upBps = v.double ?? 0
            case 1009: s.latencyMs = v.double ?? 0
            case 1011: s.azimuth = v.double ?? 0
            case 1012: s.elevation = v.double ?? 0
            case 1016: s.ethernetMbps = v.int ?? 0
            case 1018: s.snrAboveNoise = v.bool ?? true
            case 1022: s.snrPersistentlyLow = v.bool ?? false
            case 1019: // ready_states
                guard var m = v.message else { break }
                while let (k, x) = try m.next() {
                    if let name = ["cady", "scp", "l1l2", "xphy", "aap", "rf"][safe: k - 1] { s.readyStates[name] = x.bool ?? false }
                }
            case 1021: s.updateState = v.int ?? 1
            case 1024: s.disablement = v.int ?? 1
            case 1027: // alignment_stats
                guard var m = v.message else { break }
                while let (k, x) = try m.next() {
                    if k == 3 { s.tilt = x.double }
                    if k == 8 { s.desiredAzimuth = x.double }
                    if k == 9 { s.desiredElevation = x.double }
                }
            case 1040: s.connectedRouters += 1
            case 1044: s.downRestricted = (v.int ?? 1) > 1
            case 1045: s.upRestricted = (v.int ?? 1) > 1
            default: break
            }
        }
        s.received = Date()
        return s
    }

    static func decodeHistory(_ r: inout PBReader) throws -> DishHistory {
        var h = DishHistory()
        while let (n, v) = try r.next() {
            switch n {
            case 1: h.current = v.uint ?? 0
            case 1001: PBReader.appendFloats(v, to: &h.dropRate)
            case 1002: PBReader.appendFloats(v, to: &h.latencyMs)
            case 1003: PBReader.appendFloats(v, to: &h.downBps)
            case 1004: PBReader.appendFloats(v, to: &h.upBps)
            case 1010: PBReader.appendFloats(v, to: &h.powerW)
            case 1009:
                guard var m = v.message else { break }
                var cause = 0, start: Int64 = 0, dur: UInt64 = 0
                while let (k, x) = try m.next() {
                    if k == 1 { cause = x.int ?? 0 }
                    if k == 2 { start = Int64(bitPattern: x.uint ?? 0) }
                    if k == 3 { dur = x.uint ?? 0 }
                }
                // Outage times are GPS nanoseconds: the Unix epoch is 315 964 782 s later (GPS epoch less 18 leap seconds).
                let unix = Double(start) / 1e9 + 315_964_782
                h.outages.append(DishOutage(cause: cause, start: Date(timeIntervalSince1970: unix), duration: Double(dur) / 1e9))
            default: break
            }
        }
        return h
    }

    static func decodeObstructionMap(_ r: inout PBReader) throws -> ObstructionMap {
        var m = ObstructionMap()
        while let (n, v) = try r.next() {
            switch n {
            case 1: m.rows = v.int ?? 0
            case 2: m.cols = v.int ?? 0
            case 3: PBReader.appendFloats(v, to: &m.snr)
            case 4: m.minElevationDeg = v.double ?? 10
            case 5: m.maxThetaDeg = v.double ?? 80
            default: break
            }
        }
        guard m.rows > 0, m.cols > 0, m.snr.count >= m.rows * m.cols else { throw DishError.malformed("obstruction map is incomplete") }
        return m
    }

    /// Field number → (key, text, critical) for `DishAlerts`.
    static let alertTable: [Int: (String, String, Bool)] = [
        1: ("motors_stuck", "Motors are stuck", true),
        2: ("thermal_shutdown", "Overheated and shut down", true),
        3: ("thermal_throttle", "Slowed down by heat", false),
        4: ("unexpected_location", "Dish is not at its service address", true),
        5: ("mast_not_near_vertical", "Mast is not vertical", false),
        6: ("slow_ethernet_speeds", "Ethernet link is slower than 1 Gbps", false),
        7: ("roaming", "Roaming outside the service area", false),
        8: ("install_pending", "Installation is pending", false),
        9: ("is_heating", "Melting snow", false),
        10: ("power_supply_thermal_throttle", "Power supply is slowing down from heat", false),
        11: ("is_power_save_idle", "Sleeping in power save", false),
        14: ("dbf_telem_stale", "Antenna telemetry is stale", false),
        16: ("low_motor_current", "Motor current is low", false),
        17: ("lower_signal_than_predicted", "Signal is weaker than predicted", false),
        18: ("slow_ethernet_speeds_100", "Ethernet link is running at 100 Mbps", false),
        19: ("obstruction_map_reset", "Obstruction map was reset", false),
        20: ("dish_water_detected", "Water detected in the dish", true),
        21: ("router_water_detected", "Water detected in the router", true),
        22: ("upsu_router_port_slow", "Router port is slow", false),
        23: ("no_ethernet_link", "No Ethernet link", true),
    ]
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
