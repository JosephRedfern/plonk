import SwiftUI

struct ContentView: View {
    var pythonManager: PythonManager
    var settings: AppSettings
    @State private var commandText = ""
    @State private var historyIndex: Int? = nil
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            inputBar

            if let error = pythonManager.lastError {
                Divider()
                Text(error)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !pythonManager.history.isEmpty {
                Divider()
                historyView
            }
        }
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            isInputFocused = true
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text(">>>")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.tertiary)

            TextField("", text: $commandText)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .monospaced))
                .focused($isInputFocused)
                .onSubmit {
                    let cmd = commandText
                    commandText = ""
                    historyIndex = nil
                    handleCommand(cmd)
                }
                .onKeyPress(.upArrow) {
                    let commands = pythonManager.history
                    guard !commands.isEmpty else { return .ignored }
                    let next = (historyIndex ?? -1) + 1
                    guard next < commands.count else { return .ignored }
                    historyIndex = next
                    commandText = commands[next].command
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard let idx = historyIndex else { return .ignored }
                    if idx <= 0 {
                        historyIndex = nil
                        commandText = ""
                    } else {
                        historyIndex = idx - 1
                        commandText = pythonManager.history[idx - 1].command
                    }
                    return .handled
                }

            if pythonManager.isExecuting {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var historyView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(pythonManager.history) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(">>> \(entry.command)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if !entry.output.isEmpty {
                            Text(entry.output)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        if !entry.errorOutput.isEmpty {
                            Text(entry.errorOutput)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 400)
    }

    private func handleCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        switch trimmed {
        case "%clear":
            pythonManager.clearHistory()
        case "%reset":
            pythonManager.reset(pythonPath: settings.pythonPath, bootstrap: settings.bootstrapScript)
        default:
            pythonManager.execute(trimmed)
        }
    }
}
