import Foundation
import Observation
import Sparkle

@Observable
final class UpdaterManager {
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private let delegate: UpdaterDelegate

    var availableUpdate: SUAppcastItem?
    var automaticallyChecksForUpdates: Bool {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    init() {
        let delegate = UpdaterDelegate()
        let c = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        self.delegate = delegate
        self.controller = c
        self.automaticallyChecksForUpdates = c.updater.automaticallyChecksForUpdates
        delegate.onFoundUpdate = { [weak self] item in
            self?.availableUpdate = item
        }
        delegate.onNoUpdate = { [weak self] in
            self?.availableUpdate = nil
        }
        c.startUpdater()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var onFoundUpdate: ((SUAppcastItem) -> Void)?
    var onNoUpdate: (() -> Void)?

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        onFoundUpdate?(item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        onNoUpdate?()
    }
}
