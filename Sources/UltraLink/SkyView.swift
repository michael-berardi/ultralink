import SwiftUI

/// The dish's obstruction map as a sky chart: zenith at the centre, the horizon at the edge, north up.
struct SkyView: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(spacing: 8) {
                if let map = monitor.obstruction {
                    SkyCanvas(map: map, status: monitor.status).frame(width: 380, height: 380)
                } else {
                    ZStack {
                        Circle().fill(.quaternary.opacity(0.4))
                        if let e = monitor.obstructionError {
                            Text(e).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(40)
                        } else { ProgressView() }
                    }.frame(width: 380, height: 380)
                }
                HStack(spacing: 14) {
                    Legend(color: .green, text: "Clear")
                    Legend(color: .yellow, text: "Partly blocked")
                    Legend(color: .red, text: "Blocked")
                    Legend(color: .secondary.opacity(0.35), text: "No data")
                }.font(.caption)
            }
            VStack(alignment: .leading, spacing: 14) {
                if let s = monitor.status {
                    Info("Obstructed", Fmt.percent(s.fractionObstructed), "How much of the sky the dish has seen blocked.")
                    Info("Pointing", String(format: "%.0f° %@, %.0f° up", (s.azimuth + 360).truncatingRemainder(dividingBy: 360), Fmt.compass(s.azimuth), s.elevation), "Where the dish faces now.")
                    if let t = s.tilt { Info("Tilt", String(format: "%.1f° from level", t), "A well-mounted dish is close to level.") }
                    Info("GPS", s.gpsValid ? "\(s.gpsSats) satellites" : "No fix", nil)
                    Info("Ethernet", "\(s.ethernetMbps) Mbps", s.ethernetMbps > 0 && s.ethernetMbps < 1000 ? "Below 1 Gbps: check the cable." : nil)
                    Info("Software", s.software.isEmpty ? "–" : s.software, DishNames.updateState[s.updateState])
                    Info("Dish ID", s.dishID.isEmpty ? "–" : s.dishID, nil)
                }
                Spacer()
                Button("Refresh") { Task { await monitor.loadObstructionMap() } }
            }
            .frame(width: 210)
        }
        .padding(24)
        .task { await monitor.loadObstructionMap() }
    }
}

private struct Legend: View {
    let color: Color, text: String
    var body: some View { HStack(spacing: 5) { Circle().fill(color).frame(width: 8, height: 8); Text(text).foregroundStyle(.secondary) } }
}

private struct Info: View {
    let title: String, value: String, note: String?
    init(_ t: String, _ v: String, _ n: String?) { title = t; value = v; note = n }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .rounded).weight(.medium)).textSelection(.enabled).lineLimit(2).minimumScaleFactor(0.8)
            if let note { Text(note).font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

private struct SkyCanvas: View {
    let map: ObstructionMap
    let status: DishStatus?

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 18
            let disc = Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
            ctx.fill(disc, with: .color(.black.opacity(0.18)))

            // Every cell of the grid, painted as a small square that stays inside the disc.
            let cell = radius * 2 / CGFloat(map.cols)
            ctx.clip(to: disc)
            for r in 0..<map.rows {
                for col in 0..<map.cols {
                    let v = map.snr[r * map.cols + col]
                    guard v >= 0 else { continue }
                    let rect = CGRect(x: c.x - radius + CGFloat(col) * cell, y: c.y - radius + CGFloat(r) * cell, width: cell + 0.5, height: cell + 0.5)
                    ctx.fill(Path(rect), with: .color(color(for: v)))
                }
            }
        }
        .overlay { Rings(map: map, status: status) }
    }

    private func color(for v: Float) -> Color {
        if v < 0.15 { return .red.opacity(0.85) }
        if v < 0.55 { return .yellow.opacity(0.8) }
        return Color.green.opacity(0.35 + 0.4 * Double(v))
    }
}

private struct Rings: View {
    let map: ObstructionMap
    let status: DishStatus?
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 18
            let line = GraphicsContext.Shading.color(.secondary.opacity(0.45))
            // Rings every third of the way from zenith to the edge; the edge is the lowest the dish looks.
            for theta in [map.maxThetaDeg, map.maxThetaDeg * 2 / 3, map.maxThetaDeg / 3] {
                let rr = radius * theta / map.maxThetaDeg
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)), with: line, lineWidth: 0.6)
            }
            var cross = Path()
            cross.move(to: CGPoint(x: c.x - radius, y: c.y)); cross.addLine(to: CGPoint(x: c.x + radius, y: c.y))
            cross.move(to: CGPoint(x: c.x, y: c.y - radius)); cross.addLine(to: CGPoint(x: c.x, y: c.y + radius))
            ctx.stroke(cross, with: line, lineWidth: 0.4)
            for (t, p) in [("N", CGPoint(x: c.x, y: c.y - radius - 9)), ("S", CGPoint(x: c.x, y: c.y + radius + 9)),
                           ("E", CGPoint(x: c.x + radius + 9, y: c.y)), ("W", CGPoint(x: c.x - radius - 9, y: c.y))] {
                ctx.draw(Text(t).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary), at: p)
            }
            if let s = status {
                let theta = max(0, 90 - s.elevation)
                let rr = radius * theta / map.maxThetaDeg
                let a = s.azimuth * .pi / 180
                let p = CGPoint(x: c.x + rr * sin(a), y: c.y - rr * cos(a))
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)), with: .color(.white), lineWidth: 2)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(.white))
            }
        }
    }
}
