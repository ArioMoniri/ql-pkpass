//
//  PreviewViewController.swift
//  PkpassPreviewExtension
//
//  A VIEW-BASED Quick Look preview (QLPreviewingController). Unlike a data-based
//  QLPreviewProvider, a view controller can host native controls — so the
//  Space-bar preview itself carries a working "Export as PDF" button, with no
//  need to open the app.
//

import Cocoa
import QuickLookUI
import WebKit
import UniformTypeIdentifiers
import OSLog
import PkpassKit

private let previewLog = Logger(subsystem: "com.ariomoniri.PkpassQuickLook.Preview", category: "preview")

final class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {
    private var webView: WKWebView!
    private var exportButton: NSButton!
    private var passTitle = "Pass"

    private let barHeight: CGFloat = 42

    override func loadView() {
        // Frame-based layout (with autoresizing) so the web view always has a
        // real size the instant we load HTML — Auto Layout hasn't run yet when
        // the Quick Look host calls preparePreviewOfFile.
        let initial = NSRect(x: 0, y: 0, width: 480, height: 760)
        let root = NSView(frame: initial)
        root.autoresizesSubviews = true

        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: initial.width, height: initial.height - barHeight))
        web.autoresizingMask = [.width, .height]
        root.addSubview(web)
        webView = web

        let bar = NSVisualEffectView(frame: NSRect(x: 0, y: initial.height - barHeight, width: initial.width, height: barHeight))
        bar.material = .headerView
        bar.blendingMode = .withinWindow
        bar.autoresizingMask = [.width, .minYMargin]
        root.addSubview(bar)

        let button = NSButton(title: "Export as PDF…", target: self, action: #selector(exportPDF))
        button.bezelStyle = .rounded
        button.keyEquivalent = "e"
        button.keyEquivalentModifierMask = [.command]
        button.sizeToFit()
        button.frame.origin = NSPoint(x: bar.bounds.width - button.frame.width - 12, y: (barHeight - button.frame.height) / 2)
        button.autoresizingMask = [.minXMargin]
        button.isHidden = true
        bar.addSubview(button)
        exportButton = button

        view = root
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        previewLog.info("preparePreviewOfFile: \(url.lastPathComponent, privacy: .public)")
        let html: String
        do {
            let document = try PassDocumentLoader.document(contentsOf: url)
            passTitle = document.pass.displayTitle
            html = PassHTMLRenderer(document: document).render()
            exportButton.isHidden = false
        } catch {
            previewLog.error("preview error: \(String(describing: error), privacy: .public)")
            html = Self.errorHTML(error, fileName: url.lastPathComponent)
        }
        load(html: html)
        handler(nil)
    }

    /// Loads the HTML via a temp file URL — WKWebView's WebContent process inside
    /// a sandboxed extension reliably renders a file URL where an inline
    /// `loadHTMLString(baseURL: nil)` can come up blank.
    private func load(html: String) {
        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("pkpass-preview-\(UUID().uuidString).html")
        do {
            try html.write(to: file, atomically: true, encoding: .utf8)
            webView.loadFileURL(file, allowingReadAccessTo: dir)
        } catch {
            previewLog.error("temp write failed: \(error.localizedDescription, privacy: .public)")
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    // MARK: - Export

    @objc private func exportPDF() {
        // Export the pass card itself only — not the detail panels below it.
        cardRect { [weak self] rect in
            guard let self else { return }
            let config = WKPDFConfiguration()
            if let rect { config.rect = rect }
            self.webView.createPDF(configuration: config) { result in
                switch result {
                case .success(let data): self.savePDF(data)
                case .failure(let error):
                    previewLog.error("createPDF failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Asks the web view for the `.pass` card's bounds (with a small margin) so
    /// the exported PDF contains the card only.
    private func cardRect(_ completion: @escaping (CGRect?) -> Void) {
        let js = "(function(){var e=document.querySelector('.pass');if(!e)return '';"
            + "var r=e.getBoundingClientRect();"
            + "return [r.left+window.scrollX,r.top+window.scrollY,r.width,r.height].join(',');})()"
        webView.evaluateJavaScript(js) { value, _ in
            guard let s = value as? String, !s.isEmpty else { completion(nil); return }
            let p = s.split(separator: ",").compactMap { Double($0) }
            guard p.count == 4, p[2] > 0, p[3] > 0 else { completion(nil); return }
            let m = 14.0
            completion(CGRect(x: max(0, p[0] - m), y: max(0, p[1] - m), width: p[2] + 2 * m, height: p[3] + 2 * m))
        }
    }

    private func savePDF(_ data: Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(passTitle).pdf"
        panel.message = "Save the pass as a PDF"
        let write: (URL) -> Void = { url in
            do { try data.write(to: url) } catch {
                previewLog.error("write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if let window = view.window {
            panel.beginSheetModal(for: window) { if $0 == .OK, let url = panel.url { write(url) } }
        } else {
            panel.begin { if $0 == .OK, let url = panel.url { write(url) } }
        }
    }

    private static func errorHTML(_ error: Error, fileName: String) -> String {
        let message = (error as? CustomStringConvertible)?.description ?? error.localizedDescription
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        return """
        <!DOCTYPE html><meta charset="utf-8">
        <body style="font-family:-apple-system,system-ui,sans-serif;margin:0;display:flex;align-items:center;justify-content:center;min-height:100vh;color:#888;text-align:center">
        <div style="max-width:340px;padding:28px"><div style="font-size:44px">🎫</div>
        <h3 style="margin:12px 0 6px;color:#aaa">Couldn't preview this pass</h3>
        <p style="font-size:13px"><code>\(esc(fileName))</code></p><p style="font-size:13px">\(esc(message))</p></div></body>
        """
    }
}
