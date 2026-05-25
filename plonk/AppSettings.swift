import Carbon
import Foundation
import Observation

enum PythonMode: String, CaseIterable, Identifiable {
    case projectDirectory
    case pythonInterpreter
    var id: String { rawValue }
}

@Observable
final class AppSettings {
    var pythonPath: String {
        didSet { UserDefaults.standard.set(pythonPath, forKey: "pythonPath") }
    }
    var bootstrapScript: String {
        didSet { UserDefaults.standard.set(bootstrapScript, forKey: "bootstrapScript") }
    }
    var projectDir: String {
        didSet { UserDefaults.standard.set(projectDir, forKey: "projectDir") }
    }
    var useMode: PythonMode {
        didSet { UserDefaults.standard.set(useMode.rawValue, forKey: "useMode") }
    }
    var hotKeyCode: UInt32 {
        didSet { UserDefaults.standard.set(Int(hotKeyCode), forKey: "hotKeyCode") }
    }
    var hotKeyModifiers: UInt32 {
        didSet { UserDefaults.standard.set(Int(hotKeyModifiers), forKey: "hotKeyModifiers") }
    }
    var hotKeyDisplay: String {
        didSet { UserDefaults.standard.set(hotKeyDisplay, forKey: "hotKeyDisplay") }
    }

    init() {
        let defaults = UserDefaults.standard
        pythonPath = defaults.string(forKey: "pythonPath") ?? "/usr/bin/python3"
        bootstrapScript = defaults.string(forKey: "bootstrapScript") ?? ""
        projectDir = defaults.string(forKey: "projectDir") ?? ""
        useMode = PythonMode(rawValue: defaults.string(forKey: "useMode") ?? "") ?? .pythonInterpreter
        hotKeyCode = (defaults.object(forKey: "hotKeyCode") as? Int).map { UInt32($0) } ?? 49
        hotKeyModifiers = (defaults.object(forKey: "hotKeyModifiers") as? Int).map { UInt32($0) }
            ?? UInt32(optionKey | cmdKey)
        hotKeyDisplay = defaults.string(forKey: "hotKeyDisplay") ?? "⌥⌘ Space"
    }

    var effectivePythonPath: String {
        switch useMode {
        case .projectDirectory:
            if let venv = PythonManager.findVenvIn(projectDir: projectDir) {
                return (venv as NSString).appendingPathComponent("bin/python")
            }
            return (projectDir as NSString).appendingPathComponent(".venv/bin/python")
        case .pythonInterpreter:
            return pythonPath
        }
    }

    var effectiveProjectDir: String {
        useMode == .projectDirectory ? projectDir : ""
    }
}
