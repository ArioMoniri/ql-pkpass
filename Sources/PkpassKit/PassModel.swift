//
//  PassModel.swift
//  PkpassKit
//
//  Codable model for the parts of pass.json we display. Field values in
//  pass.json can be strings, numbers, or booleans, so the field decoder is
//  intentionally lenient and normalises everything to a display string.
//

import Foundation

/// The five pass styles defined by PassKit.
public enum PassStyle: String, Sendable, CaseIterable {
    case boardingPass
    case coupon
    case eventTicket
    case generic
    case storeCard

    public var displayName: String {
        switch self {
        case .boardingPass: return "Boarding Pass"
        case .coupon: return "Coupon"
        case .eventTicket: return "Event Ticket"
        case .generic: return "Generic"
        case .storeCard: return "Store Card"
        }
    }

    public var symbol: String {
        switch self {
        case .boardingPass: return "✈️"
        case .coupon: return "🎟️"
        case .eventTicket: return "🎫"
        case .generic: return "🪪"
        case .storeCard: return "💳"
        }
    }
}

/// A single field inside a pass structure.
public struct PassField: Codable, Sendable {
    public let key: String
    public let label: String?
    public let value: String
    public let changeMessage: String?
    public let textAlignment: String?
    public let dateStyle: String?
    public let timeStyle: String?
    public let currencyCode: String?
    public let attributedValue: String?

    enum CodingKeys: String, CodingKey {
        case key, label, value, changeMessage, textAlignment
        case dateStyle, timeStyle, currencyCode, attributedValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? container.decode(String.self, forKey: .key)) ?? ""
        label = try? container.decodeIfPresent(String.self, forKey: .label)
        changeMessage = try? container.decodeIfPresent(String.self, forKey: .changeMessage)
        textAlignment = try? container.decodeIfPresent(String.self, forKey: .textAlignment)
        dateStyle = try? container.decodeIfPresent(String.self, forKey: .dateStyle)
        timeStyle = try? container.decodeIfPresent(String.self, forKey: .timeStyle)
        currencyCode = try? container.decodeIfPresent(String.self, forKey: .currencyCode)
        attributedValue = PassField.flexibleString(container, .attributedValue)
        value = PassField.flexibleString(container, .value) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encode(value, forKey: .value)
    }

    /// The best human-readable string for display, with light date formatting.
    /// Prefer the plain `value`: Apple guarantees it is present alongside
    /// `attributedValue`, and using it avoids surfacing the raw `<a>` markup that
    /// `attributedValue` may contain (which we deliberately HTML-escape).
    public var displayValue: String {
        let base = value.isEmpty ? (attributedValue ?? "") : value
        return PassField.formatIfDate(base, dateStyle: dateStyle, timeStyle: timeStyle)
    }

    // MARK: - Helpers

    static func flexibleString(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let s = try? container.decode(String.self, forKey: key) { return s }
        if let i = try? container.decode(Int.self, forKey: key) { return String(i) }
        if let d = try? container.decode(Double.self, forKey: key) {
            return d == d.rounded() ? String(Int(d)) : String(d)
        }
        if let b = try? container.decode(Bool.self, forKey: key) { return b ? "Yes" : "No" }
        return nil
    }

    static func formatIfDate(_ raw: String, dateStyle: String?, timeStyle: String?) -> String {
        let wantsDate = (dateStyle != nil && dateStyle != "PKDateStyleNone")
            || (timeStyle != nil && timeStyle != "PKDateStyleNone")
        guard wantsDate else { return raw }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var date = iso.date(from: raw)
        if date == nil {
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = iso.date(from: raw)
        }
        guard let parsed = date else { return raw }

        let formatter = DateFormatter()
        formatter.dateStyle = mapStyle(dateStyle)
        formatter.timeStyle = mapStyle(timeStyle)
        return formatter.string(from: parsed)
    }

    private static func mapStyle(_ style: String?) -> DateFormatter.Style {
        switch style {
        case "PKDateStyleShort": return .short
        case "PKDateStyleMedium": return .medium
        case "PKDateStyleLong": return .long
        case "PKDateStyleFull": return .full
        default: return .none
        }
    }
}

/// A barcode declaration.
public struct PassBarcode: Codable, Sendable {
    public let format: String?
    public let message: String?
    public let altText: String?
    public let messageEncoding: String?

    /// A short, human label for the barcode symbology.
    public var formatName: String {
        switch format {
        case "PKBarcodeFormatQR": return "QR Code"
        case "PKBarcodeFormatPDF417": return "PDF417"
        case "PKBarcodeFormatAztec": return "Aztec"
        case "PKBarcodeFormatCode128": return "Code 128"
        default: return format ?? "Barcode"
        }
    }
}

/// A group of fields for a particular pass style.
public struct PassStructure: Codable, Sendable {
    public let headerFields: [PassField]?
    public let primaryFields: [PassField]?
    public let secondaryFields: [PassField]?
    public let auxiliaryFields: [PassField]?
    public let backFields: [PassField]?
    public let transitType: String?
}

/// The top-level pass document.
public struct Pass: Codable, Sendable {
    public let formatVersion: Int?
    public let description: String?
    public let organizationName: String?
    public let passTypeIdentifier: String?
    public let serialNumber: String?
    public let teamIdentifier: String?
    public let logoText: String?
    public let foregroundColor: String?
    public let backgroundColor: String?
    public let labelColor: String?
    public let relevantDate: String?
    public let expirationDate: String?
    public let voided: Bool?
    public let barcode: PassBarcode?
    public let barcodes: [PassBarcode]?

    public let boardingPass: PassStructure?
    public let coupon: PassStructure?
    public let eventTicket: PassStructure?
    public let generic: PassStructure?
    public let storeCard: PassStructure?

    /// The detected style, defaulting to `.generic`.
    public var style: PassStyle {
        if boardingPass != nil { return .boardingPass }
        if coupon != nil { return .coupon }
        if eventTicket != nil { return .eventTicket }
        if storeCard != nil { return .storeCard }
        return .generic
    }

    /// The field structure for the active style.
    public var primaryStructure: PassStructure? {
        switch style {
        case .boardingPass: return boardingPass
        case .coupon: return coupon
        case .eventTicket: return eventTicket
        case .storeCard: return storeCard
        case .generic: return generic
        }
    }

    /// The barcode to display, preferring the modern `barcodes` array.
    public var primaryBarcode: PassBarcode? {
        barcodes?.first(where: { $0.message?.isEmpty == false }) ?? barcode
    }

    public var backgroundPassColor: PassColor {
        PassColor(backgroundColor) ?? .walletDefaultBackground
    }

    public var foregroundPassColor: PassColor {
        PassColor(foregroundColor) ?? backgroundPassColor.readableForeground
    }

    public var labelPassColor: PassColor {
        PassColor(labelColor) ?? foregroundPassColor
    }

    /// A short title for the Quick Look window / thumbnail.
    public var displayTitle: String {
        if let logoText, !logoText.isEmpty { return logoText }
        if let organizationName, !organizationName.isEmpty { return organizationName }
        if let description, !description.isEmpty { return description }
        return "Pass"
    }

    public var isExpired: Bool {
        guard let expirationDate else { return false }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        guard let date = iso.date(from: expirationDate) else { return false }
        return date < Date()
    }
}
