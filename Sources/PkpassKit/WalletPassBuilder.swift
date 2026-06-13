//
//  WalletPassBuilder.swift
//  PkpassKit
//
//  Shared helpers for the Google / Samsung parsers. Rather than build the `Pass`
//  model by hand, each parser translates its source JSON into a PassKit-shaped
//  dictionary and decodes it through the existing `Pass` decoder — so the whole
//  rendering pipeline is reused unchanged.
//

import Foundation

enum WalletPassBuilder {

    /// Decodes a PassKit-shaped dictionary into a `Pass`.
    static func pass(fromPassKitDictionary dict: [String: Any]) throws -> Pass {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [])
        return try JSONDecoder().decode(Pass.self, from: data)
    }

    /// Pretty-prints arbitrary JSON bytes for the "raw" disclosure.
    static func prettyJSON(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8) else {
            return String(decoding: data, as: UTF8.self)
        }
        return string
    }

    /// Normalises a Google/Samsung barcode symbology to a PassKit format string
    /// so `BarcodeRenderer` can render it.
    static func passKitBarcodeFormat(_ raw: String?) -> String {
        switch (raw ?? "").uppercased().replacingOccurrences(of: "_", with: "") {
        case "QRCODE", "QR": return "PKBarcodeFormatQR"
        case "PDF417": return "PKBarcodeFormatPDF417"
        case "AZTEC": return "PKBarcodeFormatAztec"
        case "CODE128": return "PKBarcodeFormatCode128"
        default: return "PKBarcodeFormatQR"
        }
    }

    /// Builds a `barcodes` array for the PassKit dictionary.
    static func barcodeArray(format: String?, message: String?, altText: String?) -> [[String: Any]] {
        guard let message, !message.isEmpty else { return [] }
        var entry: [String: Any] = [
            "format": passKitBarcodeFormat(format),
            "message": message,
            "messageEncoding": "iso-8859-1"
        ]
        if let altText, !altText.isEmpty { entry["altText"] = altText }
        return [entry]
    }

    /// Makes a PassKit field dictionary, skipping empties.
    static func field(key: String, label: String?, value: String?) -> [String: Any]? {
        guard let value, !value.isEmpty else { return nil }
        var dict: [String: Any] = ["key": key, "value": value]
        if let label, !label.isEmpty { dict["label"] = label }
        return dict
    }
}
