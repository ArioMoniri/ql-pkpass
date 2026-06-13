//
//  AppMain.swift
//  pkpass Quick Look
//
//  Host app for the two Quick Look extensions. It explains how to use the
//  plugin, offers Quick Look / Finder refresh helpers, opens an in-app
//  viewer that can export passes to PDF, and wires up Sparkle auto-updates.
//

import SwiftUI
import Combine
import Sparkle

@main
struct PkpassQuickLookApp: App {
    // Owns the Sparkle updater for the app's lifetime.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup("pkpass Quick Look") {
            ContentView(updater: updaterController.updater)
                .frame(minWidth: 520, idealWidth: 560, minHeight: 600, idealHeight: 680)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}

// MARK: - Sparkle "Check for Updates" control

struct CheckForUpdatesView: View {
    let updater: SPUUpdater

    var body: some View {
        // Sparkle guards against overlapping checks internally, so the button
        // can stay enabled — this avoids a Swift 6 main-actor key-path issue.
        Button("Check for Updates…") { updater.checkForUpdates() }
    }
}

// MARK: - Main window

struct ContentView: View {
    let updater: SPUUpdater
    @State private var showingViewer = false

    private let steps: [(symbol: String, title: String, detail: String)] = [
        ("magnifyingglass", "Select a pass", "Click any .pkpass file in Finder."),
        ("space", "Press Space", "Quick Look renders a Wallet-style card instantly."),
        ("photo.on.rectangle", "See thumbnails", "Finder shows a card thumbnail for every pass.")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header

                VStack(spacing: 14) {
                    ForEach(steps, id: \.title) { step in
                        StepRow(symbol: step.symbol, title: step.title, detail: step.detail)
                    }
                }
                .padding(20)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))

                viewerCard
                maintenanceCard

                Text("Apple Wallet · Google Wallet · Samsung Wallet · 100% on-device")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
        }
        .sheet(isPresented: $showingViewer) {
            VStack(spacing: 0) {
                PassViewerView()
                HStack {
                    Spacer()
                    Button("Done") { showingViewer = false }.keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }
            .frame(minWidth: 520, minHeight: 700)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 50))
                .foregroundStyle(.tint)
            Text("pkpass Quick Look")
                .font(.largeTitle.bold())
            Text("Preview Wallet passes without opening them.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var viewerCard: some View {
        VStack(spacing: 10) {
            Text("Open & export")
                .font(.headline)
            Text("View any pass in-app and save it as a PDF.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                showingViewer = true
            } label: {
                Label("Open a pass & export PDF…", systemImage: "doc.badge.arrow.up")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    private var maintenanceCard: some View {
        VStack(spacing: 10) {
            Text("Not seeing previews?")
                .font(.headline)
            Text("Refresh Quick Look, then relaunch Finder.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button("Refresh Quick Look", action: refreshQuickLook)
                Button("Refresh Finder", action: refreshFinder)
            }
            HStack {
                Button("Extensions Settings…", action: openExtensionSettings)
                CheckForUpdatesView(updater: updater)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func openExtensionSettings() {
        for string in ["x-apple.systempreferences:com.apple.ExtensionsPreferences",
                       "x-apple.systempreferences:com.apple.preferences.extensions"] {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    private func refreshQuickLook() { run("/usr/bin/qlmanage", ["-r"]); run("/usr/bin/qlmanage", ["-r", "cache"]) }
    private func refreshFinder() { run("/usr/bin/killall", ["Finder"]) }

    private func run(_ path: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
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
