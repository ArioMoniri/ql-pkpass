//
//  WalletParserTests.swift
//  PkpassKitTests
//

import Testing
import Foundation
@testable import PkpassKit

struct GoogleWalletParserTests {

    private let genericJSON = """
    {
      "genericObjects": [
        {
          "id": "issuer.generic-001",
          "classId": "issuer.generic-class-001",
          "state": "ACTIVE",
          "cardTitle": { "defaultValue": { "language": "en-US", "value": "Acme Corp" } },
          "header":    { "defaultValue": { "language": "en-US", "value": "Membership Card" } },
          "subheader": { "defaultValue": { "language": "en-US", "value": "Downtown Branch" } },
          "hexBackgroundColor": "#1a73e8",
          "barcode": { "type": "QR_CODE", "value": "GEN-9F2A-77C1", "alternateText": "9F2A-77C1" },
          "textModulesData": [
            { "id": "since", "header": "Member Since", "body": "2021" },
            { "id": "tier", "header": "Status", "body": "Gold" }
          ],
          "linksModuleData": { "uris": [ { "uri": "https://example.com", "description": "Website" } ] }
        }
      ]
    }
    """

    private let loyaltyJSON = """
    {
      "loyaltyClasses": [
        { "id": "issuer.loy-class", "issuerName": "Adam's Apparel", "programName": "Adam's Rewards",
          "hexBackgroundColor": "#0f9d58", "accountNameLabel": "Member Name", "accountIdLabel": "Member ID" }
      ],
      "loyaltyObjects": [
        { "id": "issuer.loy-001", "classId": "issuer.loy-class", "state": "ACTIVE",
          "accountName": "Jane Doe", "accountId": "1234567890",
          "loyaltyPoints": { "label": "Points", "balance": { "int": 1250 } },
          "barcode": { "type": "CODE_128", "value": "1234567890", "alternateText": "1234 5678 90" } }
      ]
    }
    """

    @Test func parsesGenericObject() throws {
        let doc = try GoogleWalletParser.makeDocument(from: Data(genericJSON.utf8))
        #expect(doc.source == .googleWallet)
        #expect(doc.pass.organizationName == "Acme Corp")
        #expect(doc.pass.primaryBarcode?.format == "PKBarcodeFormatQR")
        #expect(doc.pass.primaryBarcode?.message == "GEN-9F2A-77C1")
        let html = PassHTMLRenderer(document: doc).render()
        #expect(html.contains("Membership Card"))
        #expect(html.contains("rgb(26, 115, 232)")) // #1a73e8
        #expect(html.contains("Website"))
    }

    @Test func parsesLoyaltyObjectWithClass() throws {
        let doc = try GoogleWalletParser.makeDocument(from: Data(loyaltyJSON.utf8))
        #expect(doc.pass.organizationName == "Adam's Apparel")
        #expect(doc.pass.primaryBarcode?.format == "PKBarcodeFormatCode128")
        let html = PassHTMLRenderer(document: doc).render()
        #expect(html.contains("Jane Doe"))
        #expect(html.contains("1250"))
    }

    @Test func unwrapsJWTPayload() throws {
        let wrapped = "{ \"iss\": \"x\", \"aud\": \"google\", \"typ\": \"savetowallet\", \"payload\": \(genericJSON) }"
        let doc = try GoogleWalletParser.makeDocument(from: Data(wrapped.utf8))
        #expect(doc.pass.organizationName == "Acme Corp")
    }

    @Test func matchesDetection() {
        let obj = try! JSONSerialization.jsonObject(with: Data(genericJSON.utf8)) as! [String: Any]
        #expect(GoogleWalletParser.matches(obj))
    }
}

struct SamsungWalletParserTests {

    private let couponJSON = """
    {
      "card": {
        "type": "coupon",
        "subType": "others",
        "data": [
          {
            "refId": "coupon-2026-0001",
            "createdAt": 1749859200000,
            "language": "en",
            "attributes": {
              "title": "20% Off Everything",
              "providerName": "Acme Coffee",
              "bgColor": "#0A1A4F",
              "fontColor": "light",
              "noticeDesc": "Valid in-store only.",
              "extendedFields": [ { "label": "Code", "value": "SAVE20", "order": 1 } ],
              "barcode": { "value": "ACME-20OFF-7H3K9", "serialType": "QRCODE", "ptSubFormat": "QR_CODE" }
            }
          }
        ]
      }
    }
    """

    @Test func parsesCoupon() throws {
        let doc = try SamsungWalletParser.makeDocument(from: Data(couponJSON.utf8))
        #expect(doc.source == .samsungWallet)
        #expect(doc.pass.organizationName == "Acme Coffee")
        #expect(doc.pass.backgroundPassColor.css == "rgb(10, 26, 79)")
        #expect(doc.pass.foregroundPassColor.css == "rgb(255, 255, 255)") // fontColor "light"
        #expect(doc.pass.primaryBarcode?.format == "PKBarcodeFormatQR")
        let html = PassHTMLRenderer(document: doc).render()
        #expect(html.contains("20% Off Everything"))
        #expect(html.contains("SAVE20"))
        #expect(html.contains("Valid in-store only."))
    }

    @Test func matchesDetection() {
        let obj = try! JSONSerialization.jsonObject(with: Data(couponJSON.utf8)) as! [String: Any]
        #expect(SamsungWalletParser.matches(obj))
    }
}

struct PassDocumentLoaderTests {

    @Test func routesApplePkpass() throws {
        let data = try Fixture.makePkpass(passJSON: Fixture.boardingPassJSON, images: ["icon.png": Fixture.png()])
        let doc = try PassDocumentLoader.document(from: data)
        #expect(doc.source == .applePkpass)
        #expect(doc.pass.style == .boardingPass)
    }

    @Test func routesGoogle() throws {
        let json = """
        { "genericObjects": [ { "id": "x.1", "classId": "x.c",
          "cardTitle": { "defaultValue": { "language": "en", "value": "G" } },
          "barcode": { "type": "QR_CODE", "value": "Z" } } ] }
        """
        let doc = try PassDocumentLoader.document(from: Data(json.utf8))
        #expect(doc.source == .googleWallet)
    }

    @Test func routesSamsung() throws {
        let json = """
        { "card": { "type": "loyalty", "subType": "others", "data": [
          { "refId": "1", "createdAt": 1, "language": "en",
            "attributes": { "title": "S", "providerName": "P" } } ] } }
        """
        let doc = try PassDocumentLoader.document(from: Data(json.utf8))
        #expect(doc.source == .samsungWallet)
    }

    @Test func rejectsGarbage() {
        #expect(throws: (any Error).self) {
            _ = try PassDocumentLoader.document(from: Data("not a pass".utf8))
        }
    }
}
