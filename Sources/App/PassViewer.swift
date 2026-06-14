//
//  PassViewer.swift
//  pkpass Quick Look
//
//  A small in-app viewer that opens any supported pass (Apple .pkpass, Google
//  Wallet JSON, Samsung Wallet JSON), renders the same card the Quick Look
//  preview shows, and exports it as a PDF via WKWebView.
//

import SwiftUI
import WebKit
import UniformTypeIdentifiers
import PkpassKit

@MainActor
final class PassViewerModel: ObservableObject {
    /// Shared so the document-open handler (AppDelegate) and the UI use one viewer.
    static let shared = PassViewerModel()

    let webView = WKWebView()

    @Published var title = "No pass open"
    @Published var hasPass = false
    @Published var errorMessage: String?

    /// Clears the current pass (returns the window to the home screen).
    func reset() {
        hasPass = false
        title = "No pass open"
        errorMessage = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    /// Prompts for a file and renders it.
    func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType("com.apple.pkpass-data") ?? .data,
            .json, .data
        ]
        panel.message = "Choose a .pkpass, Google Wallet, or Samsung Wallet pass"
        if panel.runModal() == .OK, let url = panel.url {
            load(url: url)
        }
    }

    func load(url: URL) {
        do {
            let document = try PassDocumentLoader.document(contentsOf: url)
            let html = PassHTMLRenderer(document: document).render()
            webView.loadHTMLString(html, baseURL: nil)
            title = document.pass.displayTitle
            hasPass = true
            errorMessage = nil
        } catch {
            errorMessage = (error as? CustomStringConvertible)?.description ?? error.localizedDescription
            hasPass = false
        }
    }

    /// Exports the pass card itself only (not the detail panels) as a PDF.
    func exportPDF() {
        guard hasPass else { return }
        let js = "(function(){var e=document.querySelector('.pass');if(!e)return '';"
            + "var r=e.getBoundingClientRect();"
            + "return [r.left+window.scrollX,r.top+window.scrollY,r.width,r.height].join(',');})()"
        webView.evaluateJavaScript(js) { [weak self] value, _ in
            guard let self else { return }
            let config = WKPDFConfiguration()
            if let s = value as? String, !s.isEmpty {
                let p = s.split(separator: ",").compactMap { Double($0) }
                if p.count == 4, p[2] > 0, p[3] > 0 {
                    let m = 14.0
                    config.rect = CGRect(x: max(0, p[0] - m), y: max(0, p[1] - m), width: p[2] + 2 * m, height: p[3] + 2 * m)
                }
            }
            self.webView.createPDF(configuration: config) { result in
                switch result {
                case .success(let data):
                    self.savePDF(data)
                case .failure(let error):
                    self.errorMessage = "PDF export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func savePDF(_ data: Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(title).pdf"
        panel.message = "Save the pass as a PDF"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}

/// Bridges the model's WKWebView into SwiftUI.
struct PassWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct PassViewerView: View {
    @ObservedObject var model: PassViewerModel
    var onDone: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    model.openFile()
                } label: {
                    Label("Open Another…", systemImage: "folder")
                }
                .keyboardShortcut("o")

                Spacer(minLength: 8)

                if model.hasPass {
                    Text(model.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                // Always visible; prominent once a pass is loaded.
                Button {
                    model.exportPDF()
                } label: {
                    Label("Export as PDF…", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("e")
                .buttonStyle(.borderedProminent)
                .disabled(!model.hasPass)

                Button("Done", action: onDone)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            .background(.bar)

            Divider()

            ZStack {
                PassWebView(webView: model.webView)
                if !model.hasPass {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 44))
                            .foregroundStyle(.tertiary)
                        Text(model.errorMessage ?? "Open a pass to preview it, then “Export as PDF…”.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Button {
                            model.openFile()
                        } label: {
                            Label("Open a Pass…", systemImage: "folder")
                        }
                        .controlSize(.large)
                    }
                }
            }
        }
        .frame(minWidth: 540, minHeight: 640)
    }
}
