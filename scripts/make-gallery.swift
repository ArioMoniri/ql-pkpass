//
//  make-gallery.swift
//  Renders a gallery of portrait pass cards (boarding, coupon, store card,
//  event ticket, Google loyalty, Samsung coupon) into docs/assets/gallery/ so
//  the demo page shows the plugin works for every kind of pass, not just flights.
//
//  Compiled WITH the PkpassKit sources (see `make gallery`), so it can use the
//  internal builder + the public PkpassDocument initialiser directly.
//
//  Build/run:  swiftc Sources/PkpassKit/*.swift scripts/make-gallery.swift -o /tmp/ql-gallery && /tmp/ql-gallery
//

import AppKit
import Foundation

@main
struct Gallery {
    static func render(_ doc: PkpassDocument, to path: String, width: Int = 420, height: Int = 540) throws {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        PassThumbnailRenderer(document: doc).draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }

    static func appleDoc(_ dict: [String: Any]) throws -> PkpassDocument {
        let pass = try WalletPassBuilder.pass(fromPassKitDictionary: dict)
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]), as: UTF8.self)
        return PkpassDocument(pass: pass, rawPassJSON: raw, images: [:],
                              files: [PkpassFile(name: "pass.json", size: raw.utf8.count)],
                              isSigned: true, source: .applePkpass)
    }

    static func main() throws {
        let outDir = FileManager.default.currentDirectoryPath + "/docs/assets/gallery"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        let boarding: [String: Any] = [
            "organizationName": "Skyline Air", "logoText": "✈ SKYLINE", "description": "Boarding pass",
            "backgroundColor": "rgb(20, 110, 200)", "foregroundColor": "rgb(255,255,255)",
            "boardingPass": [
                "transitType": "PKTransitTypeAir",
                "primaryFields": [["key": "o", "label": "San Francisco", "value": "SFO"],
                                  ["key": "d", "label": "London", "value": "LHR"]],
                "secondaryFields": [["key": "p", "label": "PASSENGER", "value": "J. Appleseed"]]
            ],
            "barcodes": [["format": "PKBarcodeFormatQR", "message": "SKY-219-2A", "messageEncoding": "iso-8859-1"]]
        ]
        let coupon: [String: Any] = [
            "organizationName": "Brew & Co", "logoText": "BREW & CO", "description": "Coupon",
            "backgroundColor": "rgb(226, 90, 40)", "foregroundColor": "rgb(255,255,255)",
            "coupon": ["primaryFields": [["key": "off", "label": "Coupon", "value": "20% OFF"]],
                       "secondaryFields": [["key": "ex", "label": "EXPIRES", "value": "Dec 31"]]],
            "barcodes": [["format": "PKBarcodeFormatPDF417", "message": "BREW-20OFF-7H3K", "messageEncoding": "iso-8859-1"]]
        ]
        let storeCard: [String: Any] = [
            "organizationName": "Fresh Mart", "logoText": "FRESH MART", "description": "Store card",
            "backgroundColor": "rgb(15, 125, 44)", "foregroundColor": "rgb(255,255,255)",
            "storeCard": ["primaryFields": [["key": "bal", "label": "Balance", "value": "$24.50"]],
                          "secondaryFields": [["key": "m", "label": "MEMBER", "value": "Gold"]]],
            "barcodes": [["format": "PKBarcodeFormatQR", "message": "FM-GOLD-0042", "messageEncoding": "iso-8859-1"]]
        ]
        let eventTicket: [String: Any] = [
            "organizationName": "Live Nation", "logoText": "LIVE NATION", "description": "Event ticket",
            "backgroundColor": "rgb(94, 53, 177)", "foregroundColor": "rgb(255,255,255)",
            "eventTicket": ["primaryFields": [["key": "ev", "label": "Event", "value": "The Strokes"]],
                            "secondaryFields": [["key": "sec", "label": "SEC", "value": "A"],
                                                ["key": "row", "label": "ROW", "value": "12"]]],
            "barcodes": [["format": "PKBarcodeFormatAztec", "message": "LN-STROKES-A12-5", "messageEncoding": "iso-8859-1"]]
        ]

        try render(appleDoc(boarding), to: "\(outDir)/boarding.png")
        try render(appleDoc(coupon), to: "\(outDir)/coupon.png")
        try render(appleDoc(storeCard), to: "\(outDir)/storecard.png")
        try render(appleDoc(eventTicket), to: "\(outDir)/eventticket.png")

        let cwd = FileManager.default.currentDirectoryPath
        if let google = try? PassDocumentLoader.document(contentsOf: URL(fileURLWithPath: "\(cwd)/examples/Google-Loyalty.gwallet")) {
            try render(google, to: "\(outDir)/google.png")
        }
        if let samsung = try? PassDocumentLoader.document(contentsOf: URL(fileURLWithPath: "\(cwd)/examples/Samsung-Coupon.swcard")) {
            try render(samsung, to: "\(outDir)/samsung.png")
        }

        print("✅ Wrote gallery cards to \(outDir)")
    }
}
