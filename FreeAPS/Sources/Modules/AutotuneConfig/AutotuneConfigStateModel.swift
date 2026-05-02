import Combine
import LoopKit
import SwiftUI

extension AutotuneConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var deviceManager: DeviceDataManager!
        @Injected() var apsManager: APSManager!
        @Injected() private var storage: FileStorage!
        @Published var useAutotune = false
        @Published var onlyAutotuneBasals = false
        @Published var calculateISFSuggestions = false
        @Published var autotune: Autotune?
        private(set) var units: GlucoseUnits = .mmolL
        @Published var publishedDate = Date()
        @Published var increment: Double = 0.1
        @Published var running: Bool = false

        @Persisted(key: "lastAutotuneDate") private var lastAutotuneDate = Date() {
            didSet {
                DispatchQueue.main.async {
                    self.publishedDate = self.lastAutotuneDate
                }
            }
        }

        @Published var currentProfile: [BasalProfileEntry] = []
        @Published var currentTotal: Decimal = 0.0

        @Published private(set) var isfSchedule: ReasonsISFSchedule?
        @Published private(set) var currentISFProfile: InsulinSensitivities?

        override func subscribe() {
            autotune = provider.autotune
            units = settingsManager.settings.units
            useAutotune = settingsManager.settings.useAutotune
            publishedDate = lastAutotuneDate
            increment = Double(settingsManager.preferences.bolusIncrement)
            subscribeSetting(\.onlyAutotuneBasals, on: $onlyAutotuneBasals) { onlyAutotuneBasals = $0 }
            subscribeSetting(\.calculateISFSuggestions, on: $calculateISFSuggestions) { calculateISFSuggestions = $0 }

            currentProfile = provider.profile
            calcTotal()
            loadISFSchedule()

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

        @MainActor func run() {
            running.toggle()
            provider.runAutotune()
                .receive(on: DispatchQueue.main)
                .flatMap { [weak self] result -> AnyPublisher<Bool, Never> in
                    guard let self = self else {
                        return Just(false).eraseToAnyPublisher()
                    }
                    self.autotune = result

                    // Round
                    if var tuned = self.autotune {
                        let basal = tuned.basalProfile.map { basal in
                            BasalProfileEntry(
                                start: basal.start,
                                minutes: basal.minutes,
                                rate: basal.rate.roundBolusIncrements(increment: self.increment)
                            )
                        }
                        tuned.basalProfile = basal
                        self.autotune = tuned
                    }

                    return self.apsManager.makeProfiles()
                }
                .sink { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.lastAutotuneDate = Date()
                        self?.running.toggle()
                        self?.loadISFSchedule()
                    }
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
                            rate: basal.rate.roundBolusIncrements(increment: increment)
                        )
                    }
                guard let pump = deviceManager.pumpManager else {
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

        // MARK: - Calculated ISF

        private func loadISFSchedule() {
            isfSchedule = provider.reasonsISFSchedule
            currentISFProfile = provider.currentISFProfile
        }

        /// Returns the profile ISF covering the given hour in the user's display units.
        func currentISFForHour(_ hour: Int) -> Decimal? {
            guard let profile = currentISFProfile, !profile.sensitivities.isEmpty else { return nil }
            let targetMinutes = hour * 60
            return profile.sensitivities
                .sorted { $0.offset < $1.offset }
                .last { $0.offset <= targetMinutes }
                .map(\.sensitivity)
        }

        /// Converts a raw mg/dL ISF value to the user's display unit.
        func displayISF(mgdl: Double) -> Decimal {
            if units == .mmolL {
                let mmol = mgdl * Double(GlucoseUnits.exchangeRate)
                return Decimal((mmol * 10).rounded() / 10)
            } else {
                return Decimal(Int(mgdl.rounded()))
            }
        }

        /// Writes the calculated ISF schedule to the profile and triggers a profile rebuild.
        func saveISFToProfile() {
            guard let schedule = isfSchedule else { return }

            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "HH:mm:ss"

            let entries: [InsulinSensitivityEntry] = (0 ..< 24).compactMap { hour in
                let mgdl = schedule.suggestedHours?[String(hour)] ?? schedule.hours[String(hour)]
                guard let mgdl = mgdl else { return nil }
                let offsetMinutes = hour * 60
                let date = Date(timeIntervalSince1970: TimeInterval(offsetMinutes * 60))
                let scaledMgdl = mgdl * (settingsManager.settings.isfScale as NSDecimalNumber).doubleValue
                return InsulinSensitivityEntry(
                    sensitivity: displayISF(mgdl: scaledMgdl),
                    offset: offsetMinutes,
                    start: formatter.string(from: date)
                )
            }
            guard !entries.isEmpty else { return }

            let profile = InsulinSensitivities(
                units: units,
                userPrefferedUnits: units,
                sensitivities: entries
            )
            provider.saveISFProfile(profile)
            currentISFProfile = profile
            debug(.service, "Profile ISF replaced with Calculated ISF schedule by user.")

            apsManager.makeProfiles()
                .cancellable()
                .store(in: &lifetime)
        }
    }
}
