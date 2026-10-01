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

/// Signed updates through Sparkle: a daily check against the GitHub release feed (SUFeedURL),
/// verified with the EdDSA key in Info.plist before anything is installed.
final class Updates: ObservableObject {
    static let shared = Updates()
    private var controller: SPUStandardUpdaterController?

    func start() { controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    var automatic: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? true }
        set { controller?.updater.automaticallyChecksForUpdates = newValue; objectWillChange.send() }
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
        if !windows.isEmpty { NSApp.activate(ignoringOtherApps: true) }
        if let i = args.firstIndex(of: "--snapshot"), let dir = args[safe: i + 1] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                for w in windows {
                    let name = w.title.lowercased().replacingOccurrences(of: " ", with: "-")
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    p.arguments = ["-x", "-o", "-l", "\(w.windowNumber)", "\(dir)/\(name).png"]
                    try? p.run(); p.waitUntilExit()
                }
                exit(0)
            }
        }
    }
}
