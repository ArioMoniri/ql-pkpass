//
//  PassHTMLRenderer.swift
//  PkpassKit
//
//  Turns a parsed pass into a self-contained HTML document styled to look like
//  an Apple Wallet card. Everything (images, barcode) is inlined as base64 so
//  the Quick Look reply needs no external resources.
//

import Foundation

public struct PassHTMLRenderer {
    private let document: PkpassDocument
    private var pass: Pass { document.pass }

    public init(document: PkpassDocument) {
        self.document = document
    }

    /// Builds the full HTML preview.
    public func render() -> String {
        let bg = pass.backgroundPassColor
        let fg = pass.foregroundPassColor
        let label = pass.labelPassColor

        var style = "--bg: \(bg.css); --fg: \(fg.css); --label: \(label.css(alpha: 0.72)); --hair: \(fg.css(alpha: 0.16));"
        // Event tickets can carry a full-bleed background image behind the card.
        if pass.style == .eventTicket, let background = document.background {
            let tint = bg.css(alpha: 0.55)
            style += " background-image: linear-gradient(\(tint), \(tint)), url('\(dataURI(background))'); background-size: cover; background-position: center;"
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(css())
        </style>
        </head>
        <body>
        <main class="stage">
          <div class="pass style-\(pass.style.rawValue)" style="\(style)">
            \(voidedBanner())
            \(headerSection())
            \(stripSection())
            \(primarySection())
            \(auxiliarySection())
            \(barcodeSection())
          </div>
          \(backSection())
          \(metaSection())
          \(filesSection())
          \(rawSection())
          <footer class="credit">Rendered by <strong>pkpass Quick Look</strong> · no data leaves your Mac</footer>
        </main>
        </body>
        </html>
        """
    }

    // MARK: - Sections

    private func voidedBanner() -> String {
        guard pass.voided == true || pass.isExpired else { return "" }
        let text = pass.voided == true ? "VOIDED" : "EXPIRED"
        return #"<div class="voided">\#(text)</div>"#
    }

    private func headerSection() -> String {
        var left = ""
        if let logo = document.logo {
            left = #"<img class="logo" src="\#(dataURI(logo))" alt="logo">"#
        } else if let logoText = pass.logoText, !logoText.isEmpty {
            left = #"<div class="logo-text">\#(escape(logoText))</div>"#
        } else if let org = pass.organizationName {
            left = #"<div class="logo-text">\#(escape(org))</div>"#
        }

        let headerFields = fields(pass.primaryStructure?.headerFields, container: "header-fields", alignEnd: true)
        return #"<div class="header">\#(left)\#(headerFields)</div>"#
    }

    private func stripSection() -> String {
        guard pass.style != .eventTicket, let strip = document.strip else { return "" }
        return #"<div class="strip"><img src="\#(dataURI(strip))" alt="strip"></div>"#
    }

    private func primarySection() -> String {
        let primary = pass.primaryStructure?.primaryFields ?? []
        let thumb = (pass.style == .eventTicket) ? document.thumbnail : nil

        if pass.style == .boardingPass, primary.count >= 2 {
            let origin = primary[0]
            let destination = primary[1]
            let symbol = transitSymbol(pass.primaryStructure?.transitType)
            return """
            <div class="primary boarding">
              <div class="bp-field start">\(fieldLabel(origin))\(fieldValue(origin, big: true))</div>
              <div class="bp-transit">\(symbol)</div>
              <div class="bp-field end">\(fieldLabel(destination))\(fieldValue(destination, big: true))</div>
            </div>
            """
        }

        guard !primary.isEmpty || thumb != nil else { return "" }
        let rendered = primary.map { #"<div class="field">\#(fieldLabel($0))\#(fieldValue($0, big: true))</div>"# }.joined()
        let thumbHTML = thumb.map { #"<img class="thumb" src="\#(dataURI($0))" alt="thumbnail">"# } ?? ""
        return #"<div class="primary"><div class="primary-fields">\#(rendered)</div>\#(thumbHTML)</div>"#
    }

    private func auxiliarySection() -> String {
        let secondary = pass.primaryStructure?.secondaryFields ?? []
        let auxiliary = pass.primaryStructure?.auxiliaryFields ?? []
        let all = secondary + auxiliary
        guard !all.isEmpty else { return "" }
        let rendered = all.map { #"<div class="field">\#(fieldLabel($0))\#(fieldValue($0, big: false))</div>"# }.joined()
        return #"<div class="aux-row">\#(rendered)</div>"#
    }

    private func barcodeSection() -> String {
        guard let barcode = pass.primaryBarcode,
              let png = BarcodeRenderer.pngData(for: barcode) else { return "" }
        let alt = barcode.altText.map { #"<div class="barcode-alt">\#(escape($0))</div>"# } ?? ""
        // 1D / stacked codes are wide; matrix codes (QR, Aztec) are square.
        let isWide = barcode.format == "PKBarcodeFormatPDF417" || barcode.format == "PKBarcodeFormatCode128"
        let shape = isWide ? "wide" : "square"
        return """
        <div class="barcode">
          <div class="barcode-card \(shape)">
            <img src="\(dataURI(png))" alt="\(escape(barcode.formatName))">
          </div>
          \(alt)
          <div class="barcode-format">\(escape(barcode.formatName))</div>
        </div>
        """
    }

    private func backSection() -> String {
        let back = pass.primaryStructure?.backFields ?? []
        guard !back.isEmpty else { return "" }
        let rows = back.map { field in
            """
            <div class="back-row">
              <div class="back-label">\(escape(field.label ?? field.key))</div>
              <div class="back-value">\(linkify(field.displayValue))</div>
            </div>
            """
        }.joined()
        return """
        <details class="panel" open>
          <summary>📋 Back of pass</summary>
          <div class="panel-body">\(rows)</div>
        </details>
        """
    }

    private func metaSection() -> String {
        var rows: [String] = []
        func add(_ label: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            rows.append(#"<div class="meta-row"><span>\#(label)</span><span>\#(escape(value))</span></div>"#)
        }
        add("Source", document.source.displayName)
        add("Type", "\(pass.style.symbol)  \(pass.style.displayName)")
        add("Organization", pass.organizationName)
        add("Description", pass.description)
        add("Serial", pass.serialNumber)
        add("Pass type ID", pass.passTypeIdentifier)
        add("Team", pass.teamIdentifier)
        add("Expires", pass.expirationDate)
        if document.source == .applePkpass {
            add("Signed", document.isSigned ? "Yes — signature present" : "No signature")
        }
        guard !rows.isEmpty else { return "" }
        return """
        <details class="panel">
          <summary>ℹ️ Pass information</summary>
          <div class="panel-body meta">\(rows.joined())</div>
        </details>
        """
    }

    private func filesSection() -> String {
        guard !document.files.isEmpty else { return "" }
        let rows = document.files.map { file in
            """
            <div class="meta-row"><span>\(escape(file.name))</span><span>\(escape(file.formattedSize))</span></div>
            """
        }.joined()
        let total = document.files.reduce(0) { $0 + $1.size }
        let totalStr = ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
        return """
        <details class="panel">
          <summary>🗂️ Files in archive (\(document.files.count))</summary>
          <div class="panel-body meta">\(rows)
            <div class="meta-row total"><span>Total</span><span>\(escape(totalStr))</span></div>
          </div>
        </details>
        """
    }

    private func rawSection() -> String {
        """
        <details class="panel">
          <summary>🧾 \(escape(document.source.rawLabel))</summary>
          <pre class="raw">\(escape(document.rawPassJSON))</pre>
        </details>
        """
    }

    // MARK: - Field helpers

    private func fields(_ fields: [PassField]?, container: String, alignEnd: Bool) -> String {
        guard let fields, !fields.isEmpty else { return "" }
        let rendered = fields.map { #"<div class="field\#(alignEnd ? " end" : "")">\#(fieldLabel($0))\#(fieldValue($0, big: false))</div>"# }.joined()
        return #"<div class="\#(container)">\#(rendered)</div>"#
    }

    private func fieldLabel(_ field: PassField) -> String {
        guard let label = field.label, !label.isEmpty else { return "" }
        return #"<div class="f-label">\#(escape(label))</div>"#
    }

    private func fieldValue(_ field: PassField, big: Bool) -> String {
        #"<div class="f-value\#(big ? " big" : "")">\#(escape(field.displayValue))</div>"#
    }

    private func transitSymbol(_ transitType: String?) -> String {
        switch transitType {
        case "PKTransitTypeAir": return "✈️"
        case "PKTransitTypeTrain": return "🚆"
        case "PKTransitTypeBus": return "🚌"
        case "PKTransitTypeBoat": return "⛴️"
        case "PKTransitTypeGeneric": return "➔"
        default: return "➔"
        }
    }

    // MARK: - Encoding helpers

    private func dataURI(_ data: Data) -> String {
        // Pick the MIME type from the payload's magic bytes rather than assuming
        // PNG, so an oddly-named image still renders. PNG is the spec default.
        let prefix = [UInt8](data.prefix(4))
        let mime: String
        if prefix.count >= 3, prefix[0] == 0xFF, prefix[1] == 0xD8, prefix[2] == 0xFF {
            mime = "image/jpeg"
        } else if prefix.count >= 3, prefix[0] == 0x47, prefix[1] == 0x49, prefix[2] == 0x46 {
            mime = "image/gif"
        } else if prefix.count >= 4, prefix[0] == 0x52, prefix[1] == 0x49, prefix[2] == 0x46, prefix[3] == 0x46 {
            mime = "image/webp"
        } else {
            mime = "image/png"
        }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    private func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Escapes text, then turns bare URLs into links (back fields often contain them).
    private func linkify(_ string: String) -> String {
        let escaped = escape(string)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return escaped
        }
        let range = NSRange(escaped.startIndex..., in: escaped)
        var result = escaped
        let matches = detector.matches(in: escaped, range: range).reversed()
        for match in matches {
            guard let url = match.url, let swiftRange = Range(match.range, in: escaped) else { continue }
            // Only linkify safe schemes, and escape the href so it stays a
            // well-formed, inert attribute regardless of the URL's contents.
            guard let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme),
                  let resultRange = Range(match.range, in: result) else { continue }
            let text = String(escaped[swiftRange])
            result.replaceSubrange(
                resultRange,
                with: #"<a href="\#(escape(url.absoluteString))">\#(text)</a>"#
            )
        }
        return result
    }

    // MARK: - Stylesheet

    private func css() -> String {
        """
        * { box-sizing: border-box; margin: 0; padding: 0; }
        :root { color-scheme: light dark; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
          background: #ececf1;
          -webkit-font-smoothing: antialiased;
        }
        .stage { max-width: 460px; margin: 0 auto; padding: 22px 16px 32px; }
        .pass {
          background: var(--bg);
          color: var(--fg);
          border-radius: 18px;
          padding: 18px 18px 22px;
          /* An outer hairline ring + soft shadow frames the card on ANY backdrop,
             so even a near-black pass stays clearly delineated. */
          box-shadow: 0 18px 40px rgba(0,0,0,0.35), 0 0 0 1px rgba(128,128,128,0.40);
          overflow: hidden;
          position: relative;
        }
        .voided {
          text-align: center; letter-spacing: 3px; font-weight: 800; font-size: 12px;
          padding: 6px; margin: -4px -4px 12px; border-radius: 8px;
          background: rgba(255,59,48,0.18); color: #ff6961; border: 1px solid rgba(255,59,48,0.4);
        }
        .header { display: flex; align-items: center; justify-content: space-between; gap: 12px; min-height: 36px; }
        .logo { max-height: 38px; max-width: 70%; object-fit: contain; }
        .logo-text { font-size: 17px; font-weight: 700; }
        .header-fields { display: flex; gap: 16px; }
        .f-label { font-size: 10px; font-weight: 600; letter-spacing: 0.6px; text-transform: uppercase; color: var(--label); margin-bottom: 2px; }
        .f-value { font-size: 15px; font-weight: 600; overflow-wrap: anywhere; }
        .f-value.big { font-size: clamp(18px, 7vw, 26px); font-weight: 700; letter-spacing: -0.2px; overflow-wrap: anywhere; }
        .field.end { text-align: right; }
        .header-fields .f-value { font-size: 14px; }
        .strip { margin: 14px -18px 0; }
        .strip img { width: 100%; display: block; }
        .primary { margin-top: 16px; display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; }
        .primary-fields { display: flex; flex-wrap: wrap; gap: 18px; }
        .thumb { max-height: 76px; max-width: 76px; border-radius: 8px; object-fit: cover; }
        .primary.boarding { align-items: center; }
        .bp-field { flex: 1; min-width: 0; overflow-wrap: anywhere; }
        .bp-field.end { text-align: right; }
        .bp-transit { flex: 0 0 auto; font-size: 22px; opacity: 0.85; padding: 0 6px; }
        .aux-row { margin-top: 16px; display: flex; flex-wrap: wrap; gap: 16px 22px; }
        .aux-row .field { min-width: 60px; }
        .barcode { margin-top: 20px; display: flex; flex-direction: column; align-items: center; }
        .barcode-card { background: #fff; padding: 14px; border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.2); max-width: 100%; }
        /* Keep each symbology's true aspect ratio: matrix codes stay square,
           1D / stacked codes stay wide. Rendered at scan-quality resolution. */
        .barcode-card.square img { width: 210px; height: 210px; display: block; image-rendering: pixelated; }
        .barcode-card.wide img { width: 100%; max-width: 360px; height: auto; display: block; image-rendering: pixelated; }
        .barcode-alt { margin-top: 8px; font-size: 12px; letter-spacing: 1px; color: var(--label); font-variant-numeric: tabular-nums; }
        .barcode-format { margin-top: 4px; font-size: 10px; text-transform: uppercase; letter-spacing: 1.2px; opacity: 0.4; }
        .panel {
          margin-top: 14px; background: rgba(127,127,127,0.10); border: 0.5px solid rgba(127,127,127,0.18);
          border-radius: 12px; overflow: hidden; color: inherit;
        }
        body { color: #1c1c1e; }
        @media (prefers-color-scheme: dark) { body { color: #f2f2f7; background: #161618; } }
        .panel summary {
          cursor: pointer; padding: 12px 14px; font-size: 13px; font-weight: 600; list-style: none; user-select: none;
        }
        .panel summary::-webkit-details-marker { display: none; }
        .panel summary::after { content: "⌄"; float: right; opacity: 0.5; transition: transform 0.2s; }
        .panel[open] summary::after { transform: rotate(180deg); }
        .panel-body { padding: 0 14px 14px; font-size: 13px; line-height: 1.5; }
        .back-row { padding: 8px 0; border-top: 0.5px solid rgba(127,127,127,0.18); }
        .back-row:first-child { border-top: none; }
        .back-label { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.4px; opacity: 0.6; margin-bottom: 2px; }
        .back-value { word-break: break-word; }
        .back-value a { color: #0a84ff; }
        .meta { display: grid; gap: 6px; }
        .meta-row { display: flex; justify-content: space-between; gap: 16px; }
        .meta-row span:first-child { opacity: 0.55; }
        .meta-row span:last-child { text-align: right; word-break: break-word; font-variant-numeric: tabular-nums; }
        .raw {
          font-family: "SF Mono", ui-monospace, Menlo, monospace; font-size: 11px; line-height: 1.45;
          white-space: pre-wrap; word-break: break-word; opacity: 0.85;
        }
        .credit { text-align: center; margin-top: 18px; font-size: 11px; opacity: 0.45; }
        """
    }
}
