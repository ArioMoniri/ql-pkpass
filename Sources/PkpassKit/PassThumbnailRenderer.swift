//
//  PassThumbnailRenderer.swift
//  PkpassKit
//
//  Draws a compact "card" thumbnail for Finder / Quick Look icons using the
//  pass's own colours and logo. Drawing happens into the current AppKit
//  graphics context supplied by the thumbnail extension.
//

import Foundation
import AppKit

public struct PassThumbnailRenderer {
    private let document: PkpassDocument
    private var pass: Pass { document.pass }

    public init(document: PkpassDocument) {
        self.document = document
    }

    /// Draws the thumbnail to fill `rect` in the current graphics context.
    public func draw(in rect: CGRect) {
        let bg = pass.backgroundPassColor
        let fg = pass.foregroundPassColor

        let inset = rect.width * 0.06
        let cardRect = rect.insetBy(dx: inset, dy: inset)
        let radius = cardRect.width * 0.14

        let card = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)
        NSColor(srgbRed: bg.red, green: bg.green, blue: bg.blue, alpha: 1).setFill()
        card.fill()

        // A subtle top sheen so flat colours don't look dead.
        if let gradient = NSGradient(
            colors: [
                NSColor(white: fg.isLight ? 0 : 1, alpha: 0.10),
                NSColor(white: 0, alpha: 0.0)
            ]
        ) {
            card.addClip()
            gradient.draw(in: cardRect, angle: -90)
            NSGraphicsContext.current?.cgContext.resetClip()
        }

        if let imageData = document.logo ?? document.icon ?? document.thumbnail,
           let image = NSImage(data: imageData) {
            drawImage(image, in: cardRect)
        } else {
            drawMonogram(in: cardRect, color: fg)
        }
    }

    private func drawImage(_ image: NSImage, in cardRect: CGRect) {
        let maxWidth = cardRect.width * 0.62
        let maxHeight = cardRect.height * 0.42
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }

        let scale = min(maxWidth / size.width, maxHeight / size.height)
        let drawSize = NSSize(width: size.width * scale, height: size.height * scale)
        let origin = NSPoint(
            x: cardRect.midX - drawSize.width / 2,
            y: cardRect.midY - drawSize.height / 2
        )
        image.draw(
            in: NSRect(origin: origin, size: drawSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
    }

    private func drawMonogram(in cardRect: CGRect, color: PassColor) {
        let title = pass.displayTitle
        let monogram = String(title.prefix(2)).uppercased()
        let fontSize = cardRect.height * 0.28
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 0.92)
        ]
        let string = NSAttributedString(string: monogram, attributes: attributes)
        let textSize = string.size()
        let point = NSPoint(
            x: cardRect.midX - textSize.width / 2,
            y: cardRect.midY - textSize.height / 2
        )
        string.draw(at: point)
    }
}
