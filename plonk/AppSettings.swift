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

    init() {
        let defaults = UserDefaults.standard
        pythonPath = defaults.string(forKey: "pythonPath") ?? "/usr/bin/python3"
        bootstrapScript = defaults.string(forKey: "bootstrapScript") ?? ""
        projectDir = defaults.string(forKey: "projectDir") ?? ""
        useMode = PythonMode(rawValue: defaults.string(forKey: "useMode") ?? "") ?? .projectDirectory
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
