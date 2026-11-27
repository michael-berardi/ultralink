import AppKit
import Sparkle
import SwiftUI

@main
struct UltraLinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var monitor = Monitor.shared

    init() {
        if CommandLine.arguments.contains("--probe") { Probe.run(); RunLoop.main.run() }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environmentObject(monitor)
        } label: {
            MenuLabel().environmentObject(monitor)
        }
        .menuBarExtraStyle(.window)

        Window("Sky View", id: "sky") {
            SkyView().environmentObject(monitor)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView().environmentObject(monitor)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updates.shared.checkForUpdates() }
            }
        }
    }
}

private struct MenuLabel: View {
    @EnvironmentObject var monitor: Monitor
    @StateObject private var updates = Updates.shared

    var body: some View {
        HStack(spacing: 4) {
            if updates.available != nil {
                Image(systemName: "arrow.down.circle.fill").accessibilityLabel("Update available")
            }
            Image(systemName: monitor.state.isProblem ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
            let t = monitor.menuBarText
            if !t.isEmpty { Text(t).font(.system(size: 12, weight: .medium).monospacedDigit()) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Monitor.shared.start()
        // Bounded local cleanup first: stale unreadable-history copies, stale update downloads and
        // stale temporary files. It only deletes, never writes, and demo mode leaves the disk alone.
        if !Monitor.shared.demo { Retention.sweep() }
        Updates.shared.start()
        if Monitor.shared.notifies { Monitor.shared.requestNotificationPermission() }
        QA.showRequestedWindows()
    }
}

/// Signed updates through Sparkle: a daily check against the GitHub release feed (SUFeedURL),
/// verified with the EdDSA key in Info.plist before anything is installed. A scheduled find is
/// gentle: a badge in the menu bar and a line in the popover instead of a dialog over the user's
/// work. Clicking it opens Sparkle's standard dialog (Install, Remind Me Later, Skip This Version).
/// SUSendProfileInfo=false in Info.plist keeps the anonymous GET free of machine/OS profile data.
final class Updates: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = Updates()
    /// The version of a scheduled find waiting for the user's attention.
    @Published private(set) var available: String?
    @Published private(set) var canCheck = false
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []

    /// The user-facing environment opt-out, also honored by `UpdateRules` for scheduled checks.
    static var optedOut: Bool { ProcessInfo.processInfo.environment["ULTRALINK_NO_UPDATE_CHECK"] == "1" }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    func start() {
        guard controller == nil else { return }
        let c = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        // Sparkle's default user agent carries the app version; the check stays anonymous.
        c.updater.userAgentString = "ultralink-update-check"
        c.startUpdater()
        controller = c
        // Keep Settings in step when Sparkle's dialog changes a choice or a check starts or ends.
        observations = [
            c.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                DispatchQueue.main.async { self?.canCheck = updater.canCheckForUpdates }
            },
            c.updater.observe(\.automaticallyDownloadsUpdates) { [weak self] _, _ in
                DispatchQueue.main.async { self?.objectWillChange.send() }
            }
        ]
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    /// The same check Sparkle's daily timer runs, for testing the reminder against a local feed.
    func checkInBackground() { controller?.updater.checkForUpdatesInBackground() }

    /// Sparkle reports `false` before the updater starts (for example in a snapshot or headless
    /// run), so Settings reads the saved preference or the Info.plist default instead. An explicit
    /// opt-out always shows the controls off.
    private func displayedUpdateState(key: String, plistDefault: Bool) -> Bool {
        guard !Self.optedOut else { return false }
        if let saved = UserDefaults.standard.object(forKey: key) as? NSNumber { return saved.boolValue }
        if let bundled = Bundle.main.object(forInfoDictionaryKey: key) as? NSNumber { return bundled.boolValue }
        return plistDefault
    }

    var automatic: Bool {
        get { displayedUpdateState(key: "SUEnableAutomaticChecks", plistDefault: true) }
        set {
            guard !Self.optedOut else { return }
            controller?.updater.automaticallyChecksForUpdates = newValue
            if !newValue { automaticInstall = false }
            objectWillChange.send()
        }
    }

    /// Off by default (SUAutomaticallyUpdate in Info.plist); Sparkle stores the user's choice.
    var automaticInstall: Bool {
        get { displayedUpdateState(key: "SUAutomaticallyUpdate", plistDefault: false) }
        set {
            guard !Self.optedOut else { return }
            controller?.updater.automaticallyDownloadsUpdates = newValue
            objectWillChange.send()
        }
    }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        let env = ProcessInfo.processInfo.environment
        if updateCheck == .updatesInBackground,
           !UpdateRules.backgroundChecksAllowed(environment: env, arguments: CommandLine.arguments) {
            throw NSError(domain: "UltraLink", code: 1, userInfo: [NSLocalizedDescriptionKey: "Automatic update checks are off for this launch."])
        }
    }

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let version = update.displayVersionString
        available = !handleShowingUpdate && UpdateRules.isNewer(version, than: Self.currentVersion) ? version : nil
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { available = nil }

    func standardUserDriverWillFinishUpdateSession() { available = nil }
}

/// `UltraLink --probe [host]` reads the dish once and prints what it found, with no UI.
enum Probe {
    static func run() {
        let args = CommandLine.arguments
        let host = args.drop { $0 != "--probe" }.dropFirst().first.flatMap { $0.hasPrefix("--") ? nil : $0 } ?? "192.168.100.1"
        let port = args.drop { $0 != "--port" }.dropFirst().first.flatMap(Int.init) ?? 9201
        Task {
            let client = DishClient(host: host, port: port)
            do {
                let s = try await client.status()
                print("status: down \(Fmt.rateText(s.downBps)) up \(Fmt.rateText(s.upBps)) ping \(String(format: "%.1f", s.latencyMs)) ms loss \(s.dropRate)")
                print("        obstructed \(Fmt.percent(s.fractionObstructed)) uptime \(Fmt.duration(s.uptime)) gps \(s.gpsSats) eth \(s.ethernetMbps)")
                print("        hw \(s.hardware) sw \(s.software) id \(s.dishID) alerts \(s.alerts.map(\.key)) outage \(s.outageCause.map(String.init) ?? "none")")
                let h = try await client.history()
                let idx = h.recentIndices(900)
                let avgDown = idx.isEmpty ? 0 : idx.map { Double(h.downBps[$0]) }.reduce(0, +) / Double(idx.count)
                print("history: counter \(h.current) samples \(h.downBps.count) mean down \(Fmt.rateText(avgDown)) outages \(h.outages.map { "\($0.causeText) \(Fmt.duration($0.duration)) at \($0.start)" })")
                let m = try await client.obstructionMap()
                let blocked = m.snr.filter { $0 >= 0 && $0 < 0.15 }.count, seen = m.snr.filter { $0 >= 0 }.count
                print("sky:     \(m.rows)x\(m.cols) cells, \(seen) seen, \(blocked) blocked")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("probe failed: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
    }
}

/// `--show-popover`, `--show-sky` and `--show-settings` open the real views in ordinary windows, so
/// they can be screenshotted without clicking the menu bar. `--snapshot <dir>` writes each to a PNG and quits.
enum QA {
    static var windows: [NSWindow] = []

    @MainActor static func showRequestedWindows() {
        let args = CommandLine.arguments
        func host<V: View>(_ view: V, title: String, at x: CGFloat) {
            let root = view.environmentObject(Monitor.shared).background(Color(nsColor: .windowBackgroundColor))
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = title
            w.styleMask = [.titled, .closable]
            w.setFrameTopLeftPoint(NSPoint(x: x, y: (NSScreen.main?.frame.height ?? 900) - 60))
            w.makeKeyAndOrderFront(nil)
            windows.append(w)
        }
        if args.contains("--show-popover") { host(PopoverView(), title: "UltraLink", at: 60) }
        if args.contains("--show-sky") { host(SkyView(), title: "Sky View", at: 480) }
        if args.contains("--show-settings") { host(SettingsView(), title: "Settings", at: 1000) }
        if !windows.isEmpty { NSApp.activate(ignoringOtherApps: true) }
        if args.contains("--scheduled-check") { Updates.shared.checkInBackground() }
        if let i = args.firstIndex(of: "--snapshot"), let dir = args[safe: i + 1] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                for w in windows {
                    let name = w.title.lowercased().replacingOccurrences(of: " ", with: "-")
                    capture(w, path: "\(dir)/\(name).png")
                }
                exit(0)
            }
        }
    }

    /// Screen Recording permission is not required to render our own window's view.
    private static func capture(_ window: NSWindow, path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", path]
        try? p.run(); p.waitUntilExit()
        if p.terminationStatus == 0 && FileManager.default.fileExists(atPath: path) { return }
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
