import Foundation

/// A believable dish for first launch without Starlink, for screenshots and for trying the app.
/// Turn it on in Settings or launch with `--demo`. Nothing is written to disk in demo mode.
struct DemoDish: DishSource {
    let start = Date()

    private func wave(_ t: Double, _ period: Double, _ phase: Double = 0) -> Double { sin(t / period * 2 * .pi + phase) }

    private func down(at t: Double) -> Double { max(8e6, 168e6 + 70e6 * wave(t, 90) + 28e6 * wave(t, 17, 1.3) + 12e6 * wave(t, 5.3)) }
    private func up(at t: Double) -> Double { max(0.4e6, 17e6 + 8e6 * wave(t, 70, 2) + 3e6 * wave(t, 11)) }
    private func latency(at t: Double) -> Double { 31 + 7 * wave(t, 40) + 4 * wave(t, 6.5, 0.7) }

    func status() async throws -> DishStatus {
        let t = Date().timeIntervalSince1970
        var s = DishStatus()
        s.dishID = "ut01234567-89abcdef-demo"
        s.hardware = "rev4_panda_prod2"
        s.software = "2026.07.06.mr81950"
        s.country = "US"
        s.uptime = Date().timeIntervalSince(start) + 3 * 86400 + 4 * 3600
        s.downBps = down(at: t); s.upBps = up(at: t); s.latencyMs = latency(at: t)
        s.fractionObstructed = 0.012
        s.azimuth = 358.6; s.elevation = 76.7; s.desiredAzimuth = 0.1; s.desiredElevation = 76.0; s.tilt = 14.1
        s.gpsValid = true; s.gpsSats = 19; s.ethernetMbps = 1000
        s.connectedRouters = 2
        s.readyStates = ["scp": true, "l1l2": true, "xphy": true, "aap": true, "rf": true]
        return s
    }

    func history() async throws -> DishHistory {
        let now = Date().timeIntervalSince1970
        let current = UInt64(1_000_000 + Int(now - start.timeIntervalSince1970))
        var h = DishHistory(current: current)
        for k in 0..<900 {
            let a = current - 900 + UInt64(k)
            let t = now - Double(899 - k)
            let gap = (840...852).contains(k) // a 12 s stall about a minute ago
            h.downBps.append(Float(gap ? 0 : down(at: t)))
            h.upBps.append(Float(gap ? 0 : up(at: t)))
            h.latencyMs.append(Float(gap ? 0 : latency(at: t)))
            h.dropRate.append(gap ? 1 : (k % 97 == 0 ? 0.04 : 0))
            h.powerW.append(Float(38 + 4 * wave(t, 120)))
            _ = a
        }
        // The ring is indexed by counter modulo its length; rotate so recentIndices lines up.
        let shift = Int(current % 900)
        func rot(_ a: [Float]) -> [Float] { let r = a.count - shift; return Array(a[r...] + a[..<r]) }
        h.downBps = rot(h.downBps); h.upBps = rot(h.upBps); h.latencyMs = rot(h.latencyMs); h.dropRate = rot(h.dropRate); h.powerW = rot(h.powerW)
        h.outages = [DishOutage(cause: 6, start: Date(timeIntervalSinceNow: -60), duration: 12)]
        return h
    }

    func obstructionMap() async throws -> ObstructionMap {
        let n = 123
        var snr = [Float](repeating: -1, count: n * n)
        let c = Double(n - 1) / 2
        for r in 0..<n {
            for col in 0..<n {
                let dx = Double(col) - c, dy = c - Double(r)
                let rad = (dx * dx + dy * dy).squareRoot()
                guard rad <= c else { continue }
                let az = (atan2(dx, dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                let theta = rad / c * 80 // degrees from zenith
                var v: Float = 0.92 - Float(theta / 400)
                // A tree to the north-east and a roofline to the south-west.
                if (20...75).contains(az), theta > 52 { v = 0 }
                if (200...250).contains(az), theta > 64 { v = 0 }
                if (20...75).contains(az), theta > 44, theta <= 52 { v = 0.35 }
                snr[r * n + col] = v
            }
        }
        return ObstructionMap(rows: n, cols: n, snr: snr, maxThetaDeg: 80, minElevationDeg: 10)
    }

    /// A week of plausible minutes so the longer ranges and usage totals are not empty.
    static func seedHistory() -> StoredHistory {
        var h = StoredHistory()
        let now = Int(Date().timeIntervalSince1970 / 60)
        for m in stride(from: now - 7 * 24 * 60, to: now - 15, by: 1) {
            let hour = Double(m % 1440) / 60
            let evening = max(0, sin((hour - 14) / 24 * 2 * .pi * 1.0)) // busier late in the day
            let jitter = sin(Double(m) * 0.37)
            var b = Bucket(t: m)
            b.n = 60
            b.down = (95e6 + 80e6 * (1 - evening) + 20e6 * jitter) * 60
            b.up = (11e6 + 5e6 * (1 - evening) + 2e6 * jitter) * 60
            b.lat = (30 + 14 * evening + 3 * jitter) * 60; b.latN = 60
            b.drop = (m % 700 < 3 ? 0.9 : 0.004) * 60
            b.power = 38 * 60; b.powerN = 60
            h.buckets.append(b)
            let day = Store.dayFormat.string(from: b.date)
            var d = h.daily[day] ?? [0, 0]
            d[0] += b.down / 8 * 0.003; d[1] += b.up / 8 * 0.003 // browsing, not saturating
            h.daily[day] = d
        }
        h.outages = [
            DishOutage(cause: 6, start: Date(timeIntervalSinceNow: -3600 * 5), duration: 4),
            DishOutage(cause: 8, start: Date(timeIntervalSinceNow: -3600 * 26), duration: 31),
            DishOutage(cause: 1, start: Date(timeIntervalSinceNow: -3600 * 76), duration: 38),
        ]
        return h
    }
}
