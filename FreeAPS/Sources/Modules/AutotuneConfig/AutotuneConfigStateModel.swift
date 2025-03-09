import Combine
import LoopKit
import SwiftUI

extension AutotuneConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var apsManager: APSManager!
        @Injected() private var storage: FileStorage!
        @Published var useAutotune = false
        @Published var onlyAutotuneBasals = false
        @Published var autotune: Autotune?
        private(set) var units: GlucoseUnits = .mmolL
        @Published var publishedDate = Date()
        @Published var increment: Double = 0.1
        @Persisted(key: "lastAutotuneDate") private var lastAutotuneDate = Date() {
            didSet {
                DispatchQueue.main.async {
                    self.publishedDate = self.lastAutotuneDate
                }
            }
        }

        @Published var currentProfile: [BasalProfileEntry] = []
        @Published var currentTotal: Decimal = 0.0

        override func subscribe() {
            autotune = provider.autotune
            units = settingsManager.settings.units
            useAutotune = settingsManager.settings.useAutotune
            publishedDate = lastAutotuneDate
            increment = Double(settingsManager.preferences.bolusIncrement)
            subscribeSetting(\.onlyAutotuneBasals, on: $onlyAutotuneBasals) { onlyAutotuneBasals = $0 }

            currentProfile = provider.profile
            calcTotal()

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

        func calcTotal() {
            var profileWith24hours = currentProfile.map(\.minutes)
            profileWith24hours.append(24 * 60)
            let pr2 = zip(currentProfile, profileWith24hours.dropFirst())
            currentTotal = pr2.reduce(0) { $0 + (Decimal($1.1 - $1.0.minutes) / 60) * $1.0.rate }
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

        func replace() {
            if let autotunedBasals = autotune {
                let basals = autotunedBasals.basalProfile
                    .map { basal -> BasalProfileEntry in
                        BasalProfileEntry(
                            start: String(basal.start.prefix(5)),
                            minutes: basal.minutes,
                            rate: basal.rate.roundBolus(increment: increment)
                        )
                    }
                guard let pump = apsManager.pumpManager else {
                    storage.save(basals, as: OpenAPS.Settings.basalProfile)
                    debug(.service, "Basals have been replaced with Autotuned Basals by user.")
                    return
                }
                let syncValues = basals.map {
                    RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: Double($0.rate))
                }
                pump.syncBasalRateSchedule(items: syncValues) { result in
                    switch result {
                    case .success:
                        self.storage.save(basals, as: OpenAPS.Settings.basalProfile)
                        debug(.service, "Basals saved to pump!")
                    case .failure:
                        debug(.service, "Basals couldn't be saved to pump")
                    }
                }
            }
        }
    }
}
