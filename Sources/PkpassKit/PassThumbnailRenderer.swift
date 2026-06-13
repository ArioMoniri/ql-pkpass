//
//  PassThumbnailRenderer.swift
//  PkpassKit
//
//  Draws the Finder thumbnail / preview-pane image. At small icon sizes it draws
//  a compact card (logo or monogram); at preview-pane sizes it draws a real
//  mini-pass — logo/organization, a key field, and the barcode — so you can read
//  the pass content in Finder without pressing Space.
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
        let radius = cardRect.width * 0.12

        let card = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)
        nsColor(bg).setFill()
        card.fill()

        // Subtle top sheen.
        NSGraphicsContext.saveGraphicsState()
        card.addClip()
        if let gradient = NSGradient(colors: [
            NSColor(white: fg.isLight ? 0 : 1, alpha: 0.10),
            NSColor(white: 0, alpha: 0.0)
        ]) {
            gradient.draw(in: cardRect, angle: -90)
        }
        NSGraphicsContext.restoreGraphicsState()

        // Hairline ring so the card reads on any backdrop.
        nsColor(fg, alpha: 0.18).setStroke()
        let ring = NSBezierPath(roundedRect: cardRect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        ring.lineWidth = 1
        ring.stroke()

        // Below ~150px there isn't room for fields — draw the compact card.
        if cardRect.width < 150 {
            drawCompact(in: cardRect, color: fg)
        } else {
            drawRich(in: cardRect, fg: fg)
        }
    }

    // MARK: - Rich mini-pass

    private func drawRich(in cardRect: CGRect, fg: PassColor) {
        let pad = cardRect.width * 0.09
        let content = cardRect.insetBy(dx: pad, dy: pad)
        let width = content.width
        let height = content.height
        var top = content.maxY

        // Header — logo image or logo text.
        let headerHeight = height * 0.16
        if let data = document.logo, let image = NSImage(data: data), image.size.width > 0 {
            let scale = min((width * 0.72) / image.size.width, headerHeight / image.size.height)
            let drawSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: NSRect(x: content.minX, y: top - drawSize.height, width: drawSize.width, height: drawSize.height),
                       from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            let text = pass.logoText ?? pass.organizationName ?? pass.displayTitle
            drawText(text, size: height * 0.10, weight: .heavy, color: fg, alpha: 1,
                     band: NSRect(x: content.minX, y: top - headerHeight, width: width, height: headerHeight))
        }
        top -= headerHeight + height * 0.06

        // Primary field (origin → destination for boarding passes).
        if let (label, value) = primaryDisplay() {
            if let label, !label.isEmpty {
                let labelHeight = height * 0.06
                drawText(label.uppercased(), size: height * 0.048, weight: .semibold, color: fg, alpha: 0.6,
                         band: NSRect(x: content.minX, y: top - labelHeight, width: width, height: labelHeight))
                top -= labelHeight + height * 0.012
            }
            let valueHeight = height * 0.16
            drawText(value, size: height * 0.135, weight: .bold, color: fg, alpha: 1,
                     band: NSRect(x: content.minX, y: top - valueHeight, width: width, height: valueHeight))
            top -= valueHeight + height * 0.04
        }

        // Barcode at the bottom, in a white rounded panel.
        if let barcode = pass.primaryBarcode,
           let png = BarcodeRenderer.pngData(for: barcode, targetSize: 320),
           let image = NSImage(data: png) {
            let isWide = barcode.format == "PKBarcodeFormatPDF417" || barcode.format == "PKBarcodeFormatCode128"
            var boxWidth = isWide ? width * 0.92 : min(width * 0.5, height * 0.44)
            var boxHeight = isWide ? boxWidth * 0.42 : boxWidth
            let available = top - content.minY
            if boxHeight > available {
                let shrink = max(0, available / boxHeight)
                boxWidth *= shrink; boxHeight *= shrink
            }
            if boxWidth > 8, boxHeight > 8 {
                let box = NSRect(x: content.midX - boxWidth / 2, y: content.minY, width: boxWidth, height: boxHeight)
                NSColor.white.setFill()
                NSBezierPath(roundedRect: box, xRadius: boxWidth * 0.08, yRadius: boxWidth * 0.08).fill()
                let innerPad = boxWidth * 0.08
                image.draw(in: box.insetBy(dx: innerPad, dy: innerPad), from: .zero, operation: .sourceOver, fraction: 1)
            }
        }
    }

    private func primaryDisplay() -> (label: String?, value: String)? {
        let structure = pass.primaryStructure
        if pass.style == .boardingPass, let primaries = structure?.primaryFields, primaries.count >= 2 {
            return (nil, "\(primaries[0].displayValue) → \(primaries[1].displayValue)")
        }
        if let field = structure?.primaryFields?.first
            ?? structure?.secondaryFields?.first
            ?? structure?.headerFields?.first {
            return (field.label, field.displayValue)
        }
        return nil
    }

    // MARK: - Compact card (small sizes)

    private func drawCompact(in cardRect: CGRect, color fg: PassColor) {
        if let data = document.logo ?? document.icon ?? document.thumbnail, let image = NSImage(data: data) {
            let maxWidth = cardRect.width * 0.62
            let maxHeight = cardRect.height * 0.42
            let size = image.size
            guard size.width > 0, size.height > 0 else { return }
            let scale = min(maxWidth / size.width, maxHeight / size.height)
            let drawSize = NSSize(width: size.width * scale, height: size.height * scale)
            image.draw(in: NSRect(x: cardRect.midX - drawSize.width / 2, y: cardRect.midY - drawSize.height / 2,
                                  width: drawSize.width, height: drawSize.height),
                       from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            let monogram = String(pass.displayTitle.prefix(2)).uppercased()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: cardRect.height * 0.28, weight: .bold),
                .foregroundColor: nsColor(fg, alpha: 0.92)
            ]
            let string = NSAttributedString(string: monogram, attributes: attrs)
            let size = string.size()
            string.draw(at: NSPoint(x: cardRect.midX - size.width / 2, y: cardRect.midY - size.height / 2))
        }
    }

    // MARK: - Helpers

    private func drawText(_ text: String, size: CGFloat, weight: NSFont.Weight, color: PassColor, alpha: CGFloat, band: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: nsColor(color, alpha: alpha),
            .paragraphStyle: paragraph
        ]
        let string = NSAttributedString(string: text, attributes: attrs)
        let lineHeight = string.size().height
        let drawRect = NSRect(x: band.minX, y: band.midY - lineHeight / 2, width: band.width, height: lineHeight)
        string.draw(in: drawRect)
    }

    private func nsColor(_ color: PassColor, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: alpha)
    }
}
