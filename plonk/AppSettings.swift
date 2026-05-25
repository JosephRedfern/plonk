import Foundation
import Observation

@Observable
final class AppSettings {
    var pythonPath: String {
        didSet { UserDefaults.standard.set(pythonPath, forKey: "pythonPath") }
    }
    var bootstrapScript: String {
        didSet { UserDefaults.standard.set(bootstrapScript, forKey: "bootstrapScript") }
    }

    init() {
        let defaults = UserDefaults.standard
        pythonPath = defaults.string(forKey: "pythonPath") ?? "/usr/bin/python3"
        bootstrapScript = defaults.string(forKey: "bootstrapScript") ?? ""
    }
}
