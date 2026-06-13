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

/// Shows a Dock icon while a window is open; drops it (accessory, background)
/// when the window is closed — and never quits on last-window-close.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launch as a normal app so the window reliably appears and comes forward.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification, object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // keep running in the background when the window is closed
    }

    /// Reopening (no Dock icon to click, but `open` / Launchpad still fire this).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        AppDelegate.showMainWindow()
        return true
    }

    /// "Open with pkpass Quick Look" (from the Quick Look window or Finder) —
    /// load the pass and pop the viewer so it can be exported.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        PassViewerModel.shared.load(url: url) // hasPass flips the window to the viewer
        AppDelegate.showMainWindow()
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard (note.object as? NSWindow)?.styleMask.contains(.titled) == true else { return }
        // After this window closes, if no titled window remains, hide the Dock icon.
        DispatchQueue.main.async {
            let stillOpen = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
            if !stillOpen { NSApp.setActivationPolicy(.accessory) }
        }
    }

    /// Brings the app forward with a Dock icon and shows the main window.
    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Re-show an existing window, or let the scene re-create it.
        if let window = NSApp.windows.first(where: { $0.styleMask.contains(.titled) }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Menu-bar menu

struct MenuBarContent: View {
    let updater: SPUUpdater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open pkpass Quick Look") {
            NSApp.setActivationPolicy(.regular) // restore the Dock icon
            openWindow(id: "main")              // recreate the window if it was closed
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
    @ObservedObject private var viewerModel = PassViewerModel.shared

    private let steps: [(symbol: String, title: String, detail: String)] = [
        ("magnifyingglass", "Select a pass", "Click any .pkpass file in Finder."),
        ("space", "Press Space", "Quick Look renders a Wallet-style card instantly."),
        ("photo.on.rectangle", "See thumbnails", "Finder shows a card thumbnail for every pass.")
    ]

    var body: some View {
        // When a pass is loaded, the whole window becomes the viewer (with the
        // Export button). This avoids fragile sheets that can hide behind Finder.
        if viewerModel.hasPass {
            PassViewerView(model: viewerModel, onDone: { viewerModel.reset() })
        } else {
            home
        }
    }

    private var home: some View {
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
                // Loading a pass flips the window into the viewer (with Export).
                viewerModel.openFile()
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
