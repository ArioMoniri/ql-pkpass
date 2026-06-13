//
//  AppMain.swift
//  pkpass Quick Look
//
//  Host app for the two Quick Look extensions. It explains how to use the
//  plugin, offers Quick Look / Finder refresh helpers, opens an in-app
//  viewer that can export passes to PDF, and wires up Sparkle auto-updates.
//

import SwiftUI
import Sparkle

@main
struct PkpassQuickLookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Owns the Sparkle updater for the app's lifetime.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    var body: some Scene {
        // A single on-demand window — there's no Dock icon, so closing it just
        // hides it; the app stays alive in the menu bar (see AppDelegate).
        Window("pkpass Quick Look", id: "main") {
            ContentView(updater: updaterController.updater)
                .frame(minWidth: 520, idealWidth: 560, minHeight: 600, idealHeight: 700)
        }
        .windowResizability(.contentSize)

        // Menu-bar presence so the (Dock-less) helper is always reachable.
        MenuBarExtra("pkpass Quick Look", systemImage: "wallet.pass.fill") {
            MenuBarContent(updater: updaterController.updater)
        }
    }
}

/// Runs as a menu-bar accessory: no Dock icon, survives window close.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // keep running in the background when the window is closed
    }
}

// MARK: - Menu-bar menu

struct MenuBarContent: View {
    let updater: SPUUpdater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open pkpass Quick Look") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        CheckForUpdatesView(updater: updater)
        Button("Refresh Quick Look", action: Helpers.refreshQuickLook)
        Button("Refresh Finder", action: Helpers.refreshFinder)
        Divider()
        Button("Quit pkpass Quick Look") { NSApp.terminate(nil) }
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

// MARK: - Shared helpers

enum Helpers {
    static func openExtensionSettings() {
        for string in ["x-apple.systempreferences:com.apple.ExtensionsPreferences",
                       "x-apple.systempreferences:com.apple.preferences.extensions"] {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    static func refreshQuickLook() {
        run("/usr/bin/qlmanage", ["-r"])
        run("/usr/bin/qlmanage", ["-r", "cache"])
    }

    static func refreshFinder() { run("/usr/bin/killall", ["Finder"]) }

    private static func run(_ path: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try? process.run()
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
                Button("Refresh Quick Look", action: Helpers.refreshQuickLook)
                Button("Refresh Finder", action: Helpers.refreshFinder)
            }
            HStack {
                Button("Extensions Settings…", action: Helpers.openExtensionSettings)
                CheckForUpdatesView(updater: updater)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
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
