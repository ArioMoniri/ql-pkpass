#!/usr/bin/env swift
//
//  make-sample-pass.swift
//  Generates a self-contained sample .pkpass (with drawn logo + icon images)
//  so you can try the Quick Look plugin immediately.
//
//  Usage: swift scripts/make-sample-pass.swift [output.pkpass]
//

import AppKit
import Foundation

func makePNG(width: Int, height: Int, _ draw: (NSRect) -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func logo(scale: Int) -> Data {
    makePNG(width: 160 * scale, height: 40 * scale) { rect in
        let text = "✈ SKYLINE"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: CGFloat(22 * scale), weight: .heavy),
            .foregroundColor: NSColor.white
        ]
        let string = NSAttributedString(string: text, attributes: attrs)
        let size = string.size()
        string.draw(at: NSPoint(x: 0, y: (rect.height - size.height) / 2))
    }
}

func icon(scale: Int) -> Data {
    makePNG(width: 58 * scale, height: 58 * scale) { rect in
        let path = NSBezierPath(roundedRect: rect, xRadius: CGFloat(12 * scale), yRadius: CGFloat(12 * scale))
        NSColor(srgbRed: 20 / 255, green: 110 / 255, blue: 200 / 255, alpha: 1).setFill()
        path.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: CGFloat(30 * scale), weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let string = NSAttributedString(string: "✈", attributes: attrs)
        let size = string.size()
        string.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
    }
}

let passJSON = """
{
  "formatVersion": 1,
  "passTypeIdentifier": "pass.com.example.skyline",
  "serialNumber": "SKY-2026-0042",
  "teamIdentifier": "DEMO123456",
  "organizationName": "Skyline Air",
  "description": "Skyline Air Boarding Pass",
  "logoText": "Skyline Air",
  "foregroundColor": "rgb(255, 255, 255)",
  "backgroundColor": "rgb(20, 110, 200)",
  "labelColor": "rgb(210, 230, 255)",
  "relevantDate": "2026-09-15T10:00:00Z",
  "expirationDate": "2026-09-15T23:59:59Z",
  "boardingPass": {
    "transitType": "PKTransitTypeAir",
    "headerFields": [
      { "key": "gate", "label": "GATE", "value": "A12" },
      { "key": "flight", "label": "FLIGHT", "value": "SK 219" }
    ],
    "primaryFields": [
      { "key": "origin", "label": "San Francisco", "value": "SFO" },
      { "key": "destination", "label": "London", "value": "LHR" }
    ],
    "secondaryFields": [
      { "key": "passenger", "label": "PASSENGER", "value": "J. APPLESEED" },
      { "key": "class", "label": "CLASS", "value": "Business" }
    ],
    "auxiliaryFields": [
      { "key": "boards", "label": "BOARDS", "value": "9:25 AM" },
      { "key": "seat", "label": "SEAT", "value": "2A" },
      { "key": "zone", "label": "ZONE", "value": "1" }
    ],
    "backFields": [
      { "key": "terms", "label": "Conditions", "value": "Boarding closes 15 minutes before departure. More at https://example.com/help" },
      { "key": "baggage", "label": "Baggage", "value": "1 carry-on + 1 checked bag included." }
    ]
  },
  "barcodes": [
    {
      "format": "PKBarcodeFormatQR",
      "message": "SKYLINE|SK219|SFO-LHR|2A|J.APPLESEED|SKY-2026-0042",
      "messageEncoding": "iso-8859-1",
      "altText": "SK 219 · Seat 2A"
    }
  ]
}
"""

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/examples/Skyline-BoardingPass.pkpass"

let fm = FileManager.default
let staging = fm.temporaryDirectory.appendingPathComponent("pkpass-sample-" + UUID().uuidString, isDirectory: true)
try fm.createDirectory(at: staging, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: staging) }

try Data(passJSON.utf8).write(to: staging.appendingPathComponent("pass.json"))
try logo(scale: 1).write(to: staging.appendingPathComponent("logo.png"))
try logo(scale: 2).write(to: staging.appendingPathComponent("logo@2x.png"))
try icon(scale: 1).write(to: staging.appendingPathComponent("icon.png"))
try icon(scale: 2).write(to: staging.appendingPathComponent("icon@2x.png"))
// A placeholder signature so the preview's "Signed" badge has something to show.
try Data([0x30, 0x82, 0x01, 0x00]).write(to: staging.appendingPathComponent("signature"))

let outputURL = URL(fileURLWithPath: outputPath)
try? fm.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try? fm.removeItem(at: outputURL)

let zip = Process()
zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
zip.arguments = ["-r", "-q", "-X", outputURL.path, "."]
zip.currentDirectoryURL = staging
try zip.run()
zip.waitUntilExit()

print("✅ Wrote sample pass: \(outputURL.path)")
