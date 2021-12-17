import Combine
import Foundation
import HealthKit
import Swinject

protocol HealthKitManager: GlucoseSource {
    /// Check availability HealthKit on current device and user's permissions
    var isAvailableOnCurrentDevice: Bool { get }
    /// Check all needed permissions
    /// Return false if one or more permissions are deny or not choosen
    var areAllowAllPermissions: Bool { get }
    /// Check availability to save data of concrete type to Health store
    func checkAvailabilitySave(objectTypeToHealthStore: HKObjectType) -> Bool
    func checkAvailabilitySaveBG() -> Bool
    /// Requests user to give permissions on using HealthKit
    func requestPermission(completion: ((Bool, Error?) -> Void)?)
    /// Save blood glucose to Health store (dublicate of bg will ignore)
    func saveIfNeeded(bloodGlucoses: [BloodGlucose])
    /// Create observer for data passing beetwen Health Store and FreeAPS
    func createObserver()
    /// Enable background delivering objects from Apple Health to FreeAPS
    func enableBackgroundDelivery()
}

final class BaseHealthKitManager: HealthKitManager, Injectable {
    @Injected() private var fileStorage: FileStorage!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var healthKitStore: HKHealthStore!
    @Injected() private var settingsManager: SettingsManager!

    private let queue = DispatchQueue(label: "debugInfoQueue")
    private var lock = NSLock(label: "helathKitExecureQueryLock")

    private enum Config {
        // unwraped HKObjects
        static var permissions: Set<HKSampleType> {
            var result: Set<HKSampleType> = []
            for permission in optionalPermissions {
                result.insert(permission!)
            }
            return result
        }

        static let optionalPermissions = Set([Config.healthBGObject])
        // link to object in HealthKit
        static let healthBGObject = HKObjectType.quantityType(forIdentifier: .bloodGlucose)

        static let frequencyBackgroundDeliveryBloodGlucoseFromHealth = HKUpdateFrequency(rawValue: 1)!
        // Meta-data key of FreeASPX data in HealthStore
        static let freeAPSMetaKey = "fromFreeAPSX"
    }

    // BG that will be return Publisher
    @Persisted(key: "HealthKitManagerNewGlucose") private var newGlucose: [BloodGlucose] = []

    // last anchor for HKAnchoredQuery
    private var lastBloodGlucoseQueryAnchor: HKQueryAnchor! {
        set {
            guard let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue as Any, requiringSecureCoding: false)
            else {
                persistedAnchor = Data()
                return
            }
            persistedAnchor = data
        }
        get {
            guard let result = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(persistedAnchor) as? HKQueryAnchor else {
                return HKQueryAnchor(fromValue: 0)
            }
            return result
        }
    }

    @Persisted(key: "HealthKitManagerAnchor") private var persistedAnchor = Data()

    var isAvailableOnCurrentDevice: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var areAllowAllPermissions: Bool {
        var result = true
        Config.permissions.forEach { permission in
            if [HKAuthorizationStatus.sharingDenied, HKAuthorizationStatus.notDetermined]
                .contains(healthKitStore.authorizationStatus(for: permission))
            {
                result = false
            }
        }
        return result
    }

    // NSPredicate, which use during load increment BG from Health store
    private lazy var loadBGPredicate: NSPredicate = {
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
    }()

    init(resolver: Resolver) {
        injectServices(resolver)
        guard isAvailableOnCurrentDevice,
              Config.healthBGObject != nil else { return }
        createObserver()
        enableBackgroundDelivery()
        debug(.service, "HealthKitManager did create")
    }

    func checkAvailabilitySave(objectTypeToHealthStore: HKObjectType) -> Bool {
        let status = healthKitStore.authorizationStatus(for: objectTypeToHealthStore)
        switch status {
        case .sharingAuthorized:
            return true
        default:
            return false
        }
    }

    func checkAvailabilitySaveBG() -> Bool {
        guard let sampleType = Config.healthBGObject else {
            return false
        }
        return checkAvailabilitySave(objectTypeToHealthStore: sampleType)
    }

    func requestPermission(completion: ((Bool, Error?) -> Void)? = nil) {
        guard isAvailableOnCurrentDevice else {
            completion?(false, HKError.notAvailableOnCurrentDevice)
            return
        }
        for permission in Config.optionalPermissions {
            guard permission != nil else {
                completion?(false, HKError.dataNotAvailable)
                return
            }
        }

        healthKitStore.requestAuthorization(toShare: Config.permissions, read: Config.permissions) { status, error in
            completion?(status, error)
        }
    }

    func saveIfNeeded(bloodGlucoses: [BloodGlucose]) {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = Config.healthBGObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType),
              bloodGlucoses.isNotEmpty
        else { return }

        for bgItem in bloodGlucoses {
            let bgQuantity = HKQuantity(
                unit: .milligramsPerDeciliter,
                doubleValue: Double(bgItem.glucose!)
            )

            let bgObjectSample = HKQuantitySample(
                type: sampleType,
                quantity: bgQuantity,
                start: bgItem.dateString,
                end: bgItem.dateString,
                metadata: [
                    HKMetadataKeyExternalUUID: bgItem.id,
                    HKMetadataKeySyncIdentifier: bgItem.id,
                    HKMetadataKeySyncVersion: 1,
                    Config.freeAPSMetaKey: true
                ]
            )
            load(sampleFromHealth: sampleType, withID: bgItem.id) { [weak self] samples in
                if samples.isEmpty {
                    self?.healthKitStore.save(bgObjectSample) { _, _ in }
                }
            }
        }
    }

    func createObserver() {
        guard settingsManager.settings.useAppleHealth else { return }

        guard let bgType = Config.healthBGObject else {
            warning(
                .service,
                "Can not create HealthKit Observer, because unable to get the Blood Glucose type",
                description: nil,
                error: nil
            )
            return
        }

        let query = HKObserverQuery(sampleType: bgType, predicate: nil) { [unowned self] _, _, observerError in
            debug(.service, "Execute HelathKit observer query for loading increment samples")
            guard observerError == nil else {
                warning(.service, "Error during execution of HelathKit Observer's query", error: observerError!)
                return
            }

            if let incrementQuery = getBloodGlucoseHKQuery(predicate: loadBGPredicate) {
                debug(.service, "Create increment query")
                healthKitStore.execute(incrementQuery)
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
                "Can not create background delivery, because unable to get the Blood Glucose type",
                description: nil,
                error: nil
            )
            return
        }

        healthKitStore.enableBackgroundDelivery(
            for: bgType,
            frequency: Config.frequencyBackgroundDeliveryBloodGlucoseFromHealth
        ) { status, e in
            guard e == nil else {
                warning(.service, "Can not enable background delivery", description: nil, error: e)
                return
            }
            debug(.service, "Background delivery status is \(status)")
        }
    }

    /// Try to load samples from Health store with id and do some work
    private func load(
        sampleFromHealth sampleType: HKQuantityType,
        withID id: String,
        andDo completion: (([HKSample]) -> Void)?
    ) {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            operatorType: .equalTo,
            value: id
        )

        let query = HKSampleQuery(
            sampleType: sampleType,
            predicate: predicate,
            limit: 1,
            sortDescriptors: nil
        ) { _, results, _ in

            guard let samples = results as? [HKQuantitySample] else {
                completion?([])
                return
            }

            completion?(samples)
        }
        healthKitStore.execute(query)
    }

    private func getBloodGlucoseHKQuery(predicate: NSPredicate) -> HKQuery? {
        guard let sampleType = Config.healthBGObject else { return nil }

        let query = HKAnchoredObjectQuery(
            type: sampleType,
            predicate: predicate,
            anchor: lastBloodGlucoseQueryAnchor,
            limit: HKObjectQueryNoLimit
        ) { [unowned self] _, addedObjects, deletedObjects, anchor, _ in
            queue.sync {
                debug(.service, "AnchoredQuery did execute")
            }

            lastBloodGlucoseQueryAnchor = anchor

            // Added objects
            if let bgSamples = addedObjects as? [HKQuantitySample],
               bgSamples.isNotEmpty
            {
                prepare(bloodGlucoseSamplesToPublisherFetch: bgSamples)
            }

            // Deleted objects
            if let deletedSamples = deletedObjects,
               deletedSamples.isNotEmpty
            {
                delete(samplesFromLocalStorage: deletedSamples)
            }
        }
        return query
    }

    private func prepare(bloodGlucoseSamplesToPublisherFetch samples: [HKQuantitySample]) {
        queue.sync {
            debug(.service, "Start preparing samples: \(String(describing: samples))")
        }

        newGlucose += samples
            .compactMap { sample -> HealthKitSample? in
                let fromFAX = sample.metadata?[Config.freeAPSMetaKey] as? Bool ?? false
                guard !fromFAX else { return nil }
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
                    unfiltered: nil,
                    filtered: nil,
                    noise: nil,
                    glucose: sample.glucose,
                    type: "sgv"
                )
            }
            .filter { $0.dateString >= Date().addingTimeInterval(-1.days.timeInterval) }

        newGlucose = newGlucose.removeDublicates()

        queue.sync {
            debug(
                .service,
                "Current BloodGlucose.Type objects will be send from Publisher during fetch: \(String(describing: newGlucose))"
            )
        }
    }

    private func delete(samplesFromLocalStorage deletedSamples: [HKDeletedObject]) {
        queue.sync {
            debug(.service, "Delete HealthKit objects: \(String(describing: deletedSamples))")
        }
        DispatchQueue.global(qos: .utility).async {
            let removingBGID = deletedSamples.map {
                $0.metadata?[HKMetadataKeySyncIdentifier] as? String ?? $0.uuid.uuidString
            }
            self.glucoseStorage.removeGlucose(ids: removingBGID)
            self.newGlucose = self.newGlucose.filter { !removingBGID.contains($0.id) }
        }
    }

    func fetch() -> AnyPublisher<[BloodGlucose], Never> {
        queue.sync {
            debug(.service, "Start fetching HealthKitManager")
        }
        guard settingsManager.settings.useAppleHealth else {
            queue.sync {
                debug(.service, "HealthKitManager cant return any data, because useAppleHealth option is disable")
            }
            return Just([]).eraseToAnyPublisher()
        }

        // Remove old BGs
        newGlucose = newGlucose
            .filter { $0.dateString >= Date().addingTimeInterval(-1.days.timeInterval) }
        // Get actual BGs (beetwen Date() - 1 day and Date())
        let actualGlucose = newGlucose
            .filter { $0.dateString <= Date() }
        // Update newGlucose
        newGlucose = newGlucose
            .filter { !actualGlucose.contains($0) }
        queue.sync {
            debug(.service, "Actual glucose is \(actualGlucose)")
        }
        queue.sync {
            debug(.service, "Current state of newGlucose is \(newGlucose)")
        }
        return Just(actualGlucose).eraseToAnyPublisher()
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
