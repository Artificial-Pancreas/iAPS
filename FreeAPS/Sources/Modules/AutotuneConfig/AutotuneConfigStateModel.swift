import Combine
import LoopKit
import SwiftUI

extension AutotuneConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var deviceManager: DeviceDataManager!
        @Injected() var apsManager: APSManager!
        @Injected() private var storage: FileStorage!

        private let coreDataStorage = CoreDataStorage()

        @Published var useAutotune = false
        @Published var onlyAutotuneBasals = false
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

        override func subscribe() async {
            let settings = await settingsManager.settings
            let preferences = await settingsManager.preferences
            autotune = await storage.retrieve(OpenAPS.Settings.autotune, as: Autotune.self)
            units = settings.units
            useAutotune = settings.useAutotune
            publishedDate = lastAutotuneDate
            increment = Double(preferences.bolusIncrement)
            subscribeSetting(\.onlyAutotuneBasals, on: $onlyAutotuneBasals) { self.onlyAutotuneBasals = $0 }

            currentProfile = await retrieveProfile()
            calcTotal()

            $useAutotune
                .removeDuplicates()
                .sink { [weak self] use in
                    self?.setUseAutotune(use)
                }
                .store(in: lifetime)
        }

        private func setUseAutotune(_ use: Bool) {
            Task {
                await self.settingsManager.updateSettings { settings in
                    var updated = settings
                    updated.useAutotune = use
                    return updated
                }
                _ = await self.apsManager.makeProfiles()
            }
        }

        func calcTotal() {
            var profileWith24hours = currentProfile.map(\.minutes)
            profileWith24hours.append(24 * 60)
            let pr2 = zip(currentProfile, profileWith24hours.dropFirst())
            currentTotal = pr2.reduce(0) { $0 + (Decimal($1.1 - $1.0.minutes) / 60) * $1.0.rate }
        }

        func run() {
            running.toggle()
            Task {
                self.autotune = await runAutotune()

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

                _ = await self.apsManager.makeProfiles()

                self.lastAutotuneDate = Date()
                self.running.toggle()
            }
        }

        func delete() {
            Task {
                await deleteAutotune()
                autotune = nil
                _ = await apsManager.makeProfiles()
            }
        }

        private func readConcentration() -> Double {
            coreDataStorage.insulinConcentration().concentration
        }

        func replace() {
            Task {
                if let autotunedBasals = autotune {
                    let basals = autotunedBasals.basalProfile
                        .map { basal -> BasalProfileEntry in
                            BasalProfileEntry(
                                start: String(basal.start.prefix(5)),
                                minutes: basal.minutes,
                                rate: basal.rate.roundBolusIncrements(increment: increment)
                            )
                        }
                    let concentration = readConcentration()
                    do {
                        if let adjustedBasals = try await deviceManager.syncBasalRateSchedule(
                            items: basals,
                            concentration: concentration
                        ) {
                            await self.storage.save(adjustedBasals, as: OpenAPS.Settings.basalProfile)
                        } else {
                            // no pump configured
                            await self.storage.save(basals, as: OpenAPS.Settings.basalProfile)
                        }
                        debug(.service, "Basals have been replaced with Autotuned Basals by user.")
                    } catch {
                        debug(.service, "Basals couldn't be saved to pump")
                    }
                }
            }
        }

        private func deleteAutotune() async {
            await storage.remove(OpenAPS.Settings.autotune)
        }

        private func retrieveProfile() async -> [BasalProfileEntry] {
            await storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
                ?? [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
                ?? []
        }

        private func runAutotune() async -> Autotune? {
            await apsManager.autotune()
        }
    }
}
