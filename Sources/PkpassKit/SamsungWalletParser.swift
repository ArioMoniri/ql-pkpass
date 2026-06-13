//
//  SamsungWalletParser.swift
//  PkpassKit
//
//  Renders Samsung Wallet cards. Samsung has no end-user file format and its
//  on-the-wire `cdata` token is encrypted to Samsung — so we accept the
//  documented "Wallet Card" JSON ({ card: { type, subType, data: [...] } }),
//  which is the only human-readable, renderable representation.
//

import Foundation

public enum SamsungWalletParser {

    /// Returns `true` if the JSON looks like a Samsung Wallet card.
    public static func matches(_ object: [String: Any]) -> Bool {
        guard let card = object["card"] as? [String: Any] else { return false }
        return card["data"] != nil || card["type"] != nil
    }

    public static func makeDocument(from data: Data) throws -> PkpassDocument {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let card = object["card"] as? [String: Any] else {
            throw PkpassError.invalidPassJSON("not a Samsung Wallet card")
        }

        let type = string(card["type"]) ?? "generic"
        let dataItems = card["data"] as? [[String: Any]] ?? []
        let attributes = (dataItems.first?["attributes"] as? [String: Any]) ?? [:]

        let dict = passKitDictionary(type: type, attributes: attributes)
        let pass = try WalletPassBuilder.pass(fromPassKitDictionary: dict)

        let raw = WalletPassBuilder.prettyJSON(data)
        let files = [PkpassFile(name: "card.json (Samsung Wallet)", size: data.count)]
        return PkpassDocument(
            pass: pass,
            rawPassJSON: raw,
            images: [:],
            files: files,
            isSigned: false,
            source: .samsungWallet
        )
    }

    private static func passKitDictionary(type: String, attributes: [String: Any]) -> [String: Any] {
        let title = string(attributes["title"]) ?? "Samsung Wallet Card"
        let provider = string(attributes["providerName"]) ?? title

        var primary: [[String: Any]] = []
        var secondary: [[String: Any]] = []
        var back: [[String: Any]] = []

        if let f = WalletPassBuilder.field(key: "title", label: nil, value: title) {
            primary.append(f)
        }

        // Validity window.
        if let start = epochString(attributes["startDate"]),
           let f = WalletPassBuilder.field(key: "start", label: "Valid From", value: start) {
            secondary.append(f)
        }
        if let end = epochString(attributes["endDate"]),
           let f = WalletPassBuilder.field(key: "end", label: "Valid Until", value: end) {
            secondary.append(f)
        }

        // Extended (custom) fields, sorted by `order`.
        if let extended = attributes["extendedFields"] as? [[String: Any]] {
            let sorted = extended.sorted { (($0["order"] as? Int) ?? 0) < (($1["order"] as? Int) ?? 0) }
            for (index, item) in sorted.enumerated() {
                let label = string(item["label"])
                let value = string(item["value"])
                if index < 3, let f = WalletPassBuilder.field(key: "e\(index)", label: label, value: value) {
                    secondary.append(f)
                }
                if let f = WalletPassBuilder.field(key: "eb\(index)", label: label ?? "Details", value: value) {
                    back.append(f)
                }
            }
        }

        if let notice = string(attributes["noticeDesc"]),
           let f = WalletPassBuilder.field(key: "notice", label: "Notice", value: notice) {
            back.append(f)
        }

        let barcode = attributes["barcode"] as? [String: Any]
        let format = string(barcode?["ptSubFormat"]) ?? string(barcode?["serialType"])
        let barcodes = WalletPassBuilder.barcodeArray(
            format: format,
            message: string(barcode?["value"]),
            altText: nil
        )

        var generic: [String: Any] = [:]
        if !primary.isEmpty { generic["primaryFields"] = primary }
        if !secondary.isEmpty { generic["secondaryFields"] = secondary }
        if !back.isEmpty { generic["backFields"] = back }

        var dict: [String: Any] = [
            "formatVersion": 1,
            "organizationName": provider,
            "description": "\(provider) — \(title)",
            "logoText": provider,
            "generic": generic
        ]
        if let bg = string(attributes["bgColor"]) { dict["backgroundColor"] = bg }
        if let fontColor = foregroundColor(attributes["fontColor"]) { dict["foregroundColor"] = fontColor }
        if !barcodes.isEmpty { dict["barcodes"] = barcodes }
        return dict
    }

    /// Samsung `fontColor` is a hex string OR the literal "dark"/"light".
    private static func foregroundColor(_ any: Any?) -> String? {
        guard let value = string(any)?.lowercased() else { return nil }
        switch value {
        case "dark": return "rgb(0, 0, 0)"
        case "light": return "rgb(255, 255, 255)"
        default: return value.hasPrefix("#") ? value : nil
        }
    }

    /// Formats an epoch-milliseconds value as a medium date.
    private static func epochString(_ any: Any?) -> String? {
        let millis: Double?
        if let d = any as? Double { millis = d }
        else if let i = any as? Int { millis = Double(i) }
        else if let s = any as? String, let d = Double(s) { millis = d }
        else { millis = nil }
        guard let millis else { return nil }
        let date = Date(timeIntervalSince1970: millis / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private static func string(_ any: Any?) -> String? {
        if let s = any as? String { return s.isEmpty ? nil : s }
        if let i = any as? Int { return String(i) }
        if let d = any as? Double { return String(d) }
        return nil
    }
}
