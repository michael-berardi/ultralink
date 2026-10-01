import AppKit
import Foundation
import ServiceManagement
import UserNotifications

struct Sample: Identifiable, Equatable {
    var id: Date { t }
    let t: Date
    let down: Double
    let up: Double
    let latency: Double?
    let drop: Double
    let power: Double?
}

enum ChartRange: String, CaseIterable, Identifiable {
    case m15 = "15 min", h1 = "1 hour", h24 = "24 hours", d7 = "7 days"
    var id: String { rawValue }
    var seconds: TimeInterval { switch self { case .m15: 900; case .h1: 3600; case .h24: 86400; case .d7: 604_800 } }
}

enum MenuBarReadout: String, CaseIterable, Identifiable {
    case speeds = "Speeds", latency = "Latency", icon = "Icon only"
    var id: String { rawValue }
}

@MainActor
final class Monitor: ObservableObject {
    static let shared = Monitor()

    // Live
    @Published private(set) var status: DishStatus?
    @Published private(set) var state: LinkState = .connecting
    @Published private(set) var recent: [Sample] = []
    @Published private(set) var obstruction: ObstructionMap?
    @Published private(set) var obstructionError: String?
    @Published private(set) var lastError: String?
    // Stored
    @Published private(set) var stored = StoredHistory()
    @Published private(set) var demo = false

    private var source: DishSource = DishClient(host: "192.168.100.1")
    private var task: Task<Void, Never>?
    private var lastCounter: UInt64?
    private var failures = 0
    private var outageStarted: Date?
    private var dirty = false
    private var lastSave = Date.distantPast
    private var lastHistoryPoll = Date.distantPast
    private var panelOpen = false
    private var observers: [NSObjectProtocol] = []

    var defaults: UserDefaults { .standard }
    var host: String { (defaults.string(forKey: "dishAddress") ?? "").trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "192.168.100.1" }
    var notifies: Bool { defaults.object(forKey: "notifyOutages") as? Bool ?? true }
    var wantsSpeedsInMenuBar: Bool { (MenuBarReadout(rawValue: defaults.string(forKey: "menuBarReadout") ?? "") ?? .speeds) != .icon }

    /// "192.168.100.1" or "host:port" (a different port is only useful for testing against a mock dish).
    static func client(for address: String) -> DishClient {
        if let colon = address.lastIndex(of: ":"), let port = Int(address[address.index(after: colon)...]) {
            return DishClient(host: String(address[..<colon]), port: port)
        }
        return DishClient(host: address)
    }

    // MARK: Lifecycle

    func start() {
        let wantsDemo = CommandLine.arguments.contains("--demo") || defaults.bool(forKey: "demoMode")
        configure(demo: wantsDemo)
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        })
        // The popover is a borderless panel; its key state tells us when someone is looking.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated { if (n.object as? NSWindow)?.isMenuBarPanel == true { self?.setPanel(open: true) } }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated { if (n.object as? NSWindow)?.isMenuBarPanel == true { self?.setPanel(open: false) } }
        })
    }

    /// (Re)builds the data source from the current settings and restarts polling.
    func configure(demo wantsDemo: Bool) {
        task?.cancel()
        saveNow()
        demo = wantsDemo
        status = nil; recent = []; obstruction = nil; lastError = nil; obstructionError = nil
        state = .connecting; failures = 0; lastCounter = nil; outageStarted = nil; lastHistoryPoll = .distantPast
        if wantsDemo {
            source = DemoDish()
            stored = DemoDish.seedHistory()
        } else {
            source = Self.client(for: host)
            stored = Store.load()
        }
        task = Task { [weak self] in await self?.loop() }
    }

    func restart() { configure(demo: demo) }

    func setPanel(open: Bool) {
        guard panelOpen != open else { return }
        panelOpen = open
        if open { Task { await refreshNow() } }
    }

    private func loop() async {
        while !Task.isCancelled {
            await poll()
            let fast = panelOpen || wantsSpeedsInMenuBar
            let delay: Double = failures > 0 ? 5 : (fast ? 2 : 6)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
        }
    }

    func refreshNow() async {
        lastHistoryPoll = .distantPast
        await poll()
    }

    private func poll() async {
        do {
            let s = try await source.status()
            failures = 0; lastError = nil
            status = s
            applyState(from: s)
            let historyEvery: TimeInterval = panelOpen ? 10 : 60
            if Date().timeIntervalSince(lastHistoryPoll) >= historyEvery {
                lastHistoryPoll = Date()
                let h = try await source.history()
                ingest(h, now: Date())
            }
            saveIfDue()
        } catch {
            failures += 1
            lastError = error.localizedDescription
            NSLog("UltraLink: poll failed (\(failures)): \(error.localizedDescription)")
            if failures >= 2 { setState(.offline(error.localizedDescription)) }
        }
    }

    func loadObstructionMap() async {
        do { obstruction = try await source.obstructionMap(); obstructionError = nil }
        catch { obstructionError = error.localizedDescription }
    }

    // MARK: State

    private func applyState(from s: DishStatus) {
        if let cause = s.outageCause, cause != 0 {
            setState(.outage(DishNames.outageCause[cause] ?? "Not connected"))
        } else if s.disablement != 1, s.disablement != 0 {
            setState(.outage(s.disablementText ?? "Service disabled"))
        } else if let a = s.alerts.first(where: \.critical) {
            setState(.degraded(a.title))
        } else if s.dropRate >= 0.05 {
            setState(.degraded("Losing \(Fmt.percent(s.dropRate)) of packets"))
        } else if s.fractionObstructed >= 0.05 {
            setState(.degraded("\(Fmt.percent(s.fractionObstructed)) of the sky is obstructed"))
        } else if s.snrPersistentlyLow {
            setState(.degraded("Signal is persistently low"))
        } else {
            setState(.online)
        }
    }

    private func setState(_ new: LinkState) {
        let old = state
        guard old != new else { return }
        state = new
        if new.isProblem, !old.isProblem, old != .connecting {
            outageStarted = Date()
            notify(title: "Starlink \(new == .offline("") ? "unreachable" : "outage")", body: new.detail ?? new.title)
        } else if !new.isProblem, old.isProblem, let t0 = outageStarted {
            outageStarted = nil
            notify(title: "Starlink is back", body: "Down for \(Fmt.duration(Date().timeIntervalSince(t0))).")
        } else if new.isProblem, old == .connecting {
            outageStarted = Date()
        }
    }

    private func notify(title: String, body: String) {
        guard notifies, !demo, Bundle.main.bundleIdentifier != nil else { return }
        let c = UNUserNotificationCenter.current()
        c.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title; content.body = body; content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
                if let error { NSLog("UltraLink: notification failed: \(error.localizedDescription)") }
            }
        }
    }

    func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { NSLog("UltraLink: notification permission error: \(error.localizedDescription)") }
            else if !granted { NSLog("UltraLink: notification permission was not granted") }
        }
    }

    // MARK: History

    private func ingest(_ h: DishHistory, now: Date) {
        let size = h.downBps.count
        guard size > 0, h.current > 0 else { return }
        let avail = min(Int(clamping: h.current), size)

        func timeOf(_ a: UInt64) -> Date { now.addingTimeInterval(-Double(h.current - 1 - a)) }

        // Samples for the chart: everything the ring holds.
        func value(_ arr: [Float], _ idx: Int) -> Double? {
            guard idx < arr.count else { return nil }
            let v = Double(arr[idx]); return v.isFinite ? v : nil
        }
        var all: [Sample] = []
        all.reserveCapacity(avail)
        for a in (h.current - UInt64(avail))..<h.current {
            let i = Int(a % UInt64(size))
            let lat = value(h.latencyMs, i)
            all.append(Sample(t: timeOf(a), down: value(h.downBps, i) ?? 0, up: value(h.upBps, i) ?? 0,
                              latency: (lat ?? 0) > 0 ? lat : nil, drop: value(h.dropRate, i) ?? 0, power: value(h.powerW, i)))
        }
        recent = all

        // New samples to count: by counter inside a session, by time after a relaunch.
        var fresh: ArraySlice<Sample>
        if let last = lastCounter, h.current >= last {
            fresh = all.suffix(min(Int(h.current - last), all.count))
        } else {
            let cutoff = stored.lastSample
            fresh = all.drop { $0.t.timeIntervalSince1970 <= cutoff + 0.5 }
        }
        lastCounter = h.current

        if !fresh.isEmpty {
            var index = Dictionary(uniqueKeysWithValues: stored.buckets.suffix(120).enumerated().map { ($0.element.t, stored.buckets.count - min(120, stored.buckets.count) + $0.offset) })
            var down = 0.0, up = 0.0
            for s in fresh {
                let minute = Int(s.t.timeIntervalSince1970 / 60)
                let at: Int
                if let k = index[minute] { at = k } else {
                    stored.buckets.append(Bucket(t: minute)); at = stored.buckets.count - 1; index[minute] = at
                }
                stored.buckets[at].n += 1
                stored.buckets[at].down += s.down
                stored.buckets[at].up += s.up
                stored.buckets[at].drop += s.drop
                if let l = s.latency { stored.buckets[at].lat += l; stored.buckets[at].latN += 1 }
                if let p = s.power { stored.buckets[at].power += p; stored.buckets[at].powerN += 1 }
                down += s.down; up += s.up
            }
            stored.buckets.sort { $0.t < $1.t }
            let cutoff = Int(now.timeIntervalSince1970 / 60) - 7 * 24 * 60
            if let first = stored.buckets.firstIndex(where: { $0.t >= cutoff }), first > 0 { stored.buckets.removeFirst(first) }
            // One sample is one second, so bits per second summed is bits; /8 is bytes.
            let day = Store.dayFormat.string(from: fresh.last!.t)
            var d = stored.daily[day] ?? [0, 0]
            d[0] += down / 8; d[1] += up / 8
            stored.daily[day] = d
            if stored.daily.count > 400, let oldest = stored.daily.keys.min() { stored.daily[oldest] = nil }
            stored.lastSample = max(stored.lastSample, fresh.last!.t.timeIntervalSince1970)
            dirty = true
        }

        for o in h.outages where !stored.outages.contains(where: { abs($0.start.timeIntervalSince(o.start)) < 1 }) {
            stored.outages.append(o); dirty = true
        }
        if stored.outages.count > 200 { stored.outages.removeFirst(stored.outages.count - 200) }
    }

    private func saveIfDue() {
        if dirty, Date().timeIntervalSince(lastSave) > 60 { saveNow() }
    }

    func saveNow() {
        guard dirty, !demo else { return }
        Store.save(stored); dirty = false; lastSave = Date()
    }

    func eraseHistory() {
        Store.erase()
        stored = StoredHistory(); dirty = false
    }

    // MARK: Derived

    func series(_ range: ChartRange, maxPoints: Int = 200) -> [Sample] {
        if range == .m15 {
            let step = max(1, recent.count / maxPoints)
            return Self.reduce(recent, by: step)
        }
        let cutoff = Date().addingTimeInterval(-range.seconds)
        let rows = stored.buckets.filter { $0.date >= cutoff }.map {
            Sample(t: $0.date, down: $0.downMean, up: $0.upMean, latency: $0.latMean, drop: $0.dropMean, power: $0.powerMean)
        }
        return Self.reduce(rows, by: max(1, rows.count / maxPoints))
    }

    private static func reduce(_ s: [Sample], by step: Int) -> [Sample] {
        guard step > 1 else { return s }
        return stride(from: 0, to: s.count, by: step).map { i in
            let chunk = s[i..<min(i + step, s.count)]
            let lats = chunk.compactMap(\.latency), pw = chunk.compactMap(\.power)
            return Sample(t: chunk[chunk.startIndex + chunk.count / 2].t,
                          down: chunk.map(\.down).reduce(0, +) / Double(chunk.count),
                          up: chunk.map(\.up).reduce(0, +) / Double(chunk.count),
                          latency: lats.isEmpty ? nil : lats.reduce(0, +) / Double(lats.count),
                          drop: chunk.map(\.drop).reduce(0, +) / Double(chunk.count),
                          power: pw.isEmpty ? nil : pw.reduce(0, +) / Double(pw.count))
        }
    }

    func usage(forDay date: Date) -> (down: Double, up: Double) {
        let d = stored.daily[Store.dayFormat.string(from: date)] ?? [0, 0]
        return (d[0], d[1])
    }

    func usageThisMonth() -> (down: Double, up: Double) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        var down = 0.0, up = 0.0
        for (k, v) in stored.daily {
            guard let d = Store.dayFormat.date(from: k), cal.dateComponents([.year, .month], from: d) == comps else { continue }
            down += v[0]; up += v[1]
        }
        return (down, up)
    }

    var latestPower: Double? { recent.last(where: { $0.power != nil })?.power }
    var recentOutages: [DishOutage] { stored.outages.sorted { $0.start > $1.start } }

    // MARK: Menu bar text

    var menuBarText: String {
        guard let s = status, !state.isProblem else { return "" }
        switch MenuBarReadout(rawValue: defaults.string(forKey: "menuBarReadout") ?? "") ?? .speeds {
        case .speeds: return "↓\(Fmt.mbps(s.downBps)) ↑\(Fmt.mbps(s.upBps))"
        case .latency: return s.latencyMs > 0 ? "\(Int(s.latencyMs.rounded())) ms" : ""
        case .icon: return ""
        }
    }
}

extension NSWindow {
    /// SwiftUI's MenuBarExtra(.window) hosts its content in a private panel.
    var isMenuBarPanel: Bool { className.contains("MenuBarExtra") || (self is NSPanel && level == .popUpMenu) }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
        catch { NSLog("UltraLink: launch at login failed: \(error.localizedDescription)") }
    }
}
