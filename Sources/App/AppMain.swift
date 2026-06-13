//
//  AppMain.swift
//  pkpass Quick Look
//
//  A small host app whose real job is to ship the two Quick Look extensions.
//  The window simply explains how to use the plugin and links to the relevant
//  System Settings pane.
//

import SwiftUI

@main
struct PkpassQuickLookApp: App {
    var body: some Scene {
        WindowGroup("pkpass Quick Look") {
            ContentView()
                .frame(minWidth: 480, idealWidth: 540, minHeight: 560, idealHeight: 620)
        }
    }
}

struct ContentView: View {
    private let steps: [(symbol: String, title: String, detail: String)] = [
        ("magnifyingglass", "Select a pass", "Click any .pkpass file in Finder."),
        ("space", "Press Space", "Quick Look renders a Wallet-style preview instantly."),
        ("photo.on.rectangle", "See thumbnails", "Finder shows a card thumbnail for every pass.")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                VStack(spacing: 14) {
                    ForEach(steps, id: \.title) { step in
                        StepRow(symbol: step.symbol, title: step.title, detail: step.detail)
                    }
                }
                .padding(20)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 10) {
                    Text("Not seeing previews?")
                        .font(.headline)
                    Text("Make sure the extension is enabled, then relaunch Finder.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack {
                        Button("Open Extensions Settings…", action: openExtensionSettings)
                        Button("Refresh Quick Look", action: refreshQuickLook)
                    }
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))

                Text("100% on-device · no network access · open source")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(28)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("pkpass Quick Look")
                .font(.largeTitle.bold())
            Text("Preview Apple Wallet passes without opening them.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func openExtensionSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
            "x-apple.systempreferences:com.apple.preferences.extensions"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    private func refreshQuickLook() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-r"]
        try? process.run()
    }
}

private struct StepRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 38, height: 38)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
