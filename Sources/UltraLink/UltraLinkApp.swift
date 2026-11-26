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

    var body: some View {
        HStack(spacing: 4) {
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
        Updates.shared.start()
        if Monitor.shared.notifies { Monitor.shared.requestNotificationPermission() }
        QA.showRequestedWindows()
    }
}

/// Signed updates through Sparkle. The Info.plist default is one anonymous daily check of the
/// signed GitHub feed; a user's earlier Settings choice is preserved because nothing is written at
/// launch. Downloads are verified with the EdDSA key before installation. Automatic installation is
/// a separate, off-by-default opt-in.
final class Updates: ObservableObject {
    static let shared = Updates()
    private var controller: SPUStandardUpdaterController?

    /// The user-facing opt-out; only this forces the Settings controls off.
    static var optedOut: Bool { ProcessInfo.processInfo.environment["ULTRALINK_NO_UPDATE_CHECK"] == "1" }

    /// No feed request at all for an explicit opt-out, CI, or headless/probe/snapshot runs.
    static var checksSuppressed: Bool {
        let env = ProcessInfo.processInfo.environment
        if optedOut || env["CI"] != nil { return true }
        let args = CommandLine.arguments
        return args.contains("--probe") || args.contains("--snapshot")
    }

    var disabled: Bool { Self.optedOut }

    func start() {
        // startingUpdater: false keeps the feed request off this call; startUpdater() schedules the
        // daily background check only when checks are allowed. Sparkle reads the Info.plist default
        // (true) unless the user has explicitly saved a different choice in its own defaults.
        let c = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        controller = c
        // Fixed, non-identifying User-Agent. SUSendProfileInfo=false in Info.plist suppresses
        // machine/OS profile parameters, so the GET carries no client id, version or usage data.
        c.updater.httpHeaders = ["User-Agent": "ultralink-update-check"]
        guard !Self.checksSuppressed else { return }
        c.startUpdater()
    }

    func checkForUpdates() {
        guard !Self.checksSuppressed else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    var automatic: Bool {
        get { !Self.optedOut && (controller?.updater.automaticallyChecksForUpdates ?? true) }
        set {
            guard !Self.optedOut else { return }
            controller?.updater.automaticallyChecksForUpdates = newValue
            if !newValue { autoInstall = false }
            objectWillChange.send()
        }
    }

    var autoInstall: Bool {
        get { !Self.optedOut && (controller?.updater.automaticallyDownloadsUpdates ?? false) }
        set {
            guard !Self.optedOut else { return }
            controller?.updater.automaticallyDownloadsUpdates = newValue
            objectWillChange.send()
        }
    }
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
        if !windows.isEmpty && !args.contains("--snapshot") { NSApp.activate(ignoringOtherApps: true) }
        if let i = args.firstIndex(of: "--snapshot"), let dir = args[safe: i + 1] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                for w in windows {
                    let name = w.title.lowercased().replacingOccurrences(of: " ", with: "-")
                    if let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                        v.cacheDisplay(in: v.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
                    }
                }
                exit(0)
            }
        }
    }
}
