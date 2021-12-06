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
    /// Check availability HealthKit on current device and user's permission of object
    func isAvailableFor(object: HKObjectType) -> Bool
    /// Requests user to give permissions on using HealthKit
    func requestPermission(completion: ((Bool, Error?) -> Void)?)
    /// Save blood glucose data to HealthKit store
    func save(bloodGlucoses: [BloodGlucose], completion: ((Result<Bool, Error>) -> Void)?)
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

        static let frequencyBackgroundDeliveryBloodGlucoseFromHealth = HKUpdateFrequency(rawValue: 10)!
    }

    private var newGlucose: [BloodGlucose] = []

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

    init(resolver: Resolver) {
        injectServices(resolver)
        guard isAvailableOnCurrentDevice, let bjObject = Config.healthBGObject else {
            return
        }
        if isAvailableFor(object: bjObject) {
            debug(.service, "Create HealthKit Observer for Blood Glucose")
            createObserver()
        }
        enableBackgroundDelivery()
    }

    func isAvailableFor(object: HKObjectType) -> Bool {
        let status = healthKitStore.authorizationStatus(for: object)
        switch status {
        case .sharingAuthorized:
            return true
        default:
            return false
        }
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

    func save(bloodGlucoses: [BloodGlucose], completion: ((Result<Bool, Error>) -> Void)? = nil) {
        guard settingsManager.settings.useAppleHealth else { return }

        for bgItem in bloodGlucoses {
            let bgQuantity = HKQuantity(
                unit: .milligramsPerDeciliter,
                doubleValue: Double(bgItem.glucose!)
            )

            let bgObjectSample = HKQuantitySample(
                type: Config.healthBGObject!,
                quantity: bgQuantity,
                start: bgItem.dateString,
                end: bgItem.dateString,
                metadata: [
                    "HKMetadataKeyExternalUUID": bgItem.id,
                    "HKMetadataKeySyncIdentifier": bgItem.id,
                    "HKMetadataKeySyncVersion": 1,
                    "fromFreeAPSX": true
                ]
            )

            healthKitStore.save(bgObjectSample) { status, error in
                guard error == nil else {
                    completion?(Result.failure(error!))
                    return
                }
                completion?(Result.success(status))
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

            if let _ = observerError {
                return
            }

            // loading only daily bg
            let predicate = HKQuery.predicateForSamples(
                withStart: Date().addingTimeInterval(-1.days.timeInterval),
                end: nil,
                options: .strictStartDate
            )

            healthKitStore.execute(getQueryForDeletedBloodGlucose(sampleType: bgType, predicate: predicate))
            healthKitStore.execute(getQueryForAddedBloodGlucose(sampleType: bgType, predicate: predicate))
        }
        healthKitStore.execute(query)
    }

    func enableBackgroundDelivery() {
        guard settingsManager.settings.useAppleHealth else { return }

        guard let bgType = Config.healthBGObject else {
            warning(
                .service,
                "Can not create HealthKit Background Delivery, because unable to get the Blood Glucose type",
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
                warning(.service, "Can not enable background delivery for Apple Health", description: nil, error: e)
                return
            }
            debug(.service, "HealthKit background delivery status is \(status)")
        }
    }

    private func getQueryForDeletedBloodGlucose(sampleType: HKQuantityType, predicate: NSPredicate) -> HKQuery {
        let query = HKAnchoredObjectQuery(
            type: sampleType,
            predicate: predicate,
            anchor: nil,
            limit: 1000
        ) { [unowned self] _, _, deletedObjects, _, _ in
            guard let samples = deletedObjects else {
                return
            }

            DispatchQueue.global(qos: .utility).async {
                let removingBGID = samples.map {
                    $0.metadata?["HKMetadataKeySyncIdentifier"] as? String ?? $0.uuid.uuidString
                }
                glucoseStorage.removeGlucose(ids: removingBGID)
            }
        }
        return query
    }

    private func getQueryForAddedBloodGlucose(sampleType: HKQuantityType, predicate: NSPredicate) -> HKQuery {
        let query = HKSampleQuery(
            sampleType: sampleType,
            predicate: predicate,
            limit: Int(HKObjectQueryNoLimit),
            sortDescriptors: nil
        ) { [unowned self] _, results, _ in

            guard let samples = results as? [HKQuantitySample], samples.isNotEmpty else {
                return
            }

            let oldSamples: [HealthKitSample] = fileStorage
                .retrieve(OpenAPS.HealthKit.downloadedGlucose, as: [HealthKitSample].self) ?? []

            let newSamples = samples
                .compactMap { sample -> HealthKitSample? in
                    let fromFAX = sample.metadata?["fromFreeAPSX"] as? Bool ?? false
                    guard !fromFAX else { return nil }
                    return HealthKitSample(
                        healthKitId: sample.uuid.uuidString,
                        date: sample.startDate,
                        glucose: Int(round(sample.quantity.doubleValue(for: .milligramsPerDeciliter)))
                    )
                }
                .filter { !oldSamples.contains($0) }

            guard newSamples.isNotEmpty else { return }

            let newGlucose = newSamples.map { sample in
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

            self.newGlucose = newGlucose

            let savingSamples = (newSamples + oldSamples)
                .removeDublicates()
                .filter { $0.date >= Date().addingTimeInterval(-1.days.timeInterval) }

            self.fileStorage.save(savingSamples, as: OpenAPS.HealthKit.downloadedGlucose)
        }
        return query
    }

    func fetch() -> AnyPublisher<[BloodGlucose], Never> {
        guard settingsManager.settings.useAppleHealth else { return Just([]).eraseToAnyPublisher() }

        let copy = newGlucose
        newGlucose = []

        return Just(copy).eraseToAnyPublisher()
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
