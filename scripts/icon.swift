// Renders the app icon (1024 px PNG) with CoreGraphics. Usage: swift scripts/icon.swift out.png
import AppKit

let size = 1024.0
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let cs = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }

// macOS icon grid: 824 px body, continuous corners, soft drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185).cgPath
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.35))
ctx.addPath(shape); ctx.setFillColor(rgb(0.02, 0.03, 0.08)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape); ctx.clip()

// Deep space with a cool glow rising from the lower middle.
let sky = CGGradient(colorsSpace: cs, colors: [rgb(0.015, 0.02, 0.06), rgb(0.03, 0.06, 0.16), rgb(0.06, 0.18, 0.40)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
let glow = CGGradient(colorsSpace: cs, colors: [rgb(0.30, 0.62, 1.0, 0.55), rgb(0.20, 0.45, 0.95, 0.18), rgb(0.1, 0.2, 0.6, 0)] as CFArray, locations: [0, 0.5, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 250), startRadius: 0, endCenter: CGPoint(x: 512, y: 250), endRadius: 560, options: [])

// Stars.
var seed: UInt64 = 11
for _ in 0..<26 {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    let x = 130 + Double(seed >> 40 & 0xFFFF) / 65535 * 764
    let y = 420 + Double(seed >> 20 & 0xFFFF) / 65535 * 480
    let r = 3 + Double(seed >> 8 & 0xFF) / 255 * 5
    ctx.setFillColor(rgb(0.85, 0.92, 1, 0.25 + Double(seed & 0xFF) / 255 * 0.5))
    ctx.fillEllipse(in: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r))
}

// Orbit: a tilted ellipse passing behind the signal.
ctx.saveGState()
ctx.translateBy(x: 512, y: 560); ctx.rotate(by: 0.42)
ctx.setStrokeColor(rgb(0.7, 0.85, 1, 0.38)); ctx.setLineWidth(5)
ctx.strokeEllipse(in: CGRect(x: -380, y: -118, width: 760, height: 236))
ctx.restoreGState()

// Satellite: a glowing point on the orbit, upper right.
let sat = CGPoint(x: 512 + 376 * cos(0.42) - 17.7 * sin(0.42), y: 560 + 376 * sin(0.42) + 17.7 * cos(0.42))
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 46, color: rgb(0.55, 0.8, 1, 1))
ctx.setFillColor(rgb(1, 1, 1)); ctx.fillEllipse(in: CGRect(x: sat.x - 17, y: sat.y - 17, width: 34, height: 34))
ctx.restoreGState()

// Signal: dish dot at the base and three arcs reaching up to the sky.
let base = CGPoint(x: 512, y: 300)
func arc(_ r: CGFloat, _ w: CGFloat, _ a: Double) {
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 34, color: rgb(0.4, 0.7, 1, 0.9))
    ctx.setStrokeColor(rgb(0.93, 0.97, 1, a)); ctx.setLineWidth(w); ctx.setLineCap(.round)
    ctx.addArc(center: base, radius: r, startAngle: .pi * 0.28, endAngle: .pi * 0.72, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()
}
// Aim the beam at the satellite.
ctx.saveGState()
ctx.translateBy(x: base.x, y: base.y); ctx.rotate(by: -atan2(sat.x - base.x, sat.y - base.y)); ctx.translateBy(x: -base.x, y: -base.y)
arc(120, 46, 1); arc(230, 46, 0.9); arc(340, 46, 0.78)
ctx.restoreGState()
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 40, color: rgb(0.4, 0.7, 1, 0.9))
ctx.setFillColor(rgb(1, 1, 1)); ctx.fillEllipse(in: CGRect(x: base.x - 40, y: base.y - 40, width: 80, height: 80))
ctx.restoreGState()

// Top edge highlight.
let hl = CGGradient(colorsSpace: cs, colors: [rgb(1, 1, 1, 0.16), rgb(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(hl, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 700), options: [])
ctx.restoreGState()

// Hairline rim.
ctx.addPath(shape); ctx.setStrokeColor(rgb(1, 1, 1, 0.14)); ctx.setLineWidth(2); ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
