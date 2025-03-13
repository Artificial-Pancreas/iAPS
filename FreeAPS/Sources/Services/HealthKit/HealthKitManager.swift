import Combine
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import Swinject

protocol HealthKitManager: GlucoseSource {
    /// Check all needed permissions
    /// Return false if one or more permissions are deny or not choosen
    var areAllowAllPermissions: Bool { get }
    /// Check availability to save data of BG type to Health store
    func checkAvailabilitySaveBG() -> Bool
    /// Requests user to give permissions on using HealthKit
    func requestPermission(completion: ((Bool, Error?) -> Void)?)
    /// Save blood glucose to Health store (dublicate of bg will ignore)
    func saveIfNeeded(bloodGlucose: [BloodGlucose])
    /// Save carbs to Health store (dublicate of bg will ignore)
    func saveIfNeeded(carbs: [CarbsEntry])
    /// Save Insulin to Health store
    func saveIfNeeded(pumpEvents events: [PumpHistoryEvent])
    /// Create observer for data passing beetwen Health Store and iAPS
    func createBGObserver()
    /// Enable background delivering objects from Apple Health to iAPS
    func enableBackgroundDelivery()
    /// Delete glucose with syncID
    func deleteGlucose(syncID: String)
    /// delete carbs with syncID
    func deleteCarbs(date: Date)
    /// delete insulin with syncID
    func deleteInsulin(syncID: String)
}

final class BaseHealthKitManager: HealthKitManager, Injectable, CarbsObserver, PumpHistoryObserver {
    private enum Config {
        // unwraped HKObjects
        static var readPermissions: Set<HKSampleType> {
            Set([healthBGObject].compactMap { $0 }) }

        static var writePermissions: Set<HKSampleType> {
            Set([healthBGObject, healthCarbObject, healthInsulinObject].compactMap { $0 }) }

        // link to object in HealthKit
        static let healthBGObject = HKObjectType.quantityType(forIdentifier: .bloodGlucose)
        static let healthCarbObject = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)
        static let healthInsulinObject = HKObjectType.quantityType(forIdentifier: .insulinDelivery)

        // Meta-data key of iAPS data in HealthStore
        static let freeAPSMetaKey = "From iAPS"
    }

    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var healthKitStore: HKHealthStore!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() var carbsStorage: CarbsStorage!

    private let processQueue = DispatchQueue(label: "BaseHealthKitManager.processQueue")
    private var lifetime = Lifetime()

    // BG that will be return Publisher
    @SyncAccess @Persisted(key: "BaseHealthKitManager.newGlucose") private var newGlucose: [BloodGlucose] = []

    // last anchor for HKAnchoredQuery
    private var lastBloodGlucoseQueryAnchor: HKQueryAnchor? {
        set {
            persistedBGAnchor = try? NSKeyedArchiver.archivedData(withRootObject: newValue as Any, requiringSecureCoding: false)
        }
        get {
            guard let data = persistedBGAnchor else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        }
    }

    @Persisted(key: "HealthKitManagerAnchor") private var persistedBGAnchor: Data? = nil

    var isAvailableOnCurrentDevice: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var areAllowAllPermissions: Bool {
        Set(Config.readPermissions.map { healthKitStore.authorizationStatus(for: $0) })
            .intersection([.notDetermined])
            .isEmpty &&
            Set(Config.writePermissions.map { healthKitStore.authorizationStatus(for: $0) })
            .intersection([.sharingDenied, .notDetermined])
            .isEmpty
    }

    // NSPredicate, which use during load increment BG from Health store
    private var loadBGPredicate: NSPredicate {
        // loading only daily bg
        let predicateByStartDate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-1.days.timeInterval),
            end: nil,
            options: .strictStartDate
        )

        // loading only not FreeAPS bg
        // this predicate dont influence on Deleted Objects, only on added
        let predicateByMeta = HKQuery.predicateForObjects(
            withMetadataKey: Config.freeAPSMetaKey,
            operatorType: .notEqualTo,
            value: 1
        )

        return NSCompoundPredicate(andPredicateWithSubpredicates: [predicateByStartDate, predicateByMeta])
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        guard isAvailableOnCurrentDevice,
              Config.healthBGObject != nil else { return }
        createBGObserver()
        enableBackgroundDelivery()

        broadcaster.register(CarbsObserver.self, observer: self)
        broadcaster.register(PumpHistoryObserver.self, observer: self)

        debug(.service, "HealthKitManager did create")
    }

    func checkAvailabilitySave(objectTypeToHealthStore: HKObjectType) -> Bool {
        healthKitStore.authorizationStatus(for: objectTypeToHealthStore) == .sharingAuthorized
    }

    func checkAvailabilitySaveBG() -> Bool {
        Config.healthBGObject.map { checkAvailabilitySave(objectTypeToHealthStore: $0) } ?? false
    }

    func requestPermission(completion: ((Bool, Error?) -> Void)? = nil) {
        guard isAvailableOnCurrentDevice else {
            completion?(false, HKError.notAvailableOnCurrentDevice)
            return
        }
        guard Config.readPermissions.isNotEmpty, Config.writePermissions.isNotEmpty else {
            completion?(false, HKError.dataNotAvailable)
            return
        }

        healthKitStore.requestAuthorization(toShare: Config.writePermissions, read: Config.readPermissions) { status, error in
            completion?(status, error)
        }
    }

    func saveIfNeeded(bloodGlucose: [BloodGlucose]) {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = Config.healthBGObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType),
              bloodGlucose.isNotEmpty
        else { return }

        func save(samples: [HKSample]) {
            let sampleIDs = samples.compactMap(\.syncIdentifier)
            let samplesToSave = bloodGlucose
                .filter { !sampleIDs.contains($0.id) }
                .map {
                    HKQuantitySample(
                        type: sampleType,
                        quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double($0.glucose ?? 0)),
                        start: $0.dateString,
                        end: $0.dateString,
                        metadata: [
                            HKMetadataKeyExternalUUID: $0.id,
                            HKMetadataKeySyncIdentifier: $0.id,
                            HKMetadataKeySyncVersion: 1,
                            Config.freeAPSMetaKey: true
                        ]
                    )
                }
            healthKitStore.save(samplesToSave) { (success: Bool, error: Error?) -> Void in
                if !success, let error = error {
                    debug(.service, "Failed to store blood glucose in HealthKit Store! Error: " + error.localizedDescription)
                }
            }
        }

        loadSamplesFromHealth(sampleType: sampleType, withIDs: bloodGlucose.map(\.id))
            .receive(on: processQueue)
            .sink(receiveValue: save)
            .store(in: &lifetime)
    }

    func saveIfNeeded(carbs: [CarbsEntry]) {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = Config.healthCarbObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType),
              carbs.isNotEmpty
        else { return }

        let carbsWithId = carbs.filter { c in
            guard c.id != nil else { return false }
            return true
        }

        func save(samples: [HKSample]) {
            let sampleIDs = samples.compactMap(\.syncIdentifier)
            let sampleDates = samples.map(\.startDate)
            let samplesToSave = carbsWithId
                .filter { !sampleIDs.contains($0.id ?? "") } // id existing in AH
                .filter { !sampleDates.contains($0.actualDate ?? $0.createdAt) } // not id but exactly the same datetime
                .map {
                    HKQuantitySample(
                        type: sampleType,
                        quantity: HKQuantity(unit: .gram(), doubleValue: Double($0.carbs)),
                        start: $0.actualDate ?? $0.createdAt,
                        end: $0.actualDate ?? $0.createdAt,
                        metadata: [
                            HKMetadataKeyExternalUUID: "\($0.createdAt)",
                            HKMetadataKeySyncIdentifier: $0.id ?? "_id",
                            HKMetadataKeySyncVersion: 1,
                            Config.freeAPSMetaKey: true
                        ]
                    )
                }

            healthKitStore.save(samplesToSave) { (success: Bool, error: Error?) -> Void in
                if !success, let error = error {
                    debug(.service, "Failed to store carb entry in HealthKit Store! Error: " + error.localizedDescription)
                }
            }
        }

        loadSamplesFromHealth(sampleType: sampleType)
            .receive(on: processQueue)
            .sink(receiveValue: save)
            .store(in: &lifetime)
    }

    func saveIfNeeded(pumpEvents events: [PumpHistoryEvent]) {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = Config.healthInsulinObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType),
              events.isNotEmpty
        else { return }

        func delete(syncIds: [String]?) {
            syncIds?.forEach { syncID in
                let predicate = HKQuery.predicateForObjects(
                    withMetadataKey: HKMetadataKeySyncIdentifier,
                    operatorType: .equalTo,
                    value: syncID
                )

                self.healthKitStore.deleteObjects(of: sampleType, predicate: predicate) { _, _, error in
                    if let error = error {
                        warning(.service, "Cannot delete sample with syncID: \(syncID)", error: error)
                    }
                }
            }
        }

        func save(bolus: [InsulinBolus], basal: [InsulinBasal]) {
            let bolusSamples = bolus
                .map {
                    HKQuantitySample(
                        type: sampleType,
                        quantity: HKQuantity(unit: .internationalUnit(), doubleValue: Double($0.amount)),
                        start: $0.date,
                        end: $0.date,
                        metadata: [
                            HKMetadataKeyInsulinDeliveryReason: NSNumber(2),
                            HKMetadataKeyExternalUUID: NSString(string: $0.id),
                            HKMetadataKeySyncIdentifier: NSString(string: $0.id),
                            HKMetadataKeySyncVersion: 1,
                            Config.freeAPSMetaKey: true
                        ]
                    )
                }

            let basalSamples = basal
                .map {
                    HKQuantitySample(
                        type: sampleType,
                        quantity: HKQuantity(unit: .internationalUnit(), doubleValue: Double($0.amount)),
                        start: $0.startDelivery,
                        end: $0.endDelivery,
                        metadata: [
                            HKMetadataKeyInsulinDeliveryReason: NSNumber(1),
                            HKMetadataKeyExternalUUID: NSString(string: $0.id),
                            HKMetadataKeySyncIdentifier: NSString(string: $0.id),
                            HKMetadataKeySyncVersion: 1,
                            Config.freeAPSMetaKey: true
                        ]
                    )
                }

            healthKitStore.save(bolusSamples + basalSamples) { (success: Bool, error: Error?) -> Void in
                if !success, let error = error {
                    debug(.service, "Failed to store insulin entry in HealthKit Store! Error: " + error.localizedDescription)
                }
            }
        }
        // delete existing event in HK where the amount is not the last value in the pumphistory
        loadSamplesFromHealth(sampleType: sampleType, withIDs: events.map(\.id))
            .receive(on: processQueue)
            .compactMap { samples -> [String] in
                let sampleIDs = samples.compactMap(\.syncIdentifier)
                let bolusToDelete = events
                    .filter { $0.type == .bolus && sampleIDs.contains($0.id) }
                    .compactMap { event -> String? in
                        guard let amount = event.amount else { return nil }
                        guard let sampleAmount = samples.first(where: { $0.syncIdentifier == event.id }) as? HKQuantitySample
                        else { return nil }
                        if Double(amount) != sampleAmount.quantity.doubleValue(for: .internationalUnit()) {
                            return sampleAmount.syncIdentifier
                        } else { return nil }
                    }
                return bolusToDelete
            }
            .sink(receiveValue: delete)
            .store(in: &lifetime)

        loadSamplesFromHealth(sampleType: sampleType, withIDs: events.map(\.id))
            .receive(on: processQueue)
            .compactMap { samples -> ([InsulinBolus], [InsulinBasal]) in
                let sampleIDs = samples.compactMap(\.syncIdentifier)
                let bolus = events
                    .filter { $0.type == .bolus && !sampleIDs.contains($0.id) }
                    .compactMap { event -> InsulinBolus? in
                        guard let amount = event.amount else { return nil }
                        return InsulinBolus(id: event.id, amount: amount, date: event.timestamp)
                    }
                let basalEvents = events
                    .filter { $0.type == .tempBasal && !sampleIDs.contains($0.id) }
                    .sorted(by: { $0.timestamp < $1.timestamp })
                let basal = basalEvents.enumerated()
                    .compactMap { item -> InsulinBasal? in
                        let nextElementEventIndex = item.offset + 1
                        guard basalEvents.count > nextElementEventIndex else { return nil }

                        var minimalDose = self.settingsManager.preferences.bolusIncrement
                        if (minimalDose != 0.05) || (minimalDose != 0.025) {
                            minimalDose = Decimal(0.05)
                        }

                        let nextBasalEvent = basalEvents[nextElementEventIndex]
                        let secondsOfCurrentBasal = nextBasalEvent.timestamp.timeIntervalSince(item.element.timestamp)
                        let amount = Decimal(secondsOfCurrentBasal / 3600) * (item.element.rate ?? 0)
                        let incrementsRaw = amount / minimalDose

                        var amountRounded: Decimal
                        if incrementsRaw >= 1 {
                            let incrementsRounded = floor(Double(incrementsRaw))
                            amountRounded = Decimal(round(incrementsRounded * Double(minimalDose) * 100_000.0) / 100_000.0)
                        } else {
                            amountRounded = 0
                        }

                        let id = String(item.element.id.dropFirst())
                        guard amountRounded > 0,
                              id != ""
                        else { return nil }

                        return InsulinBasal(
                            id: id,
                            amount: amountRounded,
                            startDelivery: item.element.timestamp,
                            endDelivery: nextBasalEvent.timestamp
                        )
                    }
                return (bolus, basal)
            }
            .sink(receiveValue: save)
            .store(in: &lifetime)
    }

    func pumpHistoryDidUpdate(_ events: [PumpHistoryEvent]) {
        saveIfNeeded(pumpEvents: events)
    }

    func createBGObserver() {
        guard settingsManager.settings.useAppleHealth else { return }

        guard let bgType = Config.healthBGObject else {
            warning(.service, "Can not create HealthKit Observer, because unable to get the Blood Glucose type")
            return
        }

        let query = HKObserverQuery(sampleType: bgType, predicate: nil) { [weak self] _, _, observerError in
            guard let self = self else { return }
            debug(.service, "Execute HealthKit observer query for loading increment samples")
            guard observerError == nil else {
                warning(.service, "Error during execution of HealthKit Observer's query", error: observerError!)
                return
            }

            if let incrementQuery = self.getBloodGlucoseHKQuery(predicate: self.loadBGPredicate) {
                debug(.service, "Create increment query")
                self.healthKitStore.execute(incrementQuery)
            }
        }
        healthKitStore.execute(query)
        debug(.service, "Create Observer for Blood Glucose")
    }

    func enableBackgroundDelivery() {
        guard settingsManager.settings.useAppleHealth else {
            healthKitStore.disableAllBackgroundDelivery { _, _ in }
            return }

        guard let bgType = Config.healthBGObject else {
            warning(
                .service,
                "Can not create background delivery, because unable to get the Blood Glucose type"
            )
            return
        }

        healthKitStore.enableBackgroundDelivery(for: bgType, frequency: .immediate) { status, error in
            guard error == nil else {
                warning(.service, "Can not enable background delivery", error: error)
                return
            }
            debug(.service, "Background delivery status is \(status)")
        }
    }

    /// Try to load samples from Health store
    private func loadSamplesFromHealth(
        sampleType: HKQuantityType
    ) -> Future<[HKSample], Never> {
        Future { promise in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: nil,
                limit: 100,
                sortDescriptors: nil
            ) { _, results, _ in
                promise(.success((results as? [HKQuantitySample]) ?? []))
            }
            self.healthKitStore.execute(query)
        }
    }

    /// Try to load samples from Health store with id and do some work
    private func loadSamplesFromHealth(
        sampleType: HKQuantityType,
        withIDs ids: [String]
    ) -> Future<[HKSample], Never> {
        Future { promise in
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeySyncIdentifier,
                allowedValues: ids
            )

            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: 100,
                sortDescriptors: nil
            ) { _, results, _ in
                promise(.success((results as? [HKQuantitySample]) ?? []))
            }
            self.healthKitStore.execute(query)
        }
    }

    private func getBloodGlucoseHKQuery(predicate: NSPredicate) -> HKQuery? {
        guard let sampleType = Config.healthBGObject else { return nil }

        let query = HKAnchoredObjectQuery(
            type: sampleType,
            predicate: predicate,
            anchor: lastBloodGlucoseQueryAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, addedObjects, _, anchor, _ in
            guard let self = self else { return }
            self.processQueue.async {
                debug(.service, "AnchoredQuery did execute")

                self.lastBloodGlucoseQueryAnchor = anchor

                // Added objects
                if let bgSamples = addedObjects as? [HKQuantitySample],
                   bgSamples.isNotEmpty
                {
                    self.prepareBGSamplesToPublisherFetch(bgSamples)
                }
            }
        }
        return query
    }

    private func prepareBGSamplesToPublisherFetch(_ samples: [HKQuantitySample]) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.service, "Start preparing samples: \(String(describing: samples))")

        newGlucose += samples
            .compactMap { sample -> HealthKitSample? in
                let fromiAPS = sample.metadata?[Config.freeAPSMetaKey] as? Bool ?? false
                guard !fromiAPS else { return nil }
                return HealthKitSample(
                    healthKitId: sample.uuid.uuidString,
                    date: sample.startDate,
                    glucose: Int(round(sample.quantity.doubleValue(for: .milligramsPerDeciliter)))
                )
            }
            .map { sample in
                BloodGlucose(
                    _id: sample.healthKitId,
                    sgv: sample.glucose,
                    direction: nil,
                    date: Decimal(Int(sample.date.timeIntervalSince1970) * 1000),
                    dateString: sample.date,
                    unfiltered: Decimal(sample.glucose),
                    filtered: nil,
                    noise: nil,
                    glucose: sample.glucose,
                    type: "sgv"
                )
            }
            .filter { $0.dateString >= Date().addingTimeInterval(-1.days.timeInterval) }

        newGlucose = newGlucose.removeDublicates()

        debug(
            .service,
            "Current BloodGlucose.Type objects will be send from Publisher during fetch: \(String(describing: newGlucose))"
        )
    }

    // MARK: - GlucoseSource

    var glucoseManager: FetchGlucoseManager?
    var cgmManager: CGMManagerUI?
    var cgmType: CGMType = .nightscout

    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        Future { [weak self] promise in
            guard let self = self else {
                promise(.success([]))
                return
            }

            self.processQueue.async {
                guard self.settingsManager.settings.useAppleHealth else {
                    promise(.success([]))
                    return
                }

                // Remove old BGs
                self.newGlucose = self.newGlucose
                    .filter { $0.dateString >= Date().addingTimeInterval(-1.days.timeInterval) }
                // Get actual BGs (beetwen Date() - 1 day and Date())
                let actualGlucose = self.newGlucose
                    .filter { $0.dateString <= Date() }
                // Update newGlucose
                self.newGlucose = self.newGlucose
                    .filter { !actualGlucose.contains($0) }
                promise(.success(actualGlucose))
            }
        }
        .eraseToAnyPublisher()
    }

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        fetch(nil)
    }

    func deleteGlucose(syncID: String) {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = Config.healthBGObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType)
        else { return }

        processQueue.async {
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeySyncIdentifier,
                operatorType: .equalTo,
                value: syncID
            )

            self.healthKitStore.deleteObjects(of: sampleType, predicate: predicate) { success, int, error in
                if let error = error {
                    warning(.service, "Cannot delete sample with syncID: \(syncID)", error: error)
                } else if success {
                    debug(.service, "\(int) glucose entries deleted from Health Store", printToConsole: true)
                }
            }
        }
    }

    // - MARK Carbs function

    func deleteCarbs(date: Date) {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = Config.healthCarbObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType)
        else { return }

        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            operatorType: .equalTo,
            value: "\(date)"
        )

        healthKitStore.deleteObjects(of: sampleType, predicate: predicate) { success, int, error in
            if let error = error {
                warning(.service, "Cannot delete sample with date: \(date)", error: error)
            } else if success {
                debug(.service, "\(int) carb entries with date: \(date) deleted from Health Store", printToConsole: true)
            }
        }
    }

    func carbsDidUpdate(_ carbs: [CarbsEntry]) {
        saveIfNeeded(carbs: carbs)
    }

    // - MARK Insulin function

    func deleteInsulin(syncID: String) {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = Config.healthInsulinObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType)
        else { return }

        processQueue.async {
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeySyncIdentifier,
                operatorType: .equalTo,
                value: syncID
            )

            self.healthKitStore.deleteObjects(of: sampleType, predicate: predicate) { success, int, error in
                if let error = error {
                    warning(.service, "Cannot delete sample with syncID: \(syncID)", error: error)
                } else if success {
                    debug(.service, "\(int) insulin entries with ID: \(syncID) deleted from Health Store", printToConsole: true)
                }
            }
        }
    }
}

enum HealthKitPermissionRequestStatus {
    case needRequest
    case didRequest
}

enum HKError: Error {
    // HealthKit work only iPhone (not on iPad)
    case notAvailableOnCurrentDevice
    // Some data can be not available on current iOS-device
    case dataNotAvailable
}

private struct InsulinBolus {
    var id: String
    var amount: Decimal
    var date: Date
}

private struct InsulinBasal {
    var id: String
    var amount: Decimal
    var startDelivery: Date
    var endDelivery: Date
}
