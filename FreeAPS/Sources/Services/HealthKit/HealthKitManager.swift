import Combine
import Foundation
import HealthKit
import Swinject

protocol HealthKitManager: Sendable {
    /// Check all needed permissions
    /// Return false if one or more permissions are deny or not choosen
    var areAllowAllPermissions: Bool { get async }
    /// Check availability to save data of BG type to Health store
    func checkAvailabilitySaveBG() async -> Bool
    /// Requests user to give permissions on using HealthKit
    func requestPermission() async throws -> Bool
}

actor BaseHealthKitManager: HealthKitManager, Injectable, LifetimeOwner, AppService {
    private enum Config {
        // unwraped HKObjects
        static var readPermissions: Set<HKSampleType> {
            Set([healthBGObject].compactMap { $0 }) }

        static var writePermissions: Set<HKSampleType> {
            Set(
                [healthBGObject, healthCarbObject, healthFatObject, healthProteinObject, healthInsulinObject]
                    .compactMap { $0 }
            ) }

        // link to object in HealthKit
        static let healthBGObject = HKObjectType.quantityType(forIdentifier: .bloodGlucose)
        static let healthCarbObject = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)
        static let healthFatObject = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)
        static let healthProteinObject = HKObjectType.quantityType(forIdentifier: .dietaryProtein)
        static let healthInsulinObject = HKObjectType.quantityType(forIdentifier: .insulinDelivery)
    }

    private let healthKitStore: HKHealthStore
    private let collections: [any AppService]

    let lifetime = Lifetime()

    var isAvailableOnCurrentDevice: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // HealthKit never discloses read authorization - reporting it would leak what the user chose to
    // hide - so `authorizationStatus(for:)` is only meaningful for the write types. The read side can
    // only be asked whether a request is still needed.
    var areAllowAllPermissions: Bool {
        get async {
            guard isAvailableOnCurrentDevice else { return false }

            let requestStatus = try? await healthKitStore.statusForAuthorizationRequest(
                toShare: Config.writePermissions,
                read: Config.readPermissions
            )
            guard requestStatus == .unnecessary else { return false }

            return Config.writePermissions.allSatisfy {
                healthKitStore.authorizationStatus(for: $0) == .sharingAuthorized
            }
        }
    }

    init(
        healthKitStore: HKHealthStore,
        settingsManager: SettingsManager,
        appCoordinator: AppCoordinator,
        storage: FileStorage
    ) {
        self.healthKitStore = healthKitStore

        func collection<Source: Sendable, Record: HealthKitRecord>(
            name: String,
            snapshotFile: String,
            source: KeyPath<AppCoordinator, CurrentValueSubject<Source, Never>> & Sendable,
            records: @escaping @Sendable(Source) -> [Record]
        ) -> HealthKitCollectionSync<Source, Record> {
            HealthKitCollectionSync(
                name: name,
                store: healthKitStore,
                storage: storage,
                snapshotFile: snapshotFile,
                retention: .hours(24),
                deletionWindow: .hours(8),
                appCoordinator: appCoordinator,
                settingsManager: settingsManager,
                source: source,
                records: records
            )
        }

        collections = [
            collection(
                name: "glucose",
                snapshotFile: OpenAPS.HealthKit.syncedGlucose,
                source: \.glucoseHistory,
                records: { HealthKitGlucose.from($0) }
            ),
            collection(
                name: "carbs",
                snapshotFile: OpenAPS.HealthKit.syncedCarbs,
                source: \.carbHistory,
                records: { HealthKitCarbs.from($0) }
            ),
            collection(
                name: "insulin",
                snapshotFile: OpenAPS.HealthKit.syncedInsulin,
                source: \.pumpHistory,
                records: { HealthKitInsulin.from($0) }
            )
        ]
    }

    // this is called at the start of the app
    func start() async {
        guard isAvailableOnCurrentDevice else { return }

        for collection in collections {
            try? await collection.start()
        }
    }

    private func checkAvailabilitySave(objectTypeToHealthStore: HKObjectType) -> Bool {
        healthKitStore.authorizationStatus(for: objectTypeToHealthStore) == .sharingAuthorized
    }

    func checkAvailabilitySaveBG() async -> Bool {
        Config.healthBGObject.map { checkAvailabilitySave(objectTypeToHealthStore: $0) } ?? false
    }

    func requestPermission() async throws -> Bool {
        guard isAvailableOnCurrentDevice else {
            throw HKError.notAvailableOnCurrentDevice
        }
        guard Config.readPermissions.isNotEmpty, Config.writePermissions.isNotEmpty else {
            throw HKError.dataNotAvailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            healthKitStore.requestAuthorization(toShare: Config.writePermissions, read: Config.readPermissions) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }
}

enum HKError: Error {
    // HealthKit work only iPhone (not on iPad)
    case notAvailableOnCurrentDevice
    // Some data can be not available on current iOS-device
    case dataNotAvailable
}
