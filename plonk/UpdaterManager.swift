import Foundation
import Observation
import Sparkle

@Observable
final class UpdaterManager: NSObject, SPUUpdaterDelegate {
    @ObservationIgnored private let controller: SPUStandardUpdaterController

    var availableUpdate: SUAppcastItem?
    var automaticallyChecksForUpdates: Bool {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    override init() {
        let c = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = c
        self.automaticallyChecksForUpdates = c.updater.automaticallyChecksForUpdates
        super.init()
        c.updater.delegate = self
        c.startUpdater()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableUpdate = item
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableUpdate = nil
    }
}
