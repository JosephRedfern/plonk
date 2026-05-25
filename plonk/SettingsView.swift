import Carbon
import SwiftUI
import ServiceManagement
import Sparkle

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var pythonManager: PythonManager
    @Bindable var updater: UpdaterManager
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var isRecordingHotKey = false
    @State private var hotKeyMonitor: Any?

    var body: some View {
        Form {
            Section("Python") {
                Picker("", selection: $settings.useMode) {
                    Text("Project Directory").tag(PythonMode.projectDirectory)
                    Text("Python Interpreter").tag(PythonMode.pythonInterpreter)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if settings.useMode == .projectDirectory {
                    HStack {
                        TextField("", text: $settings.projectDir)
                            .font(.system(.body, design: .monospaced))
                            .labelsHidden()
                        Button("Browse...") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            if panel.runModal() == .OK, let url = panel.url {
                                settings.projectDir = url.path
                            }
                        }
                    }
                    Text("Plonk looks for a venv (.venv, venv, or env) inside this directory and uses it as the interpreter and uv cwd.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        TextField("", text: $settings.pythonPath)
                            .font(.system(.body, design: .monospaced))
                            .labelsHidden()
                        Button("Browse...") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = true
                            panel.canChooseDirectories = false
                            if panel.runModal() == .OK, let url = panel.url {
                                settings.pythonPath = url.path
                            }
                        }
                    }
                    Text("Leave empty to use the system python3 from your shell PATH.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Bootstrap Script") {
                TextEditor(text: $settings.bootstrapScript)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 122)
                Text("Runs start-up. Import your favourite modules and define your go-to functions here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch Plonk at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                HStack {
                    Text("Toggle Plonk:")
                    Spacer()
                    Button {
                        if isRecordingHotKey { stopRecordingHotKey() } else { startRecordingHotKey() }
                    } label: {
                        Text(isRecordingHotKey ? "Press shortcut…" : settings.hotKeyDisplay)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isRecordingHotKey ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.18))
                            )
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Updates") {
                HStack {
                    if let update = updater.availableUpdate {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Update available: v\(update.displayVersionString)")
                                .fontWeight(.medium)
                            if let date = update.date {
                                Text(date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Install...") {
                            updater.checkForUpdates()
                        }
                    } else {
                        Text("Plonk is up to date.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Check for Updates...") {
                            updater.checkForUpdates()
                        }
                    }
                }
                Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
            }

            Section {
                Button("Restart Interpreter") {
                    pythonManager.reset(
                        pythonPath: settings.effectivePythonPath,
                        bootstrap: settings.bootstrapScript,
                        projectDir: settings.effectiveProjectDir
                    )
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 640)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
            stopRecordingHotKey()
        }
    }

    private func startRecordingHotKey() {
        isRecordingHotKey = true
        HotKeyManager.shared.unregister()
        hotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleRecordedKey(event)
            return nil
        }
    }

    private func stopRecordingHotKey() {
        if let monitor = hotKeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotKeyMonitor = nil
        }
        isRecordingHotKey = false
        HotKeyManager.shared.register(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
    }

    private func handleRecordedKey(_ event: NSEvent) {
        if event.keyCode == 53 { // Escape — cancel
            stopRecordingHotKey()
            return
        }
        let flags = event.modifierFlags
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        guard mods != 0 else { return } // require at least one modifier
        let kc = UInt32(event.keyCode)
        let chars = event.charactersIgnoringModifiers ?? ""
        settings.hotKeyCode = kc
        settings.hotKeyModifiers = mods
        settings.hotKeyDisplay = formatShortcut(keyCode: kc, modifiers: mods, fallback: chars)
        stopRecordingHotKey()
    }
}

fileprivate func formatShortcut(keyCode: UInt32, modifiers: UInt32, fallback: String) -> String {
    var prefix = ""
    if modifiers & UInt32(controlKey) != 0 { prefix += "⌃" }
    if modifiers & UInt32(optionKey)  != 0 { prefix += "⌥" }
    if modifiers & UInt32(shiftKey)   != 0 { prefix += "⇧" }
    if modifiers & UInt32(cmdKey)     != 0 { prefix += "⌘" }
    return prefix + " " + keyName(for: keyCode, fallback: fallback)
}

fileprivate func keyName(for keyCode: UInt32, fallback: String) -> String {
    switch keyCode {
    case 49:  return "Space"
    case 36:  return "Return"
    case 48:  return "Tab"
    case 51:  return "Delete"
    case 53:  return "Escape"
    case 123: return "←"
    case 124: return "→"
    case 125: return "↓"
    case 126: return "↑"
    case 122: return "F1"
    case 120: return "F2"
    case 99:  return "F3"
    case 118: return "F4"
    case 96:  return "F5"
    case 97:  return "F6"
    case 98:  return "F7"
    case 100: return "F8"
    case 101: return "F9"
    case 109: return "F10"
    case 103: return "F11"
    case 111: return "F12"
    default:  return fallback.uppercased()
    }
}
