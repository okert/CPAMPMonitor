import AppKit
import SwiftUI
import UserNotifications
import MonitorCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = MonitorModel()
    var item: NSStatusItem!
    var panel: NSPanel?
    var outsideClickMonitor: Any?
    var settings: NSWindow?
    var foreground: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        model.onChange = { [weak self] in self?.updateStatus() }
        model.openSettings = { [weak self] in self?.showSettings() }
        updateStatus()
        model.start()
        if CommandLine.arguments.contains("--show") { showMonitorWindow() }
        else if !model.configured { showSettings() }
    }

    func updateStatus() {
        var name = "chart.bar.xaxis"
        // Keep all status-item symbols as template images so macOS uses the
        // same foreground color as the rest of the menu bar, including alerts.
        if model.paused { name = "pause.circle" }
        else if let low = model.lowest, low <= Double(model.config.critical) { name = "exclamationmark.circle.fill" }
        else if let low = model.lowest, low <= Double(model.config.warning) { name = "exclamationmark.circle.fill" }
        else if model.hasProblems { name = "exclamationmark.triangle" }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "CPAMP Monitor")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.contentTintColor = nil
        item.button?.title = model.lowest.map { " \(Int($0))%" } ?? ""
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        item.button?.toolTip = "CPAMP Monitor · " + model.statusText
    }

    @objc func togglePopover() {
        guard let button = item.button else { return }
        if let panel, panel.isVisible {
            closePanel()
            return
        }

        model.now = Date()
        let visibleHeight = button.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
        let maximumHeight = max(420, visibleHeight - 24)
        let rows = max(model.accounts.count, 1)
        let listHeight = model.accounts.isEmpty
            ? 190
            : min(660, max(140, min(CGFloat(rows) * 112, maximumHeight - 180)))
        let contentHeight = min(maximumHeight, 180 + listHeight)
        let content = MonitorView(model: model, maximumHeight: maximumHeight)
        let hosting = NSHostingView(rootView: content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous)))

        let floating = panel ?? makePanel()
        floating.contentView = hosting
        floating.setContentSize(NSSize(width: 500, height: contentHeight))
        positionPanel(floating, below: button)
        floating.orderFrontRegardless()
        panel = floating
        installOutsideClickMonitor()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePanel() -> NSPanel {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        window.hidesOnDeactivate = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }

    private func positionPanel(_ panel: NSPanel, below button: NSStatusBarButton) {
        guard let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let width = panel.frame.width
        let x = min(max(visible.minX + 8, buttonRect.midX - width / 2), visible.maxX - width - 8)
        // Screen coordinates have their origin at the bottom-left. Clamp the
        // panel's top edge to the usable area as status-item windows can
        // report a rect that includes the menu bar itself.
        // Leave room for the native window shadow so it cannot bleed into the
        // menu bar even when the status-item window reports its full height.
        let menuBarClearance: CGFloat = 12
        let top = min(buttonRect.minY - menuBarClearance, visible.maxY - menuBarClearance)
        let y = max(visible.minY + 8, top - panel.frame.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) { self.closePanel() }
            }
        }
    }

    private func closePanel() {
        panel?.orderOut(nil)
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        outsideClickMonitor = nil
    }

    private func closePopoverForSettings() {
        closePanel()
    }

    func showSettings() {
        closePopoverForSettings()
        if settings == nil {
            settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 650), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            settings?.title = "CPAMP Monitor 设置"
            settings?.isReleasedWhenClosed = false
            settings?.center()
        }
        settings?.contentView = NSHostingView(rootView: SettingsView(model: model))
        settings?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showMonitorWindow() {
        foreground = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 700), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        foreground?.title = "CPAMP Monitor"
        foreground?.contentView = NSHostingView(rootView: MonitorView(model: model))
        foreground?.isReleasedWhenClosed = false
        foreground?.center()
        foreground?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { togglePopover() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        closePanel()
        model.tunnel.stop()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

// Diagnostics accept credentials only on stdin, never in process arguments or logs.
let arguments = CommandLine.arguments
if arguments.contains("--configure") || arguments.contains("--smoke") {
    Task { @MainActor in
        do {
            var config = Storage.load(Configuration.self, key: "configuration") ?? Configuration()
            if let index = arguments.firstIndex(of: "--configure"), index + 1 < arguments.count {
                config.baseURL = arguments[index + 1]
                config.name = "OC"
                if let hostIndex = arguments.firstIndex(of: "--ssh"), hostIndex + 1 < arguments.count {
                    config.sshHost = arguments[hostIndex + 1]
                } else { config.sshHost = "" }
                config = try config.validated()
                let secret = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                try Storage.storeCredential(secret, server: config.credentialID)
                Storage.save(config, key: "configuration")
                print("Configuration saved; credential stored in Keychain.")
            }
            if arguments.contains("--smoke") {
                let tunnel = Tunnel()
                try await tunnel.prepare(config)
                defer { tunnel.stop() }
                let key = try Storage.credential(config.credentialID)
                let client = try APIClient(baseURL: config.baseURL, key: key)
                let accounts = try await client.accounts()
                let history = try await client.history(accounts)
                print("Accounts: \(accounts.count); history rows: \(history.count)")
                var failures = 0
                for account in accounts where !account.disabled {
                    do {
                        let result = try await client.quota(account)
                        print("\(account.provider): " + result.windows.map { "\($0.title)=\(Int($0.remaining ?? -1))%, reset=\($0.reset?.ISO8601Format() ?? "unknown")" }.joined(separator: "; "))
                    } catch { failures += 1; print("\(account.provider): quota query failed") }
                }
                if failures > 0 { exit(2) }
            }
            exit(0)
        } catch { print("Operation failed; check connection, service URL and Keychain access."); exit(1) }
    }
    RunLoop.main.run()
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
