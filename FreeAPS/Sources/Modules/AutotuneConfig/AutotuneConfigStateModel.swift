import Combine
import LoopKit
import SwiftUI

extension AutotuneConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var apsManager: APSManager!
        @Published var useAutotune = false
        @Published var autotune: Autotune?
        @Published var basalProfile: [BasalProfileEntry?] = []
        private(set) var units: GlucoseUnits = .mmolL
        @Published var publishedDate = Date()
        @Persisted(key: "lastAutotuneDate") private var lastAutotuneDate = Date() {
            didSet {
                DispatchQueue.main.async {
                    self.publishedDate = self.lastAutotuneDate
                }
            }
        }

        override func subscribe() {
            autotune = provider.autotune
            var bp: [BasalProfileEntry?] = []
            for p in provider.autotune?.basalProfile ?? [] {
                var np: BasalProfileEntry?
                for b in provider.basalProfilePump {
                    if b.start > p.start {
                        NSLog("Matched \(p) with \(b)")
                        break
                    }
                    np = b
                }
                bp.append(np)
            }
            NSLog("basalProfile \(bp)")
            basalProfile = bp
            units = settingsManager.settings.units
            useAutotune = settingsManager.settings.useAutotune
            publishedDate = lastAutotuneDate

            $useAutotune
                .removeDuplicates()
                .flatMap { [weak self] use -> AnyPublisher<Bool, Never> in
                    guard let self = self else {
                        return Just(false).eraseToAnyPublisher()
                    }
                    self.settingsManager.settings.useAutotune = use
                    return self.apsManager.makeProfiles()
                }
                .cancellable()
                .store(in: &lifetime)
        }

        func run() {
            provider.runAutotune()
                .receive(on: DispatchQueue.main)
                .flatMap { [weak self] result -> AnyPublisher<Bool, Never> in
                    guard let self = self else {
                        return Just(false).eraseToAnyPublisher()
                    }
                    self.autotune = result
                    return self.apsManager.makeProfiles()
                }
                .sink { [weak self] _ in
                    self?.lastAutotuneDate = Date()
                }.store(in: &lifetime)
        }

        func delete() {
            provider.deleteAutotune()
            autotune = nil
            apsManager.makeProfiles()
                .cancellable()
                .store(in: &lifetime)
        }

        func copyBasal() {
            guard let autotuneProfile = autotune?.basalProfile else {
                NSLog("copyBasal failure - no profile")
                return
            }
            guard let pump = provider.deviceManager?.pumpManager else {
                // storage.save(profile, as: OpenAPS.Settings.basalProfile)
                NSLog("copyBasal failure - no pump")
                return
            }
            let profile = autotuneProfile.map {
                BasalProfileEntry(
                    start: $0.start,
                    minutes: $0.minutes,
                    // Round to 0.05, ie. 1/20th
                    rate: Decimal(round(Double($0.rate) * 20) / 20)
                )
            }
            for item in profile {
                NSLog("\(item.minutes) \(item.rate)")
            }
            let syncValues = profile.map {
                RepeatingScheduleValue(
                    startTime: TimeInterval($0.minutes * 60),
                    value: Double($0.rate)
                )
            }

            for item in syncValues {
                NSLog("\(item.startTime) \(item.value)")
            }
            pump.syncBasalRateSchedule(items: syncValues) { result in
                switch result {
                case .success:
                    NSLog("copyBasal success")
                    self.provider.storage.save(profile, as: OpenAPS.Settings.basalProfile)
                case let .failure(error):
                    NSLog("copyBasal failed \(error)")
                }
            }
        }
    }
}
