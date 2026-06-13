//
//  RendererTests.swift
//  PkpassKitTests
//

import Testing
import Foundation
import AppKit
@testable import PkpassKit

struct PkpassDocumentTests {

    @Test func parsesFullDocument() throws {
        let logo3x = Fixture.png(width: 24, height: 24, color: .white)
        let data = try Fixture.makePkpass(
            passJSON: Fixture.boardingPassJSON,
            images: [
                "icon.png": Fixture.png(),
                "logo.png": Fixture.png(color: .gray),
                "logo@2x.png": Fixture.png(width: 16, height: 16, color: .lightGray),
                "logo@3x.png": logo3x
            ]
        )

        let document = try PkpassDocument(data: data)
        #expect(document.pass.organizationName == "Skyline Air")
        #expect(document.isSigned)
        #expect(document.images.count >= 4)
    }

    @Test func prefersHighestResolutionImage() throws {
        let logo3x = Fixture.png(width: 24, height: 24, color: .white)
        let data = try Fixture.makePkpass(
            passJSON: Fixture.boardingPassJSON,
            images: [
                "logo.png": Fixture.png(color: .gray),
                "logo@2x.png": Fixture.png(color: .lightGray),
                "logo@3x.png": logo3x
            ]
        )
        let document = try PkpassDocument(data: data)
        #expect(document.image(named: "logo") == logo3x)
    }

    @Test func throwsWhenPassJSONMissing() throws {
        // A zip with only an image, no pass.json.
        let data = try Fixture.makePkpass(
            passJSON: "{}",
            images: [:],
            includeSignature: false
        )
        // Replace: build an archive that genuinely lacks pass.json.
        let noPass = try buildArchiveWithoutPassJSON()
        #expect(throws: PkpassError.self) {
            _ = try PkpassDocument(data: noPass)
        }
        // Sanity: the normal one still parses.
        #expect((try? PkpassDocument(data: data)) != nil)
    }

    private func buildArchiveWithoutPassJSON() throws -> Data {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try Fixture.png().write(to: dir.appendingPathComponent("icon.png"))
        let out = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pkpass")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.arguments = ["-r", "-q", "-X", out.path, "."]
        p.currentDirectoryURL = dir
        try p.run(); p.waitUntilExit()
        let data = try Data(contentsOf: out)
        try? fm.removeItem(at: out)
        return data
    }
}

struct BarcodeRendererTests {

    private let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    @Test func rendersQRCode() throws {
        let barcode = PassBarcode(format: "PKBarcodeFormatQR", message: "HELLO-123", altText: nil, messageEncoding: "iso-8859-1")
        let data = try #require(BarcodeRenderer.pngData(for: barcode))
        #expect(data.count > 100)
        #expect(Array(data.prefix(8)) == pngSignature)
    }

    @Test func rendersPDF417() throws {
        let barcode = PassBarcode(format: "PKBarcodeFormatPDF417", message: "LOYALTY-0001", altText: nil, messageEncoding: nil)
        let data = try #require(BarcodeRenderer.pngData(for: barcode))
        #expect(Array(data.prefix(8)) == pngSignature)
    }

    @Test func rendersCode128AndAztec() throws {
        let code128 = PassBarcode(format: "PKBarcodeFormatCode128", message: "ABC123", altText: nil, messageEncoding: nil)
        let aztec = PassBarcode(format: "PKBarcodeFormatAztec", message: "XYZ789", altText: nil, messageEncoding: nil)
        #expect(BarcodeRenderer.pngData(for: code128) != nil)
        #expect(BarcodeRenderer.pngData(for: aztec) != nil)
    }

    @Test func returnsNilForEmptyMessage() {
        let barcode = PassBarcode(format: "PKBarcodeFormatQR", message: "", altText: nil, messageEncoding: nil)
        #expect(BarcodeRenderer.pngData(for: barcode) == nil)
    }
}

struct PassHTMLRendererTests {

    private func render(_ json: String, images: [String: Data] = [:]) throws -> String {
        let data = try Fixture.makePkpass(passJSON: json, images: images)
        let document = try PkpassDocument(data: data)
        return PassHTMLRenderer(document: document).render()
    }

    @Test func includesOrganizationAndFields() throws {
        let html = try render(Fixture.boardingPassJSON)
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("Skyline Air"))
        #expect(html.contains("SFO"))
        #expect(html.contains("LHR"))
        #expect(html.contains("J. Appleseed"))
    }

    @Test func embedsBarcodeImage() throws {
        let html = try render(Fixture.boardingPassJSON)
        #expect(html.contains("data:image/png;base64,"))
        #expect(html.contains("barcode-card"))
    }

    @Test func embedsLogoImage() throws {
        let html = try render(Fixture.boardingPassJSON, images: ["logo.png": Fixture.png(color: .white)])
        #expect(html.contains("class=\"logo\""))
    }

    @Test func appliesBackgroundColor() throws {
        let html = try render(Fixture.boardingPassJSON)
        #expect(html.contains("rgb(20, 110, 200)"))
    }

    @Test func rendersBackFieldsAndRawJSON() throws {
        let html = try render(Fixture.boardingPassJSON)
        #expect(html.contains("Back of pass"))
        #expect(html.contains("Raw pass.json"))
        #expect(html.contains("Terms"))
    }

    @Test func linkifiesURLsInBackFields() throws {
        let html = try render(Fixture.boardingPassJSON)
        #expect(html.contains("<a href=\"https://example.com"))
    }

    @Test func escapesHTMLInValues() throws {
        let json = """
        { "organizationName": "Acme <script>", "description": "x",
          "generic": { "primaryFields": [ { "key": "k", "label": "L", "value": "<b>bad</b>" } ] } }
        """
        let html = try render(json)
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;b&gt;bad&lt;/b&gt;"))
    }

    @Test func showsBoardingTransitSymbol() throws {
        let html = try render(Fixture.boardingPassJSON)
        #expect(html.contains("✈️"))
    }
}

struct PassThumbnailRendererTests {

    @Test func drawsWithoutCrashing() throws {
        let data = try Fixture.makePkpass(
            passJSON: Fixture.boardingPassJSON,
            images: ["logo.png": Fixture.png(width: 40, height: 20, color: .white)]
        )
        let document = try PkpassDocument(data: data)
        let renderer = PassThumbnailRenderer(document: document)

        let size = NSSize(width: 128, height: 128)
        let image = NSImage(size: size)
        image.lockFocus()
        renderer.draw(in: CGRect(origin: .zero, size: size))
        image.unlockFocus()

        #expect(image.size == size)
    }

    @Test func drawsMonogramWhenNoImages() throws {
        let data = try Fixture.makePkpass(passJSON: Fixture.storeCardJSON)
        let document = try PkpassDocument(data: data)
        let renderer = PassThumbnailRenderer(document: document)

        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        renderer.draw(in: CGRect(x: 0, y: 0, width: 64, height: 64))
        image.unlockFocus()
        #expect(Bool(true)) // reaching here means no crash
    }
}
