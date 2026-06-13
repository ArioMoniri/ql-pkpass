//
//  GoogleWalletParser.swift
//  PkpassKit
//
//  Renders Google Wallet passes. Google has no .pkpass-style file: a pass is the
//  JSON of a "Save to Google Wallet" JWT payload (arrays of generic/loyalty/…
//  objects + classes). We accept that JSON (or a raw JWT, or a single object),
//  map it onto a PassKit-shaped dictionary, and reuse the normal renderer.
//
//  Note: Google logos/hero images are remote URLs, not embedded — a sandboxed
//  preview has no network, so we render colours, text and the (locally drawn)
//  barcode. That is the correct, privacy-preserving behaviour.
//

import Foundation

public enum GoogleWalletParser {

    private static let verticals = [
        "genericObjects", "loyaltyObjects", "eventTicketObjects",
        "offerObjects", "giftCardObjects", "flightObjects", "transitObjects"
    ]

    /// Returns `true` if the JSON looks like a Google Wallet pass.
    public static func matches(_ object: [String: Any]) -> Bool {
        let root = unwrapPayload(object)
        if verticals.contains(where: { root[$0] != nil }) { return true }
        // A single bare object.
        if root["classId"] != nil, (root["id"] != nil || root["cardTitle"] != nil) { return true }
        return false
    }

    public static func makeDocument(from data: Data) throws -> PkpassDocument {
        let json = try jsonObject(from: data)
        let root = unwrapPayload(json)

        guard let object = firstObject(in: root) else {
            throw PkpassError.invalidPassJSON("no Google Wallet object found")
        }
        let klass = matchingClass(for: object, in: root)

        let dict = passKitDictionary(object: object, klass: klass)
        let pass = try WalletPassBuilder.pass(fromPassKitDictionary: dict)

        let raw = WalletPassBuilder.prettyJSON(data)
        let files = [PkpassFile(name: "pass.json (Google Wallet)", size: data.count)]
        return PkpassDocument(
            pass: pass,
            rawPassJSON: raw,
            images: [:],
            files: files,
            isSigned: false,
            source: .googleWallet
        )
    }

    // MARK: - Mapping

    private static func passKitDictionary(object: [String: Any], klass: [String: Any]?) -> [String: Any] {
        let title = localized(object["cardTitle"])
            ?? string(klass?["issuerName"])
            ?? string(klass?["programName"])
            ?? "Google Wallet Pass"
        let header = localized(object["header"])
            ?? string(klass?["programName"])
        let subheader = localized(object["subheader"])

        var primary: [[String: Any]] = []
        var secondary: [[String: Any]] = []
        var back: [[String: Any]] = []

        if let header, let f = WalletPassBuilder.field(key: "header", label: nil, value: header) {
            primary.append(f)
        }
        if let subheader, let f = WalletPassBuilder.field(key: "subheader", label: nil, value: subheader) {
            secondary.append(f)
        }

        // Loyalty specifics.
        if let points = object["loyaltyPoints"] as? [String: Any] {
            if let f = pointsField(points, key: "points") { primary.append(f) }
        }
        if let points = object["secondaryLoyaltyPoints"] as? [String: Any] {
            if let f = pointsField(points, key: "points2") { secondary.append(f) }
        }
        if let account = string(object["accountName"]),
           let f = WalletPassBuilder.field(key: "account", label: string(klass?["accountNameLabel"]) ?? "Member", value: account) {
            secondary.append(f)
        }
        if let accountId = string(object["accountId"]),
           let f = WalletPassBuilder.field(key: "accountId", label: string(klass?["accountIdLabel"]) ?? "ID", value: accountId) {
            secondary.append(f)
        }

        // Text modules (object + class) → secondary (first couple) and back.
        let modules = textModules(object["textModulesData"]) + textModules(klass?["textModulesData"])
        for (index, module) in modules.enumerated() {
            if index < 2, let f = WalletPassBuilder.field(key: "m\(index)", label: module.header, value: module.body) {
                secondary.append(f)
            }
            if let f = WalletPassBuilder.field(key: "b\(index)", label: module.header ?? "Details", value: module.body) {
                back.append(f)
            }
        }

        // Links → back fields.
        if let links = (object["linksModuleData"] as? [String: Any])?["uris"] as? [[String: Any]] {
            for (index, link) in links.enumerated() {
                let desc = string(link["description"]) ?? "Link"
                if let uri = string(link["uri"]),
                   let f = WalletPassBuilder.field(key: "l\(index)", label: desc, value: uri) {
                    back.append(f)
                }
            }
        }

        let barcode = object["barcode"] as? [String: Any]
        let barcodes = WalletPassBuilder.barcodeArray(
            format: string(barcode?["type"]),
            message: string(barcode?["value"]),
            altText: string(barcode?["alternateText"])
        )

        var generic: [String: Any] = [:]
        if !primary.isEmpty { generic["primaryFields"] = primary }
        if !secondary.isEmpty { generic["secondaryFields"] = secondary }
        if !back.isEmpty { generic["backFields"] = back }

        var dict: [String: Any] = [
            "formatVersion": 1,
            "organizationName": title,
            "description": header ?? title,
            "logoText": title,
            "generic": generic
        ]
        if let hex = string(object["hexBackgroundColor"]) ?? string(klass?["hexBackgroundColor"]) {
            dict["backgroundColor"] = hex
        }
        if !barcodes.isEmpty { dict["barcodes"] = barcodes }
        if let id = string(object["id"]) { dict["serialNumber"] = id }
        return dict
    }

    private static func pointsField(_ points: [String: Any], key: String) -> [String: Any]? {
        let label = localized(points["localizedLabel"]) ?? string(points["label"])
        guard let balance = points["balance"] as? [String: Any] else { return nil }
        let value: String?
        if let s = string(balance["string"]) { value = s }
        else if let i = balance["int"] as? Int { value = String(i) }
        else if let d = balance["double"] as? Double { value = String(d) }
        else if let money = balance["money"] as? [String: Any] {
            value = string(money["micros"]).map { (Double($0) ?? 0) / 1_000_000 }.map { "\($0)" }
        } else { value = nil }
        return WalletPassBuilder.field(key: key, label: label, value: value)
    }

    // MARK: - JSON helpers

    private struct Module { let header: String?; let body: String? }

    private static func textModules(_ any: Any?) -> [Module] {
        guard let array = any as? [[String: Any]] else { return [] }
        return array.map {
            Module(
                header: localized($0["localizedHeader"]) ?? string($0["header"]),
                body: localized($0["localizedBody"]) ?? string($0["body"])
            )
        }
    }

    private static func firstObject(in root: [String: Any]) -> [String: Any]? {
        for vertical in verticals {
            if let array = root[vertical] as? [[String: Any]], let first = array.first {
                return first
            }
        }
        // Single bare object at the root.
        if root["classId"] != nil { return root }
        return nil
    }

    private static func matchingClass(for object: [String: Any], in root: [String: Any]) -> [String: Any]? {
        guard let classId = string(object["classId"]) else { return nil }
        for vertical in verticals {
            let classesKey = vertical.replacingOccurrences(of: "Objects", with: "Classes")
            if let array = root[classesKey] as? [[String: Any]],
               let match = array.first(where: { string($0["id"]) == classId }) {
                return match
            }
        }
        return nil
    }

    /// Unwraps a full "Save to Google Wallet" JWT payload `{ payload: {...} }`.
    private static func unwrapPayload(_ object: [String: Any]) -> [String: Any] {
        if let payload = object["payload"] as? [String: Any] { return payload }
        return object
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        // Plain JSON.
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        // A raw JWT string: header.payload.signature — decode the middle segment.
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = text.split(separator: ".")
        if segments.count >= 2, let payloadData = base64URLDecode(String(segments[1])),
           let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
            return object
        }
        throw PkpassError.invalidPassJSON("not valid Google Wallet JSON or JWT")
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }

    /// Resolves a Google LocalizedString (`{defaultValue:{value}}`) or plain string.
    private static func localized(_ any: Any?) -> String? {
        if let s = any as? String { return s.isEmpty ? nil : s }
        if let dict = any as? [String: Any] {
            if let def = dict["defaultValue"] as? [String: Any], let value = def["value"] as? String {
                return value.isEmpty ? nil : value
            }
            if let value = dict["value"] as? String { return value.isEmpty ? nil : value }
        }
        return nil
    }

    private static func string(_ any: Any?) -> String? {
        if let s = any as? String { return s.isEmpty ? nil : s }
        if let i = any as? Int { return String(i) }
        if let d = any as? Double { return String(d) }
        return nil
    }
}
