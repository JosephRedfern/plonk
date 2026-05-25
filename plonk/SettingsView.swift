import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var pythonManager: PythonManager

    var body: some View {
        Form {
            Section("Python Interpreter") {
                HStack {
                    TextField("Path to Python", text: $settings.pythonPath)
                        .font(.system(.body, design: .monospaced))
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url {
                            settings.pythonPath = url.path
                        }
                    }
                }
            }

            Section("Bootstrap Script") {
                TextEditor(text: $settings.bootstrapScript)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                Text("Runs when the interpreter starts. Use for imports, etc.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Keyboard Shortcut") {
                HStack {
                    Text("Toggle plonk:")
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
                        pythonPath: settings.pythonPath,
                        bootstrap: settings.bootstrapScript
                    )
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 400)
    }
}
