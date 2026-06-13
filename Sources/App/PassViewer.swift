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
    let webView = WKWebView()

    @Published var title = "No pass open"
    @Published var hasPass = false
    @Published var errorMessage: String?

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

    /// Exports the currently-rendered pass as a PDF.
    func exportPDF() {
        guard hasPass else { return }
        let config = WKPDFConfiguration()
        webView.createPDF(configuration: config) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let data):
                self.savePDF(data)
            case .failure(let error):
                self.errorMessage = "PDF export failed: \(error.localizedDescription)"
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
    @StateObject private var model = PassViewerModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.openFile()
                } label: {
                    Label("Open Pass…", systemImage: "folder")
                }
                Text(model.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.exportPDF()
                } label: {
                    Label("Export PDF…", systemImage: "square.and.arrow.down")
                }
                .disabled(!model.hasPass)
            }
            .padding(12)
            .background(.bar)

            Divider()

            ZStack {
                PassWebView(webView: model.webView)
                if !model.hasPass {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 44))
                            .foregroundStyle(.tertiary)
                        Text(model.errorMessage ?? "Open a pass to preview and export it as PDF")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 620)
    }
}
