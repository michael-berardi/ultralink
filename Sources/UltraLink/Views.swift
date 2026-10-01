import Charts
import SwiftUI

// MARK: - Popover

struct PopoverView: View {
    @EnvironmentObject var monitor: Monitor
    @StateObject private var speed = SpeedTest()
    @AppStorage("chartRange") private var rangeRaw = ChartRange.m15.rawValue
    @State private var hover: Sample?
    @State private var showOutages = false

    private var range: ChartRange { ChartRange(rawValue: rangeRaw) ?? .m15 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header()
            if let s = monitor.status, !isUnreachable {
                let series = monitor.series(range)
                Readout(status: s, hover: hover)
                Picker("Range", selection: $rangeRaw) {
                    ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden()
                ThroughputChart(samples: series, range: range, hover: $hover).frame(height: 96)
                LatencyChart(samples: series, range: range, hover: $hover).frame(height: 56)
                StatGrid(status: s)
                if !s.alerts.isEmpty { AlertList(alerts: s.alerts) }
                if !monitor.recentOutages.isEmpty { OutageList(expanded: $showOutages) }
            } else {
                Unreachable()
            }
            Divider()
            SpeedRow(speed: speed)
            Footer()
        }
        .padding(16)
        .frame(width: 372)
    }

    private var isUnreachable: Bool { if case .offline = monitor.state { return true }; return false }
}

private struct Header: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(monitor.state.color).frame(width: 10, height: 10)
                .shadow(color: monitor.state.color.opacity(0.6), radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(monitor.state.title).font(.headline)
                    if monitor.demo {
                        Text("DEMO").font(.system(size: 9, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
        }
    }

    private var subtitle: String {
        if case .offline = monitor.state { return "Not reachable from this Mac" }
        if let d = monitor.state.detail { return d }
        if let s = monitor.status { return "Starlink \(s.hardwareName) · \(shortSoftware(s.software))" }
        return "Looking for your dish…"
    }
    private func shortSoftware(_ s: String) -> String { s.split(separator: ".").prefix(3).joined(separator: ".") }
}

private struct Readout: View {
    let status: DishStatus
    let hover: Sample?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Big(title: "Download", symbol: "arrow.down", color: .blue, bps: hover?.down ?? status.downBps)
            Big(title: "Upload", symbol: "arrow.up", color: .teal, bps: hover?.up ?? status.upBps)
        }
        .overlay(alignment: .topTrailing) {
            if let hover { Text(Fmt.time(hover.t)).font(.caption2).foregroundStyle(.secondary).monospacedDigit() }
        }
    }
}

private struct Big: View {
    let title: String, symbol: String, color: Color, bps: Double
    var body: some View {
        let r = Fmt.rate(bps)
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(r.value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(r.unit).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Charts

private func xAxis(_ range: ChartRange) -> some AxisContent {
    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
        AxisGridLine().foregroundStyle(.quaternary)
        AxisValueLabel(format: range == .d7 ? .dateTime.weekday(.abbreviated) : .dateTime.hour().minute(), anchor: .top)
            .font(.system(size: 9)).foregroundStyle(.tertiary)
    }
}

struct ThroughputChart: View {
    let samples: [Sample]
    let range: ChartRange
    @Binding var hover: Sample?

    var body: some View {
        Chart {
            ForEach(samples) { s in
                AreaMark(x: .value("Time", s.t), y: .value("Download", s.down / 1e6), series: .value("S", "d"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.45), .blue.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", s.t), y: .value("Download", s.down / 1e6), series: .value("S", "d"))
                    .interpolationMethod(.monotone).foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 1.4))
                LineMark(x: .value("Time", s.t), y: .value("Upload", s.up / 1e6), series: .value("S", "u"))
                    .interpolationMethod(.monotone).foregroundStyle(.teal).lineStyle(StrokeStyle(lineWidth: 1.4))
            }
            if let h = hover { RuleMark(x: .value("Time", h.t)).foregroundStyle(.secondary.opacity(0.5)) }
        }
        .chartXScale(domain: Date().addingTimeInterval(-range.seconds)...Date())
        .chartYScale(domain: 0...yMax)
        .chartXAxis { xAxis(range) }
        .chartPlotStyle { $0.clipped() }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))").font(.system(size: 9)).foregroundStyle(.tertiary) } }
            }
        }
        .chartOverlay { proxy in HoverCatcher(proxy: proxy, samples: samples, hover: $hover) }
    }

    private var yMax: Double { max(10, (samples.map(\.down).max() ?? 0) / 1e6 * 1.15) }
}

struct LatencyChart: View {
    let samples: [Sample]
    let range: ChartRange
    @Binding var hover: Sample?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Latency").font(.caption2.weight(.medium)).foregroundStyle(.orange)
                Spacer()
                Text(label).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            Chart {
                ForEach(samples) { s in
                    if let l = s.latency {
                        LineMark(x: .value("Time", s.t), y: .value("ms", l), series: .value("S", "l"))
                            .interpolationMethod(.monotone).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1.3))
                    }
                    if s.drop >= 0.2 {
                        PointMark(x: .value("Time", s.t), y: .value("ms", yMax * 0.04)).foregroundStyle(.red).symbolSize(14)
                    }
                }
                if let h = hover { RuleMark(x: .value("Time", h.t)).foregroundStyle(.secondary.opacity(0.5)) }
            }
            .chartXScale(domain: Date().addingTimeInterval(-range.seconds)...Date())
            .chartYScale(domain: 0...yMax)
            .chartXAxis(.hidden)
            .chartPlotStyle { $0.clipped() }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { v in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))").font(.system(size: 9)).foregroundStyle(.tertiary) } }
                }
            }
            .chartOverlay { proxy in HoverCatcher(proxy: proxy, samples: samples, hover: $hover) }
        }
    }

    /// Scaled to the 95th percentile so a single spike does not flatten the line.
    private var yMax: Double {
        let v = samples.compactMap(\.latency).sorted()
        return max(60, (v.isEmpty ? 0 : v[Int(Double(v.count - 1) * 0.95)]) * 1.3)
    }
    private var label: String {
        let l = hover?.latency ?? samples.last?.latency
        let loss = hover?.drop ?? samples.last?.drop ?? 0
        return [l.map { "\(Int($0.rounded())) ms" }, loss >= 0.005 ? "\(Fmt.percent(loss)) loss" : nil].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct HoverCatcher: View {
    let proxy: ChartProxy
    let samples: [Sample]
    @Binding var hover: Sample?

    var body: some View {
        GeometryReader { geo in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p):
                        let x = p.x - geo[proxy.plotAreaFrame].origin.x
                        guard let t: Date = proxy.value(atX: x) else { return }
                        hover = samples.min { abs($0.t.timeIntervalSince(t)) < abs($1.t.timeIntervalSince(t)) }
                    case .ended: hover = nil
                    }
                }
        }
    }
}

// MARK: - Stats

private struct StatGrid: View {
    @EnvironmentObject var monitor: Monitor
    let status: DishStatus

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Tile("Ping", status.latencyMs > 0 ? "\(Int(status.latencyMs.rounded())) ms" : "–", "timer")
                Tile("Packet loss", Fmt.percent(status.dropRate), "waveform.path.ecg")
                Tile("Obstructed", Fmt.percent(status.fractionObstructed), "tree")
            }
            GridRow {
                Tile("Power", monitor.latestPower.map { String(format: "%.0f W", $0) } ?? "–", "bolt")
                Tile("Uptime", Fmt.duration(status.uptime), "clock")
                Tile("GPS", status.gpsValid ? "\(status.gpsSats) sats" : "No fix", "location")
            }
            GridRow { UsageTile().gridCellColumns(3) }
        }
    }
}

private struct Tile: View {
    let title: String, value: String, symbol: String
    init(_ title: String, _ value: String, _ symbol: String) { self.title = title; self.value = value; self.symbol = symbol }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(size: 15, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.quaternary.opacity(0.5)))
    }
}

private struct UsageTile: View {
    @EnvironmentObject var monitor: Monitor
    var body: some View {
        let today = monitor.usage(forDay: Date()), month = monitor.usageThisMonth()
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Data today", systemImage: "chart.bar").font(.caption2).foregroundStyle(.secondary)
                Text("↓ \(Fmt.bytes(today.down))   ↑ \(Fmt.bytes(today.up))")
                    .font(.system(size: 13, weight: .medium, design: .rounded)).monospacedDigit()
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("This month").font(.caption2).foregroundStyle(.secondary)
                Text(Fmt.bytes(month.down + month.up)).font(.system(size: 13, weight: .medium, design: .rounded)).monospacedDigit()
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.quaternary.opacity(0.5)))
        .help("Counted while UltraLink is running")
    }
}

private struct AlertList: View {
    let alerts: [DishAlert]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(alerts) { a in
                Label(a.title, systemImage: a.critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(a.critical ? .red : .orange)
            }
        }
    }
}

private struct OutageList: View {
    @EnvironmentObject var monitor: Monitor
    @Binding var expanded: Bool
    var body: some View {
        let list = monitor.recentOutages
        let day = list.filter { $0.start > Date().addingTimeInterval(-86400) }.count
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Outages").font(.caption.weight(.medium))
                    Text("\(day) in 24 h").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let last = list.first { Text("Last \(Fmt.time(last.start))").font(.caption).foregroundStyle(.secondary) }
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded {
                ForEach(list.prefix(6)) { o in
                    HStack {
                        Text(o.causeText).font(.caption)
                        Spacer()
                        Text("\(Fmt.duration(o.duration)) · \(Fmt.time(o.start))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }
}

private struct Unreachable: View {
    @EnvironmentObject var monitor: Monitor
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.system(size: 30)).foregroundStyle(.secondary)
            Text(monitor.lastError ?? "Looking for your dish…").font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Settings…") { openSettings() }
                Button("Try the demo") { UserDefaults.standard.set(true, forKey: "demoMode"); monitor.configure(demo: true) }
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
    }
}

// MARK: - Speed test + footer

private struct SpeedRow: View {
    @ObservedObject var speed: SpeedTest
    var body: some View {
        HStack(spacing: 8) {
            switch speed.phase {
            case .idle:
                Label("Speed test", systemImage: "speedometer").font(.callout)
                Spacer()
                Button("Start") { speed.run() }.controlSize(.small)
            case .running:
                ProgressView().controlSize(.small)
                Text("Measuring…").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { speed.cancel() }.controlSize(.small)
            case .done(let r):
                VStack(alignment: .leading, spacing: 2) {
                    Text("↓ \(Fmt.rateText(r.down))   ↑ \(Fmt.rateText(r.up))").font(.callout.weight(.medium)).monospacedDigit()
                    Text(([r.rtt.map { "Idle ping \(Int($0.rounded())) ms" }, r.responsiveness.map { "\(Int($0.rounded())) RPM" }]
                        .compactMap { $0 } + [Fmt.time(r.date)]).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Again") { speed.run() }.controlSize(.small)
            case .failed(let m):
                Text(m).font(.caption).foregroundStyle(.red).lineLimit(2)
                Spacer()
                Button("Retry") { speed.run() }.controlSize(.small)
            }
        }
    }
}

private struct Footer: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        HStack(spacing: 14) {
            Button { NSApp.activate(ignoringOtherApps: true); openWindow(id: "sky") } label: { Label("Sky View", systemImage: "scope") }
            Spacer()
            Button { openSettings() } label: { Image(systemName: "gearshape") }.help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Quit UltraLink")
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

func openSettings() {
    NSApp.activate(ignoringOtherApps: true)
    if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}

extension LinkState {
    var color: Color {
        switch self {
        case .online: return .green
        case .degraded: return .orange
        case .outage, .offline: return .red
        case .connecting: return .gray
        }
    }
}
