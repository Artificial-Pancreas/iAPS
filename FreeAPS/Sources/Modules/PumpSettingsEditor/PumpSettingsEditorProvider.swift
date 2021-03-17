import Combine
import LoopKit
import LoopKitUI

protocol PumpSettingsObserver {
    func pumpSettingsDidChange(_ pumpSettings: PumpSettings)
}

extension PumpSettingsEditor {
    final class Provider: BaseProvider, PumpSettingsEditorProvider {
        private let processQueue = DispatchQueue(label: "PumpSettingsEditorProvider.processQueue")
        @Injected() private var broadcaster: Broadcaster!

        func settings() -> PumpSettings {
            (try? storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self))
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 5, maxBolus: 10, maxBasal: 2)
        }

        func save(settings: PumpSettings) -> AnyPublisher<Void, Error> {
            func save() {
                try? storage.save(settings, as: OpenAPS.Settings.settings)
                processQueue.async {
                    self.broadcaster.notify(PumpSettingsObserver.self, on: self.processQueue) {
                        $0.pumpSettingsDidChange(settings)
                    }
                }
            }

            guard let pump = deviceManager?.pumpManager else {
                save()
                return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
            }
            // Don't ask why 🤦‍♂️
            let sync = DeliveryLimitSettingsTableViewController(style: .grouped)
            sync.maximumBasalRatePerHour = Double(settings.maxBasal)
            sync.maximumBolus = Double(settings.maxBolus)
            return Future { promise in
                self.processQueue.async {
                    pump.syncDeliveryLimitSettings(for: sync) { result in
                        switch result {
                        case .success:
                            save()
                            promise(.success(()))
                        case let .failure(error):
                            promise(.failure(error))
                        }
                    }
                }
            }.eraseToAnyPublisher()
        }
    }
}
