import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var pythonManager: PythonManager
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

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
                    Text("⌃⌥ Space")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
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
    }
}
