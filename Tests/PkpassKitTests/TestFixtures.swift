//
//  TestFixtures.swift
//  PkpassKitTests
//
//  Helpers that build real `.pkpass` archives on disk (via /usr/bin/zip) so the
//  tests exercise the exact ZIP format produced in the wild — both DEFLATE
//  (pass.json) and stored (already-compressed PNG) entries.
//

import Foundation
import AppKit

enum Fixture {

    /// Generates a tiny solid-colour PNG.
    static func png(width: Int = 8, height: Int = 8, color: NSColor = .systemBlue) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    /// Builds a `.pkpass` archive in memory.
    /// - Parameters:
    ///   - passJSON: the pass.json contents.
    ///   - images: filename → PNG bytes.
    ///   - includeSignature: write a placeholder `signature` entry.
    ///   - stored: use `zip -0` (no compression) to force stored entries.
    static func makePkpass(
        passJSON: String,
        images: [String: Data] = [:],
        includeSignature: Bool = true,
        stored: Bool = false
    ) throws -> Data {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        try Data(passJSON.utf8).write(to: dir.appendingPathComponent("pass.json"))
        for (name, data) in images {
            try data.write(to: dir.appendingPathComponent(name))
        }
        if includeSignature {
            try Data([0x30, 0x80]).write(to: dir.appendingPathComponent("signature"))
        }

        let output = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pkpass")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        var args = ["-r", "-q", "-X"]
        if stored { args.append("-0") }
        args.append(output.path)
        args.append(".")
        process.arguments = args
        process.currentDirectoryURL = dir
        try process.run()
        process.waitUntilExit()

        let data = try Data(contentsOf: output)
        try? fm.removeItem(at: output)
        return data
    }

    // MARK: - Sample pass.json payloads

    static let boardingPassJSON = """
    {
      "formatVersion": 1,
      "passTypeIdentifier": "pass.com.example.boarding",
      "serialNumber": "ABC123456",
      "teamIdentifier": "TEAM123",
      "organizationName": "Skyline Air",
      "description": "Skyline Air Boarding Pass",
      "logoText": "Skyline Air",
      "foregroundColor": "rgb(255, 255, 255)",
      "backgroundColor": "rgb(20, 110, 200)",
      "labelColor": "rgb(220, 235, 255)",
      "expirationDate": "2999-12-31T23:59:59Z",
      "boardingPass": {
        "transitType": "PKTransitTypeAir",
        "headerFields": [
          { "key": "gate", "label": "GATE", "value": "A12" }
        ],
        "primaryFields": [
          { "key": "origin", "label": "San Francisco", "value": "SFO" },
          { "key": "destination", "label": "London", "value": "LHR" }
        ],
        "secondaryFields": [
          { "key": "passenger", "label": "PASSENGER", "value": "J. Appleseed" },
          { "key": "seat", "label": "SEAT", "value": 14, "textAlignment": "PKTextAlignmentRight" }
        ],
        "auxiliaryFields": [
          { "key": "boards", "label": "BOARDS", "value": "10:30 AM" }
        ],
        "backFields": [
          { "key": "terms", "label": "Terms", "value": "Visit https://example.com for details." }
        ]
      },
      "barcodes": [
        { "format": "PKBarcodeFormatQR", "message": "SKY-ABC123456", "messageEncoding": "iso-8859-1", "altText": "SKY-ABC123456" }
      ]
    }
    """

    static let storeCardJSON = """
    {
      "formatVersion": 1,
      "passTypeIdentifier": "pass.com.example.store",
      "serialNumber": "S-001",
      "teamIdentifier": "TEAM123",
      "organizationName": "Bean & Brew",
      "description": "Loyalty Card",
      "backgroundColor": "#0a7d2c",
      "storeCard": {
        "primaryFields": [
          { "key": "balance", "label": "BALANCE", "value": 12.5, "currencyCode": "USD" }
        ],
        "secondaryFields": [
          { "key": "member", "label": "MEMBER", "value": "Gold" }
        ]
      },
      "barcode": { "format": "PKBarcodeFormatPDF417", "message": "LOYALTY-0001" }
    }
    """
}
