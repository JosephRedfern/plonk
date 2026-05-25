import SwiftUI
import Carbon
import Observation

@main
struct PlonkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                updater: appDelegate.updater,
                onShow: { appDelegate.togglePanel() }
            )
        } label: {
            Image("MenuBarIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .accessibilityLabel("Plonk")
        }
        Settings {
            SettingsView(
                settings: appDelegate.settings,
                pythonManager: appDelegate.pythonManager,
                updater: appDelegate.updater
            )
        }
    }
}

private struct MenuBarContent: View {
    @Bindable var updater: UpdaterManager
    let onShow: () -> Void

    var body: some View {
        if let update = updater.availableUpdate {
            Button("Install Update — v\(update.displayVersionString)") {
                updater.checkForUpdates()
            }
            Divider()
        }
        Button("Show Plonk") {
            onShow()
        }
        Divider()
        SettingsLink()
        Divider()
        Button("Quit Plonk") {
            NSApp.terminate(nil)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let pythonManager = PythonManager()
    let updater = UpdaterManager()
    private var panel: FloatingPanel!
    private var hostingView: NSHostingView<ContentView>!
    private var panelTopY: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        NSApp.setActivationPolicy(.accessory)
        setupPanel()
        setupHotKey()
        observeContentChanges()
        pythonManager.start(pythonPath: settings.effectivePythonPath, bootstrap: settings.bootstrapScript, projectDir: settings.effectiveProjectDir)
    }

    private func setupPanel() {
        let contentView = ContentView(pythonManager: pythonManager, settings: settings)
        hostingView = NSHostingView(rootView: contentView)

        let initialHeight: CGFloat = 48
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: initialHeight))
        panel.contentView = hostingView

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 300
            panelTopY = screenFrame.minY + screenFrame.height * 0.72
            panel.setFrameOrigin(NSPoint(x: x, y: panelTopY - initialHeight))
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53, event.window === self.panel {
                self.panel.orderOut(nil)
                return nil
            }
            if event.window === self.panel,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "c" {
                if let textView = self.panel.firstResponder as? NSTextView,
                   textView.selectedRange().length > 0 {
                    return event
                }
                let output = self.pythonManager.history.first?.output ?? ""
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(output, forType: .string)
                return nil
            }
            return event
        }
    }

    private func setupHotKey() {
        HotKeyManager.shared.onHotKey = { [weak self] in
            self?.togglePanel()
        }
        // Control + Option + Space
        HotKeyManager.shared.register(keyCode: 49, modifiers: UInt32(controlKey | optionKey))
    }

    private func observeContentChanges() {
        withObservationTracking {
            _ = pythonManager.history.count
            _ = pythonManager.lastError
            _ = pythonManager.isReady
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.observeContentChanges()
                DispatchQueue.main.async {
                    self?.updatePanelSize()
                }
            }
        }
    }

    private func updatePanelSize() {
        guard panel.isVisible else { return }
        let idealSize = hostingView.intrinsicContentSize
        let newHeight = min(max(idealSize.height, 48), 500)
        var frame = panel.frame
        frame.size.height = newHeight
        frame.origin.y = panelTopY - newHeight
        panel.setFrame(frame, display: true, animate: false)
    }

    func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            updatePanelSize()
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func panelDidResignKey(_ notification: Notification) {
        panel.orderOut(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        pythonManager.stop()
        HotKeyManager.shared.unregister()
    }
}
