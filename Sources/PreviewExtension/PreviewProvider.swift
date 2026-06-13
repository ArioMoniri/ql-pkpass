//
//  PreviewProvider.swift
//  PkpassPreviewExtension
//
//  The Quick Look preview extension. It parses the selected `.pkpass` file and
//  returns an HTML reply that Quick Look renders in its preview panel.
//

import QuickLookUI
import UniformTypeIdentifiers
import OSLog
import PkpassKit

private let previewLog = Logger(subsystem: "com.ariomoniri.PkpassQuickLook.Preview", category: "preview")

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        previewLog.info("providePreview start: \(url.lastPathComponent, privacy: .public)")

        do {
            let document = try PkpassDocument(contentsOf: url)
            let html = PassHTMLRenderer(document: document).render()
            let data = Data(html.utf8)
            let title = document.pass.displayTitle
            previewLog.info("providePreview ok: \(data.count, privacy: .public) bytes, style \(document.pass.style.rawValue, privacy: .public)")

            let reply = QLPreviewReply(
                dataOfContentType: .html,
                contentSize: CGSize(width: 460, height: 640)
            ) { reply in
                reply.title = title
                reply.stringEncoding = .utf8
                return data
            }
            return reply
        } catch {
            previewLog.error("providePreview error: \(String(describing: error), privacy: .public)")
            // Render a friendly error card instead of a blank preview.
            let html = ErrorPreview.html(for: error, fileName: url.lastPathComponent)
            let data = Data(html.utf8)
            return QLPreviewReply(
                dataOfContentType: .html,
                contentSize: CGSize(width: 460, height: 320)
            ) { reply in
                reply.title = url.lastPathComponent
                reply.stringEncoding = .utf8
                return data
            }
        }
    }
}

private enum ErrorPreview {
    static func html(for error: Error, fileName: String) -> String {
        let message = (error as? CustomStringConvertible)?.description ?? error.localizedDescription
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        :root { color-scheme: light dark; }
        body { font-family: -apple-system, system-ui, sans-serif; margin: 0;
               display: flex; align-items: center; justify-content: center;
               min-height: 100vh; background: #f2f2f7; color: #1c1c1e; }
        @media (prefers-color-scheme: dark) { body { background: #1c1c1e; color: #f2f2f7; } }
        .box { max-width: 360px; text-align: center; padding: 28px; }
        .emoji { font-size: 46px; }
        h1 { font-size: 17px; margin: 14px 0 6px; }
        p { font-size: 13px; opacity: 0.7; line-height: 1.5; word-break: break-word; }
        code { font-family: ui-monospace, Menlo, monospace; font-size: 12px; }
        </style></head><body><div class="box">
        <div class="emoji">🎫</div>
        <h1>Couldn't preview this pass</h1>
        <p><code>\(escape(fileName))</code></p>
        <p>\(escape(message))</p>
        </div></body></html>
        """
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
