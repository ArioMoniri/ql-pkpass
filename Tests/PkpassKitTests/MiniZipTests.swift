//
//  MiniZipTests.swift
//  PkpassKitTests
//

import Testing
import Foundation
@testable import PkpassKit

struct MiniZipTests {

    @Test func extractsDeflatedAndStoredEntries() throws {
        let icon = Fixture.png(color: .systemRed)
        let data = try Fixture.makePkpass(
            passJSON: Fixture.boardingPassJSON,
            images: ["icon.png": icon, "logo.png": Fixture.png(color: .white)]
        )

        let entries = try MiniZip.entries(from: data)

        #expect(entries["pass.json"] != nil)
        #expect(entries["icon.png"] == icon)
        #expect(entries["logo.png"] != nil)
        #expect(entries["signature"] != nil)
    }

    @Test func extractsStoredOnlyArchive() throws {
        let data = try Fixture.makePkpass(
            passJSON: Fixture.storeCardJSON,
            images: ["icon.png": Fixture.png()],
            stored: true
        )

        let entries = try MiniZip.entries(from: data)
        let passJSON = try #require(entries["pass.json"])
        #expect(String(decoding: passJSON, as: UTF8.self).contains("Bean & Brew"))
    }

    @Test func roundTripsExactJSONBytes() throws {
        let data = try Fixture.makePkpass(passJSON: Fixture.boardingPassJSON)
        let entries = try MiniZip.entries(from: data)
        let passJSON = try #require(entries["pass.json"])
        #expect(passJSON == Data(Fixture.boardingPassJSON.utf8))
    }

    @Test func decompressesLargeButValidEntry() throws {
        // ~580 KB of real text — well under the 64 MiB cap, exercises the
        // size-bounded fast path with a genuine central-directory size.
        let note = String(repeating: "Skyline frequent flyer note. ", count: 20_000)
        let json = """
        { "organizationName": "Big", "description": "x", "generic": {
            "backFields": [ { "key": "n", "label": "Notes", "value": "\(note)" } ] } }
        """
        let data = try Fixture.makePkpass(passJSON: json)
        let entries = try MiniZip.entries(from: data)
        let passJSON = try #require(entries["pass.json"])
        #expect(passJSON.count > 500_000)
    }

    @Test func rejectsNonZipData() {
        let garbage = Data("this is definitely not a zip file".utf8)
        #expect(throws: MiniZipError.self) {
            _ = try MiniZip.entries(from: garbage)
        }
    }

    @Test func rejectsEmptyData() {
        #expect(throws: MiniZipError.self) {
            _ = try MiniZip.entries(from: Data())
        }
    }
}
