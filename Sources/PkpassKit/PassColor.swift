//
//  PassColor.swift
//  PkpassKit
//
//  Parses the colour strings found in pass.json. Apple passes use either
//  `rgb(r, g, b)` or a hex string. We keep a normalised representation so the
//  HTML and thumbnail renderers can reason about contrast.
//

import Foundation

/// An RGB colour parsed from a pass.json colour string.
public struct PassColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red.clamped()
        self.green = green.clamped()
        self.blue = blue.clamped()
    }

    /// Parses `rgb(...)` or `#rrggbb` / `#rgb` strings. Returns `nil` when the
    /// input is missing or unrecognised so callers can fall back to a default.
    public init?(_ raw: String?) {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        if trimmed.lowercased().hasPrefix("rgb") {
            let inside = trimmed.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }
            let parts = inside.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count >= 3,
                  let r = Double(parts[0]),
                  let g = Double(parts[1]),
                  let b = Double(parts[2]) else { return nil }
            self.init(red: r / 255, green: g / 255, blue: b / 255)
            return
        }

        if trimmed.hasPrefix("#") {
            var hex = String(trimmed.dropFirst())
            if hex.count == 3 {
                hex = hex.map { "\($0)\($0)" }.joined()
            }
            guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
            return
        }

        return nil
    }

    /// CSS `rgb()` representation for use in HTML.
    public var css: String {
        "rgb(\(Int((red * 255).rounded())), \(Int((green * 255).rounded())), \(Int((blue * 255).rounded())))"
    }

    /// CSS `rgba()` representation with the given opacity.
    public func css(alpha: Double) -> String {
        "rgba(\(Int((red * 255).rounded())), \(Int((green * 255).rounded())), \(Int((blue * 255).rounded())), \(alpha.clamped()))"
    }

    /// Relative luminance (WCAG) — used to decide light vs. dark treatment.
    public var luminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// `true` when the colour is light enough that dark text reads best on it.
    public var isLight: Bool { luminance > 0.5 }

    /// A readable foreground colour (black or white) for text drawn on top.
    public var readableForeground: PassColor {
        isLight ? PassColor(red: 0, green: 0, blue: 0) : PassColor(red: 1, green: 1, blue: 1)
    }

    public static let walletDefaultBackground = PassColor(red: 0.13, green: 0.13, blue: 0.15)
    public static let walletDefaultForeground = PassColor(red: 1, green: 1, blue: 1)
}

private extension Double {
    func clamped() -> Double { Swift.min(1, Swift.max(0, self)) }
}
