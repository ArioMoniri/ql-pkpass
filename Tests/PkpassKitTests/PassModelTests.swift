//
//  PassModelTests.swift
//  PkpassKitTests
//

import Testing
import Foundation
@testable import PkpassKit

struct PassModelTests {

    private func decode(_ json: String) throws -> Pass {
        try JSONDecoder().decode(Pass.self, from: Data(json.utf8))
    }

    @Test func detectsBoardingPassStyle() throws {
        let pass = try decode(Fixture.boardingPassJSON)
        #expect(pass.style == .boardingPass)
        #expect(pass.primaryStructure?.transitType == "PKTransitTypeAir")
    }

    @Test func detectsStoreCardStyle() throws {
        let pass = try decode(Fixture.storeCardJSON)
        #expect(pass.style == .storeCard)
    }

    @Test func coercesNumericFieldValueToString() throws {
        let pass = try decode(Fixture.boardingPassJSON)
        let seat = try #require(pass.primaryStructure?.secondaryFields?.first { $0.key == "seat" })
        #expect(seat.value == "14")
    }

    @Test func coercesDecimalFieldValue() throws {
        let pass = try decode(Fixture.storeCardJSON)
        let balance = try #require(pass.primaryStructure?.primaryFields?.first)
        #expect(balance.value == "12.5")
    }

    @Test func prefersBarcodesArrayOverLegacyBarcode() throws {
        let pass = try decode(Fixture.boardingPassJSON)
        #expect(pass.primaryBarcode?.format == "PKBarcodeFormatQR")
        #expect(pass.primaryBarcode?.message == "SKY-ABC123456")
    }

    @Test func fallsBackToLegacyBarcode() throws {
        let pass = try decode(Fixture.storeCardJSON)
        #expect(pass.primaryBarcode?.format == "PKBarcodeFormatPDF417")
    }

    @Test func resolvesColours() throws {
        let pass = try decode(Fixture.boardingPassJSON)
        #expect(pass.backgroundPassColor.css == "rgb(20, 110, 200)")
        #expect(pass.foregroundPassColor.css == "rgb(255, 255, 255)")
    }

    @Test func derivesDisplayTitle() throws {
        let pass = try decode(Fixture.boardingPassJSON)
        #expect(pass.displayTitle == "Skyline Air")
    }

    @Test func detectsExpiry() throws {
        let expiredJSON = """
        { "organizationName": "Old", "description": "x",
          "expirationDate": "2000-01-01T00:00:00Z", "generic": {} }
        """
        #expect(try decode(expiredJSON).isExpired)
        #expect(try !decode(Fixture.boardingPassJSON).isExpired)
    }

    @Test func prefersPlainValueOverAttributedValue() throws {
        let json = """
        { "organizationName": "X", "description": "y", "generic": {
          "primaryFields": [
            { "key": "k", "label": "L", "value": "Gate B12",
              "attributedValue": "Gate <a href='https://x.example'>B12</a>" }
          ]
        } }
        """
        let pass = try decode(json)
        let field = try #require(pass.primaryStructure?.primaryFields?.first)
        #expect(field.displayValue == "Gate B12")
    }

    @Test func formatsDateValueWhenDateStyleSet() throws {
        let json = """
        { "organizationName": "X", "description": "y", "generic": {
          "primaryFields": [
            { "key": "d", "label": "When", "value": "2023-06-15T09:41:00Z",
              "dateStyle": "PKDateStyleMedium" }
          ]
        } }
        """
        let pass = try decode(json)
        let field = try #require(pass.primaryStructure?.primaryFields?.first)
        // Should no longer be the raw ISO string.
        #expect(!field.displayValue.contains("T09:41"))
        #expect(field.displayValue.contains("2023"))
    }
}
