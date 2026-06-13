#!/usr/bin/env swift
//
//  make-app-icon.swift
//  Draws the "pkpass Quick Look" app icon (a tilted Wallet pass card inspected
//  by a Quick Look magnifier) and writes a full AppIcon.appiconset.
//
//  Usage: swift scripts/make-app-icon.swift
//

import AppKit
import Foundation

let outDir = FileManager.default.currentDirectoryPath + "/Sources/App/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func color(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

/// Draws the icon into a `size`×`size` bitmap (design space is 1024).
func drawIcon(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let s = CGFloat(size) / 1024.0
    func S(_ v: CGFloat) -> CGFloat { v * s }
    func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: (1024 - y) * s) } // flip y to top-origin

    // ---- Background squircle with blue gradient ----
    let bgRect = NSRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: S(230), yRadius: S(230))
    bgPath.addClip()
    NSGradient(colors: [color(46, 143, 230), color(23, 111, 203), color(14, 79, 158)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: bgRect, angle: -90)

    // top sheen
    if let sheen = NSGradient(colors: [color(255, 255, 255, 0.20), color(255, 255, 255, 0)]) {
        sheen.draw(in: NSRect(x: 0, y: CGFloat(size) * 0.45, width: CGFloat(size), height: CGFloat(size) * 0.55),
                   relativeCenterPosition: NSPoint(x: 0, y: 0.4))
    }

    // ---- Pass card (tilted -9deg) ----
    cg.saveGState()
    cg.translateBy(x: S(475), y: CGFloat(size) - S(500))
    cg.rotate(by: -9 * .pi / 180)
    let cardRect = NSRect(x: -S(220), y: -S(300), width: S(440), height: S(600))

    // card shadow
    cg.setShadow(offset: CGSize(width: 0, height: -S(18)), blur: S(40), color: color(8, 30, 60, 0.30).cgColor)
    let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: S(34), yRadius: S(34))
    color(255, 255, 255).setFill()
    cardPath.fill()
    cg.setShadow(offset: .zero, blur: 0, color: nil)

    // card gradient body
    cardPath.addClip()
    NSGradient(colors: [color(255, 255, 255), color(238, 244, 251)])!.draw(in: cardRect, angle: -90)

    // orange top band
    let band = NSBezierPath()
    let bandRect = NSRect(x: cardRect.minX, y: cardRect.maxY - S(150), width: cardRect.width, height: S(150))
    band.appendRect(bandRect)
    NSGradient(colors: [color(255, 122, 61), color(255, 90, 44)])!.draw(in: bandRect, angle: -90)

    // field placeholder lines
    color(199, 210, 224).setFill()
    NSBezierPath(roundedRect: NSRect(x: cardRect.minX + S(40), y: cardRect.maxY - S(150) - S(60), width: S(220), height: S(16)), xRadius: S(8), yRadius: S(8)).fill()
    NSBezierPath(roundedRect: NSRect(x: cardRect.minX + S(40), y: cardRect.maxY - S(150) - S(100), width: S(150), height: S(16)), xRadius: S(8), yRadius: S(8)).fill()

    // QR hint block
    let qr = NSRect(x: -S(75), y: cardRect.minY + S(60), width: S(150), height: S(150))
    color(255, 255, 255).setFill(); NSBezierPath(rect: qr).fill()
    color(27, 36, 48).setFill()
    let module = qr.width / 9
    func cell(_ cx: Int, _ cy: Int) { NSBezierPath(rect: NSRect(x: qr.minX + CGFloat(cx) * module, y: qr.minY + CGFloat(cy) * module, width: module, height: module)).fill() }
    // finder squares (corners)
    for (ox, oy) in [(0, 6), (6, 6), (0, 0)] {
        NSBezierPath(rect: NSRect(x: qr.minX + CGFloat(ox) * module, y: qr.minY + CGFloat(oy) * module, width: module * 3, height: module * 3)).fill()
        color(255, 255, 255).setFill()
        NSBezierPath(rect: NSRect(x: qr.minX + CGFloat(ox + 1) * module, y: qr.minY + CGFloat(oy + 1) * module, width: module, height: module)).fill()
        color(27, 36, 48).setFill()
    }
    // scattered body modules
    for (cx, cy) in [(4, 7), (5, 5), (7, 4), (4, 4), (5, 2), (2, 4), (7, 7), (4, 1), (1, 4), (5, 7)] { cell(cx, cy) }
    cg.restoreGState()

    // ---- Magnifier (bottom-right, overlapping card) ----
    let center = P(660, 660)
    cg.setShadow(offset: CGSize(width: 0, height: -S(14)), blur: S(30), color: color(8, 30, 60, 0.30).cgColor)
    // handle
    let handle = NSBezierPath()
    handle.lineWidth = S(40); handle.lineCapStyle = .round
    handle.move(to: NSPoint(x: center.x + S(95), y: center.y - S(95)))
    handle.line(to: NSPoint(x: center.x + S(190), y: center.y - S(190)))
    color(154, 170, 190).setStroke(); handle.stroke()
    cg.setShadow(offset: .zero, blur: 0, color: nil)

    // lens ring
    let ringRect = NSRect(x: center.x - S(150), y: center.y - S(150), width: S(300), height: S(300))
    let ring = NSBezierPath(ovalIn: ringRect)
    ring.lineWidth = S(28)
    NSGradient(colors: [color(244, 247, 251), color(154, 170, 190)])!.draw(in: ringRect, angle: -45)
    // draw the metal ring by stroking with a clip
    cg.saveGState()
    let outer = NSBezierPath(ovalIn: ringRect)
    let inner = NSBezierPath(ovalIn: ringRect.insetBy(dx: S(28), dy: S(28)))
    outer.append(inner.reversed)
    outer.addClip()
    NSGradient(colors: [color(244, 247, 251), color(194, 206, 221), color(154, 170, 190)])!.draw(in: ringRect, angle: -45)
    cg.restoreGState()

    // glass
    let glassRect = ringRect.insetBy(dx: S(28), dy: S(28))
    let glass = NSBezierPath(ovalIn: glassRect)
    color(170, 205, 245, 0.22).setFill(); glass.fill()
    cg.saveGState(); glass.addClip()
    // magnified bars
    color(27, 36, 48).setFill()
    let bx = glassRect.midX - S(60)
    for (i, w) in [S(14), S(8), S(18), S(10), S(14)].enumerated() {
        NSBezierPath(roundedRect: NSRect(x: bx + CGFloat(i) * S(28), y: glassRect.midY - S(45), width: w, height: S(90)), xRadius: w / 2, yRadius: w / 2).fill()
    }
    // glare
    if let glare = NSGradient(colors: [color(255, 255, 255, 0.55), color(255, 255, 255, 0)]) {
        glare.draw(in: glassRect, relativeCenterPosition: NSPoint(x: -0.4, y: 0.4))
    }
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// ---- Write all required sizes + Contents.json ----
struct Spec { let idiom = "mac"; let size: Int; let scale: Int }
let specs: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

var images: [[String: String]] = []
for (pt, scale) in specs {
    let px = pt * scale
    let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
    let data = drawIcon(size: px)
    try data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted])
try json.write(to: URL(fileURLWithPath: "\(outDir)/Contents.json"))
print("✅ Wrote AppIcon.appiconset (\(images.count) sizes) to \(outDir)")
