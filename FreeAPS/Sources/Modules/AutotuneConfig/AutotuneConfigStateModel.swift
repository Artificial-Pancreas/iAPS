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
        @Published var autotune: Autotune?
        private(set) var units: GlucoseUnits = .mmolL
        /// True when AutoISF or Dynamic ISF is the active algorithm.
        /// When active, ISF is measured directly from CoreData Reasons entries rather than
        /// inferred by oref0 deviation analysis. CR tuning may still be less reliable.
        @Published private(set) var dynamicAlgorithmActive = false
        /// Human-readable name of the active ISF algorithm for display in the UI.
        @Published private(set) var algorithmName = ""
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

        /// The ISF schedule derived from CoreData Reasons entries, if available.
        /// Only populated when a dynamic algorithm is active and autotune has run at least once.
        @Published private(set) var reasonsISFSchedule: ReasonsISFSchedule?
        /// The current ISF profile, used for side-by-side comparison in the UI.
        @Published private(set) var currentISFProfile: InsulinSensitivities?

        override func subscribe() {
            autotune = provider.autotune
            units = settingsManager.settings.units
            useAutotune = settingsManager.settings.useAutotune
            publishedDate = lastAutotuneDate
            increment = Double(settingsManager.preferences.bolusIncrement)

            // Detect active algorithm.
            // With AutoISF or DynamicISF, autotune now uses CoreData Reasons entries to
            // build a per-hour median ISF schedule (the actual ISF the loop applied), which
            // corrects the BGI calculation and gives a reliable ISF measurement.
            // Carb-ratio tuning remains less reliable under dynamic algorithms because the
            // carb-absorption model assumes a fixed ISF; onlyAutotuneBasals still defaults
            // to true on first activation, but users may override it if they want ISF output.
            let prefs = settingsManager.preferences
            let s = settingsManager.settings
            let isDynamic = s.autoisf || prefs.useNewFormula
            dynamicAlgorithmActive = isDynamic
            if s.autoisf {
                algorithmName = "AutoISF"
            } else if prefs.sigmoid, prefs.enableDynamicCR {
                algorithmName = "Dynamic ISF + CR (Sigmoid)"
            } else if prefs.sigmoid {
                algorithmName = "Dynamic ISF (Sigmoid)"
            } else if prefs.useNewFormula, prefs.enableDynamicCR {
                algorithmName = "Dynamic ISF + CR (Logarithmic)"
            } else if prefs.useNewFormula {
                algorithmName = "Dynamic ISF (Logarithmic)"
            } else {
                algorithmName = "oref0"
            }

            subscribeSetting(\.onlyAutotuneBasals, on: $onlyAutotuneBasals) { onlyAutotuneBasals = $0 }

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
                        // Reload the ISF schedule — autotune may have just generated a fresh one.
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

        // MARK: - ISF schedule helpers

        private func loadISFSchedule() {
            reasonsISFSchedule = provider.reasonsISFSchedule
            currentISFProfile   = provider.currentISFProfile
        }

        /// Returns the ISF value from the current profile that covers the given hour-of-day.
        /// The returned value is in whatever units the profile stores (matching `units`).
        func currentISFForHour(_ hour: Int) -> Decimal? {
            guard let profile = currentISFProfile, !profile.sensitivities.isEmpty else { return nil }
            let targetMinutes = hour * 60
            return profile.sensitivities
                .sorted { $0.offset < $1.offset }
                .last { $0.offset <= targetMinutes }
                .map { $0.sensitivity }
        }

        /// Converts a raw mg/dL ISF value from the Reasons schedule into the user's display unit.
        func displayISF(mgdl: Double) -> Decimal {
            if units == .mmolL {
                // Round to 1 decimal place in mmol/L
                let mmol = mgdl * Double(GlucoseUnits.exchangeRate)
                return Decimal((mmol * 10).rounded() / 10)
            } else {
                return Decimal(Int(mgdl.rounded()))
            }
        }

        /// Writes the Reasons-based ISF schedule to the insulin_sensitivities profile file.
        /// Creates one entry per hour (24 entries) and triggers a profile rebuild.
        func replaceISF() {
            guard let schedule = reasonsISFSchedule else { return }

            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "HH:mm:ss"

            let entries: [InsulinSensitivityEntry] = (0 ..< 24).compactMap { hour in
                guard let mgdl = schedule.hours[String(hour)] else { return nil }
                let offsetMinutes = hour * 60
                let date = Date(timeIntervalSince1970: TimeInterval(offsetMinutes * 60))
                return InsulinSensitivityEntry(
                    sensitivity: displayISF(mgdl: mgdl),
                    offset: offsetMinutes,
                    start: formatter.string(from: date)
                )
            }

            guard !entries.isEmpty else { return }

            let userUnits = settingsManager.settings.units
            let profile = InsulinSensitivities(
                units: userUnits,
                userPrefferedUnits: userUnits,
                sensitivities: entries
            )
            provider.saveISFProfile(profile)
            debug(.service, "ISF profile replaced with Reasons-based 24-hour schedule by user.")

            // Refresh the local copy so the comparison grid updates immediately.
            currentISFProfile = profile

            apsManager.makeProfiles()
                .cancellable()
                .store(in: &lifetime)
        }

        // MARK: - Basal replace

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
    }
}
