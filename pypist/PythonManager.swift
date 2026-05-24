import Foundation
import Observation

struct HistoryEntry: Identifiable {
    let id = UUID()
    let command: String
    let output: String
    let errorOutput: String
    let timestamp: Date
}

@Observable
final class PythonManager {
    var history: [HistoryEntry] = []
    var isRunning = false
    var isExecuting = false
    private(set) var isReady = false
    var lastError: String?

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private let marker = "---PYPIST_DONE---"
    private var stderrAccumulator = ""
    private let stderrLock = NSLock()

    private static func detectVenv(pythonPath: String) -> String? {
        var dir = (pythonPath as NSString).deletingLastPathComponent
        while dir != "/" && !dir.isEmpty {
            let cfg = (dir as NSString).appendingPathComponent("pyvenv.cfg")
            if FileManager.default.fileExists(atPath: cfg) {
                return dir
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    private static func userShellEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let shell = env["SHELL"] ?? "/bin/zsh"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-l", "-i", "-c", "printf '%s' \"$PATH\""]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return env
        }
        if let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
           !path.isEmpty {
            env["PATH"] = path
        }
        return env
    }

    func start(pythonPath: String, bootstrap: String) {
        stop()
        lastError = nil

        guard FileManager.default.isExecutableFile(atPath: pythonPath) else {
            lastError = "Python not found at \(pythonPath)"
            return
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pypist_executor.py")
        do {
            try Self.executorScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            lastError = "Failed to write executor script: \(error.localizedDescription)"
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)

        var args = ["-u", scriptURL.path]
        if !bootstrap.isEmpty {
            let bootstrapURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("pypist_bootstrap.py")
            try? bootstrap.write(to: bootstrapURL, atomically: true, encoding: .utf8)
            args.append(bootstrapURL.path)
        }
        process.arguments = args

        var env = Self.userShellEnvironment()
        if let venvDir = Self.detectVenv(pythonPath: pythonPath) {
            let venvBin = (venvDir as NSString).appendingPathComponent("bin")
            env["VIRTUAL_ENV"] = venvDir
            env["PATH"] = venvBin + ":" + (env["PATH"] ?? "/usr/bin:/bin")
            env["PYPIST_PROJECT_DIR"] = (venvDir as NSString).deletingLastPathComponent
        }
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        process.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.isRunning = false
                if proc.terminationStatus != 0 {
                    self?.lastError = "Python exited with code \(proc.terminationStatus)"
                }
            }
        }

        do {
            try process.run()
        } catch {
            lastError = "Failed to launch Python: \(error.localizedDescription)"
            return
        }

        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutHandle = stdoutPipe.fileHandleForReading
        self.stderrHandle = stderrPipe.fileHandleForReading
        self.isRunning = true

        let seHandle = stderrPipe.fileHandleForReading
        DispatchQueue.global().async { [weak self] in
            while true {
                let data = seHandle.availableData
                if data.isEmpty { break }
                if let str = String(data: data, encoding: .utf8) {
                    self?.stderrLock.lock()
                    self?.stderrAccumulator += str
                    self?.stderrLock.unlock()
                }
            }
        }

        let handle = stdoutPipe.fileHandleForReading
        let m = marker
        DispatchQueue.global().async { [weak self] in
            _ = Self.readUntilMarker(from: handle, marker: m)
            DispatchQueue.main.async {
                self?.isReady = true
            }
        }
    }

    func execute(_ command: String, silent: Bool = false, completion: ((HistoryEntry) -> Void)? = nil) {
        guard isReady, let process, process.isRunning,
              let stdinHandle, let stdoutHandle, !isExecuting else { return }
        isExecuting = true

        drainStderr()
        stdinHandle.write((command + "\n").data(using: .utf8)!)

        let m = marker
        DispatchQueue.global().async { [weak self] in
            let stdout = Self.readUntilMarker(from: stdoutHandle, marker: m)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            usleep(10_000)
            let stderr = self?.drainStderr() ?? ""
            DispatchQueue.main.async {
                let entry = HistoryEntry(
                    command: command,
                    output: stdout,
                    errorOutput: stderr,
                    timestamp: Date()
                )
                if !silent || !entry.errorOutput.isEmpty {
                    self?.history.insert(entry, at: 0)
                }
                self?.isExecuting = false
                completion?(entry)
            }
        }
    }

    @discardableResult
    private func drainStderr() -> String {
        stderrLock.lock()
        let result = stderrAccumulator.trimmingCharacters(in: .whitespacesAndNewlines)
        stderrAccumulator = ""
        stderrLock.unlock()
        return result
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        isRunning = false
        isReady = false
        stderrLock.lock()
        stderrAccumulator = ""
        stderrLock.unlock()
    }

    func clearHistory() {
        history.removeAll()
    }

    func reset(pythonPath: String, bootstrap: String) {
        stop()
        history.removeAll()
        start(pythonPath: pythonPath, bootstrap: bootstrap)
    }

    private static func readUntilMarker(from handle: FileHandle, marker: String) -> String {
        var lines: [String] = []
        var buffer = Data()
        while true {
            let byte = handle.readData(ofLength: 1)
            if byte.isEmpty { break }
            if byte[0] == UInt8(ascii: "\n") {
                if let line = String(data: buffer, encoding: .utf8) {
                    if line == marker { break }
                    lines.append(line)
                }
                buffer = Data()
            } else {
                buffer.append(byte)
            }
        }
        return lines.joined(separator: "\n")
    }

    static let executorScript = """
import sys, traceback, io, subprocess, os

MARKER = "---PYPIST_DONE---"

if sys.prefix != sys.base_prefix:
    venv_bin = os.path.join(sys.prefix, "bin")
    os.environ["VIRTUAL_ENV"] = sys.prefix
    os.environ["PATH"] = venv_bin + ":" + os.environ.get("PATH", "")

if len(sys.argv) > 1 and os.path.exists(sys.argv[1]):
    try:
        exec(open(sys.argv[1]).read())
    except Exception as e:
        print(f"Bootstrap error: {e}", file=sys.stderr, flush=True)

print(MARKER, flush=True)

while True:
    try:
        line = input()
    except EOFError:
        break
    if line.startswith("!"):
        try:
            cmd = line[1:]
            cwd = None
            if cmd.strip().startswith("uv "):
                cwd = os.environ.get("PYPIST_PROJECT_DIR")
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, executable=os.environ.get("SHELL", "/bin/sh"), cwd=cwd)
            if result.stdout:
                print(result.stdout, end="", flush=True)
            if result.stderr:
                print(result.stderr, end="", file=sys.stderr, flush=True)
        except Exception as e:
            print(str(e), file=sys.stderr, flush=True)
    else:
        old_stdout = sys.stdout
        old_stderr = sys.stderr
        captured_out = io.StringIO()
        captured_err = io.StringIO()
        sys.stdout = captured_out
        sys.stderr = captured_err
        try:
            code = None
            try:
                code = compile(line, "<pypist>", "eval")
            except SyntaxError:
                pass
            if code is None:
                try:
                    code = compile(line, "<pypist>", "exec")
                except SyntaxError:
                    traceback.print_exc()
            if code is not None:
                try:
                    result = eval(code)
                    if result is not None:
                        print(repr(result))
                except Exception:
                    traceback.print_exc()
        finally:
            sys.stdout = old_stdout
            sys.stderr = old_stderr
        stdout_text = captured_out.getvalue()
        stderr_text = captured_err.getvalue()
        if stdout_text:
            print(stdout_text, end="", flush=True)
        if stderr_text:
            print(stderr_text, end="", file=sys.stderr, flush=True)
    sys.stderr.flush()
    print(MARKER, flush=True)
"""
}
