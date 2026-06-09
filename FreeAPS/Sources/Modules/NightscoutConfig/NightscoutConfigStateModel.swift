import CGMBLEKit
import Combine
import CoreData
import G7SensorKit
import LoopKit
import SwiftUI

extension NightscoutConfig {
    final class StateModel: BaseStateModel<Provider>, LifetimeOwner {
        @Injected() private var keychain: Keychain!
        @Injected() private var nightscoutManager: NightscoutManager!
        @Injected() private var glucoseStorage: GlucoseStorage!
        @Injected() private var storage: FileStorage!
        @Injected() private var coreDataStorageGlucoseSaver: CoreDataStorageGlucoseSaver!
        @Injected() private var apsManager: APSManager!
        @Injected() private var deviceManager: DeviceDataManager!
        @Injected() private var appCoordinator: AppCoordinator!

        private let coredataContext = CoreDataStack.shared.persistentContainer.viewContext
        private let coreDataStorage = CoreDataStorage()

        @Published var url = ""
        @Published var secret = ""
        @Published var message = ""
        @Published var connecting = false
        @Published var backfilling = false
        @Published var backfillingProgress = 0.0
        @Published var uploading = false
        @Published var uploadingProgress = 0.0
        @Published var isUploadEnabled = false // Allow uploads
        @Published var nightscoutFetchEnabled = true // Allow fetch
        @Published var units: GlucoseUnits = .mmolL
        @Published var dia: Decimal = 6
        @Published var maxBasal: Decimal = 4
        @Published var maxBolus: Decimal = 10
        @Published var allowAnnouncements: Bool = false
        @Published var backFillInterval: Decimal = 1 {
            didSet {
                let clamped = min(max(backFillInterval, 1), 90)
                if backFillInterval != clamped {
                    backFillInterval = clamped
                }
            }
        }

        @Published var uploadInterval: Decimal = 1 {
            didSet {
                let clamped = min(max(uploadInterval, 1), 90)
                if uploadInterval != clamped {
                    uploadInterval = clamped
                }
            }
        }

        @Published var cgmSupportsGlucoseUpload: Bool = false
        @Published var cgmEnablesGlucoseUpload: Bool = false
        @Published var cgmDisablesGlucoseUpload: Bool = false

        override func subscribe() async {
            url = keychain.getValue(String.self, forKey: Config.urlKey) ?? ""
            secret = keychain.getValue(String.self, forKey: Config.secretKey) ?? ""

            let settings = await settingsManager.settings
            let pumpSettings = await settingsManager.pumpSettings

            units = settings.units
            dia = pumpSettings.insulinActionCurve
            maxBasal = pumpSettings.maxBasal
            maxBolus = pumpSettings.maxBolus

            updatedShouldUploadGlucose()

            subscribeSetting(\.allowAnnouncements, on: $allowAnnouncements) { self.allowAnnouncements = $0 }
            subscribeSetting(\.isUploadEnabled, on: $isUploadEnabled) { self.isUploadEnabled = $0 }
            subscribeSetting(\.nightscoutFetchEnabled, on: $nightscoutFetchEnabled) { self.nightscoutFetchEnabled = $0 }

            observe(appCoordinator.cgmInfo) { me, _ in
                await me.updatedShouldUploadGlucose()
            }
            observe(appCoordinator.cgmStatus) { me, _ in
                await me.updatedShouldUploadGlucose()
            }
        }

        private func updatedShouldUploadGlucose() {
            guard let cgmInfo = appCoordinator.cgmInfo.value,
                  let cgmStatus = appCoordinator.cgmStatus.value
            else {
                cgmSupportsGlucoseUpload = false
                cgmEnablesGlucoseUpload = false
                cgmDisablesGlucoseUpload = false
                return
            }
            cgmSupportsGlucoseUpload = cgmInfo.glucoseUploadSupported
            cgmEnablesGlucoseUpload = cgmStatus.shouldUploadGlucose
            cgmDisablesGlucoseUpload = cgmInfo.glucoseUploadSupported && !cgmStatus.shouldUploadGlucose
        }

        func connect() {
            if let CheckURL = url.last, CheckURL == "/" {
                let fixedURL = url.dropLast()
                url = String(fixedURL)
            }
            guard let url = URL(string: url) else {
                message = "Invalid URL"
                return
            }
            connecting = true
            message = ""
            Task {
                do {
                    try await NightscoutAPI(url: url, secret: secret.isEmpty ? nil : secret).checkConnection()
                    self.message = "Connected!"
                    self.keychain.setValue(self.url, forKey: Config.urlKey)
                    self.keychain.setValue(self.secret, forKey: Config.secretKey)
                } catch {
                    self.message = "Error: \(error.localizedDescription)"
                }
                connecting = false
            }
        }

        private func readConcentration() -> Double {
            coreDataStorage.insulinConcentration().concentration
        }

        func importSettings() {
            Task {
                guard await nightscoutManager.isConfigured() else {
                    saveError("Can't access nightscoutAPI")
                    return
                }
                let pumpInfo = self.appCoordinator.pumpInfo.value

                let fetchedProfileStore: [FetchedNightscoutProfileStore]
                do {
                    fetchedProfileStore = try await self.nightscoutManager.fetchProfile()
                } catch let importError {
                    debug(.nightscout, "Error occured: " + importError.localizedDescription)
                    saveError("Error occurred: " + importError.localizedDescription)
                    return
                }

                guard let fetchedProfile: ScheduledNightscoutProfile = fetchedProfileStore.first?.store["default"]
                else {
                    saveError("\nCan't find the default Nightscout Profile.")
                    return
                }

                guard fetchedProfile.units.contains(self.units.rawValue.prefix(4)) else {
                    debug(
                        .nightscout,
                        "Mismatching glucose units in Nightscout and Pump Settings. Import settings aborted."
                    )
                    saveError("\nMismatching glucose units in Nightscout and Pump Settings. Import settings aborted.")
                    return
                }

                var areCRsOK = true
                let carbratios = fetchedProfile.carbratio
                    .map { carbratio -> CarbRatioEntry in
                        if carbratio.value <= 0 {
                            areCRsOK = false
                        }
                        return CarbRatioEntry(
                            start: carbratio.time,
                            offset: self.offset(carbratio.time) / 60,
                            ratio: carbratio.value
                        )
                    }
                let carbratiosProfile = CarbRatios(units: CarbUnit.grams, schedule: carbratios)
                guard areCRsOK else {
                    saveError(
                        "\nInvalid Carb Ratio settings in Nightscout.\n\nImport aborted. Please check your Nightscout Profile Carb Ratios Settings!"
                    )
                    return
                }

                var areBasalsOK = true
                let pumpName = pumpInfo?.name
                let basals = fetchedProfile.basal
                    .map { basal -> BasalProfileEntry in
                        if pumpName != "Omnipod DASH", basal.value <= 0
                        {
                            areBasalsOK = false
                        }
                        return BasalProfileEntry(
                            start: basal.time,
                            minutes: self.offset(basal.time) / 60,
                            rate: basal.value
                        )
                    }

                guard areBasalsOK else {
                    saveError(
                        "\nInvalid Nightcsout Basal Settings. Some or all of your basal settings are 0 U/h.\n\nImport aborted. Please check your Nightscout Profile Basal Settings before trying to import again. Import has been aborted.)"
                    )
                    return
                }

                // DASH pumps can have 0U/h basal rates but don't import if total basals (24 hours) amount to 0 U.
                if pumpName == "Omnipod DASH", basals.map({ each in each.rate }).reduce(0, +) <= 0 {
                    areBasalsOK = false
                }
                guard areBasalsOK else {
                    saveError(
                        "\nYour total Basal insulin amount to 0 U or lower in Nightscout Profile settings.\n\n Please check your Nightscout Profile Basal Settings before trying to import again. Import has been aborted.)"
                    )
                    return
                }

                let sensitivities = fetchedProfile.sens.map { sensitivity -> InsulinSensitivityEntry in
                    InsulinSensitivityEntry(
                        sensitivity: sensitivity.value,
                        offset: self.offset(sensitivity.time) / 60,
                        start: sensitivity.time
                    )
                }
                if sensitivities.filter({ $0.sensitivity <= 0 }).isNotEmpty {
                    saveError(
                        "\nInvalid Nightcsout Sensitivities Settings. \n\nImport aborted. Please check your Nightscout Profile Sensitivities Settings!"
                    )
                    return
                }

                let sensitivitiesProfile = InsulinSensitivities(
                    units: self.units,
                    userPrefferedUnits: self.units,
                    sensitivities: sensitivities
                )

                let targets = fetchedProfile.target_low
                    .map { target -> BGTargetEntry in
                        BGTargetEntry(
                            low: target.value,
                            high: target.value,
                            start: target.time,
                            offset: self.offset(target.time) / 60
                        )
                    }

                let targetsProfile = BGTargets(
                    units: self.units,
                    userPrefferedUnits: self.units,
                    targets: targets
                )

                // IS THERE A PUMP?
                guard pumpInfo != nil else {
                    await self.storage.save(carbratiosProfile, as: OpenAPS.Settings.carbRatios)
                    await self.storage.save(basals, as: OpenAPS.Settings.basalProfile)
                    await self.storage.save(sensitivitiesProfile, as: OpenAPS.Settings.insulinSensitivities)
                    await self.storage.save(targetsProfile, as: OpenAPS.Settings.bgTargets)
                    let error =
                        "Settings were imported but the Basals couldn't be saved to pump (No pump). Check your basal settings and tap ´Save on Pump´ to sync the new basal settings"
                    debug(.service, error)
                    saveError(error)
                    return
                }

                // SAVE TO STORAGE. SAVE TO PUMP (LoopKit)
                let concentration = readConcentration()
                do {
                    if let adjustedBasals = try await deviceManager.syncBasalRateSchedule(
                        items: basals,
                        concentration: concentration
                    ) {
                        await self.storage.save(adjustedBasals, as: OpenAPS.Settings.basalProfile)
                    } else {
                        await self.storage.save(basals, as: OpenAPS.Settings.basalProfile)
                    }
                    await self.storage.save(carbratiosProfile, as: OpenAPS.Settings.carbRatios)
                    await self.storage.save(sensitivitiesProfile, as: OpenAPS.Settings.insulinSensitivities)
                    await self.storage.save(targetsProfile, as: OpenAPS.Settings.bgTargets)
                    debug(.service, "Settings have been imported and the Basals saved to pump!")
                    // DIA. Save if changed.
                    let dia = fetchedProfile.dia
                    if dia != self.dia, dia >= 0 {
                        let pumpSettings = PumpSettings(
                            insulinActionCurve: dia,
                            maxBolus: self.maxBolus,
                            maxBasal: self.maxBasal
                        )
                        await self.settingsManager.updatePumpSettings(pumpSettings)
                        debug(.nightscout, "DIA setting updated to " + dia.description + " after a NS import.")
                    }

                } catch {
                    let error =
                        "\nSettings were imported but the Basals couldn't be saved to pump (communication error). Check your basal settings and tap ´Save on Pump´ to sync the new basal settings"
                    saveError(error)
                    debug(.service, "Basals couldn't be save to pump: \(error)")
                }
            }
        }

        private func offset(_ string: String) -> Int {
            let hours = Int(string.prefix(2)) ?? 0
            let minutes = Int(string.suffix(2)) ?? 0
            return ((hours * 60) + minutes) * 60
        }

        private func saveError(_ string: String) {
            coredataContext.performAndWait {
                let saveToCoreData = ImportError(context: self.coredataContext)
                saveToCoreData.date = Date()
                saveToCoreData.error = string
                if coredataContext.hasChanges {
                    try? coredataContext.save()
                }
            }
        }

        func backfillGlucose() {
            backfilling = true
            backfillingProgress = 0.0
            Task {
                defer { backfilling = false }
                let since = Date.now.removingTimeInterval(.days(backFillInterval))
                for await progress in await nightscoutManager.fetchGlucose(since: since) {
                    switch progress {
                    case let .progress(progress):
                        self.backfillingProgress = progress
                    case let .done(glucose):
                        await storeBackfilledGlucose(glucose)
                    }
                }
            }
        }

        private func storeBackfilledGlucose(_ glucose: [BloodGlucose]) async {
            let onePer5Min = FrequentGlucoseFiltering.filterFrequentGlucose(glucose, interval: .minutes(4.5))
            debug(.nightscout, "fetched \(glucose.count) (filtered: \(onePer5Min.count)) glucose records from nightscout")

            guard glucose.isNotEmpty else { return }

            // glucose storage - store only last 24 hours
            let cutOffDate = Date.now.removingTimeInterval(.hours(24))
            let recent = glucose.filter { $0.dateString >= cutOffDate }
            _ = await glucoseStorage.storeGlucose(recent)

            // core data - store everything
            await coreDataStorageGlucoseSaver.storeGlucose(glucose)
        }

        func uploadOldGlucose() {
            uploading = true
            uploadingProgress = 0.0

            Task {
                let readings = CoreDataStorage()
                    .fetchGlucose(interval: Date.now.removingTimeInterval(.days(self.uploadInterval)) as NSDate)
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

                for await progress in await self.nightscoutManager.uploadOldGlucose(bloodGlucose: bloodGlucose) {
                    self.uploadingProgress = progress
                }
                self.uploading = false
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
