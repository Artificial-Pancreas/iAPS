import CGMBLEKit
import Combine
import G7SensorKit
import SwiftDate
import SwiftUI

extension NightscoutConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var keychain: Keychain!
        @Injected() private var nightscoutManager: NightscoutManager!
        @Injected() private var glucoseStorage: GlucoseStorage!
        @Injected() private var healthKitManager: HealthKitManager!
        @Injected() private var cgmManager: FetchGlucoseManager!
        @Injected() private var storage: FileStorage!

        @Published var url = ""
        @Published var secret = ""
        @Published var message = ""
        @Published var connecting = false
        @Published var backfilling = false
        @Published var imported = false // Allow Setting Importss
        @Published var isUploadEnabled = false // Allow uploads
        @Published var uploadStats = false // Upload Statistics
        @Published var uploadGlucose = true // Upload Glucose
        @Published var useLocalSource = false
        @Published var localPort: Decimal = 0
        @Published var units: GlucoseUnits = .mmolL

        override func subscribe() {
            url = keychain.getValue(String.self, forKey: Config.urlKey) ?? ""
            secret = keychain.getValue(String.self, forKey: Config.secretKey) ?? ""
            units = settingsManager.settings.units

            subscribeSetting(\.isUploadEnabled, on: $isUploadEnabled) { isUploadEnabled = $0 }
            subscribeSetting(\.useLocalGlucoseSource, on: $useLocalSource) { useLocalSource = $0 }
            subscribeSetting(\.localGlucosePort, on: $localPort.map(Int.init)) { localPort = Decimal($0) }
            subscribeSetting(\.uploadStats, on: $uploadStats) { uploadStats = $0 }
            subscribeSetting(\.uploadGlucose, on: $uploadGlucose, initial: { uploadGlucose = $0 }, didSet: { val in
                if let cgmManagerG5 = self.cgmManager.glucoseSource.cgmManager as? G5CGMManager {
                    cgmManagerG5.shouldSyncToRemoteService = val
                }
                if let cgmManagerG6 = self.cgmManager.glucoseSource.cgmManager as? G6CGMManager {
                    cgmManagerG6.shouldSyncToRemoteService = val
                }
                if let cgmManagerG7 = self.cgmManager.glucoseSource.cgmManager as? G7CGMManager {
                    cgmManagerG7.uploadReadings = val
                }
            })
        }

        func connect() {
            guard let url = URL(string: url) else {
                message = "Invalid URL"
                return
            }
            connecting = true
            message = ""
            provider.checkConnection(url: url, secret: secret.isEmpty ? nil : secret)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished: break
                    case let .failure(error):
                        self.message = "Error: \(error.localizedDescription)"
                    }
                    self.connecting = false
                } receiveValue: {
                    self.message = "Connected!"
                    self.keychain.setValue(self.url, forKey: Config.urlKey)
                    self.keychain.setValue(self.secret, forKey: Config.secretKey)
                }
                .store(in: &lifetime)
        }

        private var nightscoutAPI: NightscoutAPI? {
            guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
                  let url = URL(string: urlString),
                  let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
            else {
                return nil
            }
            return NightscoutAPI(url: url, secret: secret)
        }

        func importSettings() {
            guard let nightscout = nightscoutAPI else {
                return
            }

            let path = "/api/v1/profile.json"
            let timeout: TimeInterval = 60

            var components = URLComponents()
            components.scheme = nightscout.url.scheme
            components.host = nightscout.url.host
            components.port = nightscout.url.port
            components.path = path
            components.queryItems = [
                URLQueryItem(name: "count", value: "1")
            ]

            var url = URLRequest(url: components.url!)
            url.allowsConstrainedNetworkAccess = false
            url.timeoutInterval = timeout

            if let secret = nightscout.secret {
                url.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
            }

            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    print("Error occured:", error)
                    // handle error
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      (200 ... 299).contains(httpResponse.statusCode)
                else {
                    print("Error occured!", error as Any)
                    // handle error
                    return
                }

                let jsonDecoder = JSONCoding.decoder

                if let mimeType = httpResponse.mimeType, mimeType == "application/json",
                   let data = data
                {
                    do {
                        let fetchedProfileStore = try jsonDecoder.decode([FetchedNightscoutProfileStore].self, from: data)
                        guard let fetchedProfile: ScheduledNightscoutProfile = fetchedProfileStore.first?.store["default"]
                        else { return }

                        guard fetchedProfile.units.contains(self.units.rawValue.prefix(4)) else {
                            debug(
                                .nightscout,
                                "Mismatching units Nightcosut/Pump Settings" + fetchedProfile.units + " " + self.units.rawValue +
                                ". Import settings aborted."
                            )
                            return
                        }

                        let carbratios = fetchedProfile.carbratio
                            .map { carbratio -> CarbRatioEntry in
                                CarbRatioEntry(
                                    start: carbratio.time,
                                    offset: carbratio.timeAsSeconds,
                                    ratio: carbratio.value
                                ) }
                        let carbratiosProfile = CarbRatios(units: CarbUnit.grams, schedule: carbratios)

                        let basals = fetchedProfile.basal
                            .map { basal -> BasalProfileEntry in
                                BasalProfileEntry(
                                    start: basal.time,
                                    minutes: basal.timeAsSeconds,
                                    rate: basal.value
                                ) }
                        let sensitivities = fetchedProfile.sens.map { sensitivity -> InsulinSensitivityEntry in
                            InsulinSensitivityEntry(
                                sensitivity: self.units == .mmolL ? sensitivity.value : sensitivity.value.asMgdL,
                                offset: sensitivity.timeAsSeconds,
                                start: sensitivity.time
                            ) }
                        let sensitivitiesProfile = InsulinSensitivities(
                            units: self.units,
                            userPrefferedUnits: self.units,
                            sensitivities: sensitivities
                        )

                        // iAPS does not have target ranges but a simple target glucose; targets will therefore adhere to target_low.value == target_high.value
                        // => this is the reasoning for only using target_low here
                        let targets = fetchedProfile.target_low
                            .map { target -> BGTargetEntry in
                                BGTargetEntry(
                                    low: self.units == .mmolL ? target.value : target.value.asMgdL,
                                    high: self.units == .mmolL ? target.value : target.value.asMgdL,
                                    start: target.time,
                                    offset: target.timeAsSeconds
                                ) }
                        let targetsProfile = BGTargets(
                            units: self.units,
                            userPrefferedUnits: self.units,
                            targets: targets
                        )

                        self.storage.save(carbratiosProfile, as: OpenAPS.Settings.carbRatios)
                        self.storage.save(basals, as: OpenAPS.Settings.basalProfile)
                        self.storage.save(sensitivitiesProfile, as: OpenAPS.Settings.insulinSensitivities)
                        self.storage.save(targetsProfile, as: OpenAPS.Settings.bgTargets)

                    } catch let parsingError {
                        print(parsingError)
                    }
                }
            }
            task.resume()
            imported = true
        }

        func saveSettings() {}

        func backfillGlucose() {
            backfilling = true
            nightscoutManager.fetchGlucose(since: Date().addingTimeInterval(-1.days.timeInterval))
                .sink { [weak self] glucose in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.backfilling = false
                    }

                    guard glucose.isNotEmpty else { return }
                    self.healthKitManager.saveIfNeeded(bloodGlucose: glucose)
                    self.glucoseStorage.storeGlucose(glucose)
                }
                .store(in: &lifetime)
        }

        func delete() {
            keychain.removeObject(forKey: Config.urlKey)
            keychain.removeObject(forKey: Config.secretKey)
            url = ""
            secret = ""
        }
    }
}
