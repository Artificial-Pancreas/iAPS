import CGMBLEKit
import Combine
import CoreData
import G7SensorKit
import LoopKit
import SwiftDate
import SwiftUI

extension NightscoutConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var keychain: Keychain!
        @Injected() private var nightscoutManager: NightscoutManager!
        @Injected() private var glucoseStorage: GlucoseStorage!
        @Injected() private var storage: FileStorage!
        @Injected() private var coreDataStorageGlucoseSaver: CoreDataStorageGlucoseSaver!
        @Injected() var apsManager: APSManager!
        @Injected() var deviceManager: DeviceDataManager!

        private let processQueue = DispatchQueue(label: "NightscoutConfig.StateModel.processQueue")
        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

        @Published var url = ""
        @Published var secret = ""
        @Published var message = ""
        @Published var connecting = false
        @Published var backfilling = false
        @Published var backfillingProgress = 0.0
        @Published var uploading = false
        @Published var uploadingProgress = 0.0
        @Published var isUploadEnabled = false
        @Published var nightscoutFetchEnabled = true
        @Published var units: GlucoseUnits = .mmolL
        @Published var dia: Decimal = 6
        @Published var maxBasal: Decimal = 4
        @Published var maxBolus: Decimal = 10
        @Published var allowAnnouncements: Bool = false
        @Published var backFillInterval: Decimal = 1 {
            didSet { backFillInterval = min(max(backFillInterval, 1), 90) }
        }

        @Published var uploadInterval: Decimal = 1 {
            didSet { uploadInterval = min(max(uploadInterval, 1), 90) }
        }

        override func subscribe() {
            url = keychain.getValue(String.self, forKey: Config.urlKey) ?? ""
            secret = keychain.getValue(String.self, forKey: Config.secretKey) ?? ""
            units = settingsManager.settings.units
            dia = settingsManager.pumpSettings.insulinActionCurve
            maxBasal = settingsManager.pumpSettings.maxBasal
            maxBolus = settingsManager.pumpSettings.maxBolus

            subscribeSetting(\.allowAnnouncements, on: $allowAnnouncements) { allowAnnouncements = $0 }
            subscribeSetting(\.isUploadEnabled, on: $isUploadEnabled) { isUploadEnabled = $0 }
            subscribeSetting(\.nightscoutFetchEnabled, on: $nightscoutFetchEnabled) { nightscoutFetchEnabled = $0 }
        }

        func connect() {
            var sanitizedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            if sanitizedURL.hasSuffix("/") { sanitizedURL.removeLast() }

            guard let connectionURL = URL(string: sanitizedURL) else {
                message = "Invalid URL"
                return
            }

            connecting = true
            provider.checkConnection(url: connectionURL, secret: secret.isEmpty ? nil : secret)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    if case let .failure(error) = completion {
                        self.message = "Error: \(error.localizedDescription)"
                    }
                    self.connecting = false
                } receiveValue: {
                    self.message = "Connected!"
                    self.keychain.setValue(sanitizedURL, forKey: Config.urlKey)
                    self.keychain.setValue(self.secret, forKey: Config.secretKey)
                }
                .store(in: &lifetime)
        }

        private var nightscoutAPI: NightscoutAPI? {
            guard let urlString = keychain.getValue(String.self, forKey: Config.urlKey),
                  let url = URL(string: urlString),
                  let secret = keychain.getValue(String.self, forKey: Config.secretKey) else { return nil }
            return NightscoutAPI(url: url, secret: secret)
        }

        func importSettings() {
            guard let nightscout = nightscoutAPI else {
                saveError("Can't access nightscoutAPI")
                return
            }

            let group = DispatchGroup()
            group.enter()

            var components = URLComponents(url: nightscout.url, resolvingAgainstBaseURL: false)!
            components.path = "/api/v1/profile.json"
            components.queryItems = [URLQueryItem(name: "count", value: "1")]

            var request = URLRequest(url: components.url!)
            // OPTIMIERUNG: Cache ignorieren, um immer die frischen KI-Profile zu laden
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 30

            if let secret = nightscout.secret {
                request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
            }

            URLSession.shared.dataTask(with: request) { data, response, error_ in
                defer { group.leave() }

                if let error_ = error_ {
                    self.saveError("Fetch error: \(error_.localizedDescription)")
                    return
                }

                guard let data = data, let httpResponse = response as? HTTPURLResponse,
                      (200 ... 299).contains(httpResponse.statusCode)
                else {
                    self.saveError("Invalid NS response")
                    return
                }

                do {
                    let fetchedProfileStore = try JSONCoding.decoder.decode([FetchedNightscoutProfileStore].self, from: data)
                    // WICHTIG: Muss exakt "default" sein für den Sync mit deiner Berater-App
                    guard let fetchedProfile = fetchedProfileStore.first?.store["default"] else {
                        self.saveError("Default profile not found in NS")
                        return
                    }

                    // 1. Einheiten validieren
                    guard fetchedProfile.units.contains(self.units.rawValue.prefix(4)) else {
                        self.saveError("Unit mismatch: \(fetchedProfile.units) vs \(self.units.rawValue)")
                        return
                    }

                    // 2. Basalraten (Synchronisation der 35,7 vs 37,88)
                    let pumpName = self.apsManager.pumpName.value
                    let basals = fetchedProfile.basal.map { entry in
                        BasalProfileEntry(
                            start: entry.time,
                            minutes: self.offset(entry.time) / 60,
                            rate: entry.value
                        )
                    }

                    // Check auf 0-Raten (Omnipod Safety)
                    if pumpName != "Omnipod DASH", basals.contains(where: { $0.rate <= 0 }) {
                        self.saveError("Safety: 0 U/h basal detected in NS profile.")
                        return
                    }

                    // 3. Andere Parameter (Sens, CarbRatio, Targets)
                    let sensitivities = InsulinSensitivities(
                        units: self.units,
                        userPrefferedUnits: self.units,
                        sensitivities: fetchedProfile.sens.map {
                            InsulinSensitivityEntry(sensitivity: $0.value, offset: self.offset($0.time) / 60, start: $0.time)
                        }
                    )

                    let carbratios = CarbRatios(units: .grams, schedule: fetchedProfile.carbratio.map {
                        CarbRatioEntry(start: $0.time, offset: self.offset($0.time) / 60, ratio: $0.value)
                    })

                    let targets = BGTargets(
                        units: self.units,
                        userPrefferedUnits: self.units,
                        targets: fetchedProfile.target_low.map {
                            BGTargetEntry(low: $0.value, high: $0.value, start: $0.time, offset: self.offset($0.time) / 60)
                        }
                    )

                    // 4. Sync zur Pumpe (LoopKit Integration)
                    if let pump = self.deviceManager.pumpManager {
                        let syncValues = basals
                            .map { RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: Double($0.rate)) }

                        pump.syncBasalRateSchedule(items: syncValues) { result in
                            if case .success = result {
                                self.saveAllSettings(
                                    basals: basals,
                                    cr: carbratios,
                                    sens: sensitivities,
                                    targets: targets,
                                    dia: fetchedProfile.dia
                                )
                                debug(.service, "Sync erfolgreich: \(basals.count) Basal-Segmente geladen.")
                            } else {
                                self.saveError("Pump sync failed")
                            }
                        }
                    } else {
                        self.saveAllSettings(
                            basals: basals,
                            cr: carbratios,
                            sens: sensitivities,
                            targets: targets,
                            dia: fetchedProfile.dia
                        )
                        self.saveError("No pump connected - saved to local storage only")
                    }

                } catch {
                    self.saveError("Decoding error: \(error.localizedDescription)")
                }
            }.resume()
        }

        private func saveAllSettings(
            basals: [BasalProfileEntry],
            cr: CarbRatios,
            sens: InsulinSensitivities,
            targets: BGTargets,
            dia: Decimal
        ) {
            storage.save(basals, as: OpenAPS.Settings.basalProfile)
            storage.save(cr, as: OpenAPS.Settings.carbRatios)
            storage.save(sens, as: OpenAPS.Settings.insulinSensitivities)
            storage.save(targets, as: OpenAPS.Settings.bgTargets)

            if dia != self.dia, dia >= 0 {
                let settings = PumpSettings(insulinActionCurve: dia, maxBolus: maxBolus, maxBasal: maxBasal)
                storage.save(settings, as: OpenAPS.Settings.settings)
            }
        }

        func offset(_ string: String) -> Int {
            let parts = string.split(separator: ":")
            let h = Int(parts.first ?? "0") ?? 0
            let m = Int(parts.last ?? "0") ?? 0
            return ((h * 60) + m) * 60
        }

        func saveError(_ string: String) {
            guard !string.isEmpty else { return }
            coredataContext.perform {
                let err = ImportError(context: self.coredataContext)
                err.date = Date()
                err.error = string
                try? self.coredataContext.save()
            }
            DispatchQueue.main.async { self.message = string }
        }

        func backfillGlucose() {
            backfilling = true
            backfillingProgress = 0.0
            nightscoutManager.fetchGlucose(
                since: Date().addingTimeInterval(-Int(backFillInterval).days.timeInterval),
                progress: { progress in
                    DispatchQueue.main.async {
                        self.backfillingProgress = progress
                    }
                }
            )
            .receive(on: processQueue)
            .map { glucose in
                let onePer5Min = self.glucoseStorage.filterFrequentGlucose(glucose, interval: TimeInterval(minutes: 4.5))
                debug(.nightscout, "fetched \(glucose.count) (filtered: \(onePer5Min.count)) glucose records from nightscout")
                return onePer5Min
            }
            .sink { [weak self] glucose in
                guard let self = self else {
                    return
                }

                guard glucose.isNotEmpty else {
                    DispatchQueue.main.async {
                        self.backfilling = false
                    }
                    return
                }
                // glucose storage - store only last 24 hours
                let cutOffDate = Date().addingTimeInterval(-1.days.timeInterval)
                let recent = glucose.filter { $0.dateString >= cutOffDate }
                _ = self.glucoseStorage.storeGlucose(recent)

                // core date - store everything
                coreDataStorageGlucoseSaver.storeGlucose(glucose) {
                    DispatchQueue.main.async {
                        self.backfilling = false
                    }
                }
            }
            .store(in: &lifetime)
        }

        func uploadOldGlucose() {
            uploading = true
            uploadingProgress = 0.0

            processQueue.async {
                let readings = CoreDataStorage()
                    .fetchGlucose(interval: Date().addingTimeInterval(-Int(self.uploadInterval).days.timeInterval) as NSDate)
                let bloodGlucose = readings.compactMap { reading -> BloodGlucose? in
                    guard let date = reading.date,
                          let id = reading.id
                    else {
                        return nil
                    }
                    return BloodGlucose(
                        _id: id,
                        sgv: Int(reading.glucose),
                        direction: nil,
                        date: Decimal(Int(date.timeIntervalSince1970 * 1000)),
                        dateString: date,
                        unfiltered: nil,
                        uncalibrated: nil,
                        filtered: nil,
                        noise: nil,
                        glucose: Int(reading.glucose),
                        type: "sgv",
                        activationDate: nil,
                        sessionStartDate: nil,
                        transmitterID: nil
                    )
                }

                self.nightscoutManager.uploadOldGlucose(
                    bloodGlucose: bloodGlucose,
                    completion: {
                        DispatchQueue.main.async {
                            self.uploading = false
                        }
                    },
                    progress: { progress in
                        DispatchQueue.main.async {
                            self.uploadingProgress = progress
                        }
                    }
                )
            }
        }

        func delete() {
            keychain.removeObject(forKey: Config.urlKey)
            keychain.removeObject(forKey: Config.secretKey)
            url = ""
            secret = ""
        }
    }
}
