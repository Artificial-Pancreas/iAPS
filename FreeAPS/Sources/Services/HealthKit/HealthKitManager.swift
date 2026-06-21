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
    /// Save blood glucose to Health store (dublicate of bg will ignore)
    func saveIfNeeded(bloodGlucose: [BloodGlucose]) async
    /// Save carbs to Health store (dublicate of bg will ignore)
    func saveIfNeeded(carbs: [CarbsEntry]) async
    /// Save Insulin to Health store
    func saveIfNeeded(pumpEvents events: [PumpHistoryEvent]) async
    /// Delete glucose with syncID
    func deleteGlucose(syncID: String) async
    /// delete carbs with syncID
    func deleteCarbs(date: Date) async
    /// delete insulin with syncID
    func deleteInsulin(syncID: String) async
}

actor BaseHealthKitManager: HealthKitManager, Injectable, LifetimeOwner, AppService {
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

    private let healthKitStore: HKHealthStore
    private let settingsManager: SettingsManager
    private let appCoordinator: AppCoordinator

    let lifetime = Lifetime()

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

    init(
        healthKitStore: HKHealthStore,
        settingsManager: SettingsManager,
        appCoordinator: AppCoordinator
    ) {
        self.healthKitStore = healthKitStore
        self.settingsManager = settingsManager
        self.appCoordinator = appCoordinator
    }

    // this is called at the start of the app
    func start() async {
        guard isAvailableOnCurrentDevice,
              Config.healthBGObject != nil else { return }

        observe(appCoordinator.carbHistory.dropFirst()) { me, carbs in
            await me.saveIfNeeded(carbs: carbs)
        }
        observe(appCoordinator.pumpHistory.dropFirst()) { me, events in
            await me.saveIfNeeded(pumpEvents: events)
        }
        observe(appCoordinator.newGlucoseRecords) { me, bloodGlucose in
            await me.saveIfNeeded(bloodGlucose: bloodGlucose)
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

    func saveIfNeeded(bloodGlucose: [BloodGlucose]) async {
        let settings = await settingsManager.settings
        guard settings.useAppleHealth,
              let sampleType = Config.healthBGObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType),
              bloodGlucose.isNotEmpty
        else { return }

        func save(samples: [HKSample]) async {
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

            do {
                try await healthKitStore.save(samplesToSave)
            } catch {
                debug(.service, "failed to store blood glucose to HealthKit: " + error.localizedDescription)
            }
        }

        let samples = await loadSamplesFromHealth(sampleType: sampleType, withIDs: bloodGlucose.map(\.id))
        await save(samples: samples)
    }

    func saveIfNeeded(carbs: [CarbsEntry]) async {
        let settings = await settingsManager.settings
        guard settings.useAppleHealth,
              let sampleType = Config.healthCarbObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType),
              carbs.isNotEmpty
        else { return }

        let carbsWithId = carbs.filter { $0.id != nil }

        func save(samples: [HKSample]) async {
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

            do {
                try await healthKitStore.save(samplesToSave)
            } catch {
                debug(.service, "failed to store carb entries to HealthKit: " + error.localizedDescription)
            }
        }

        let samples = await loadSamplesFromHealth(sampleType: sampleType)
        await save(samples: samples)
    }

    func saveIfNeeded(pumpEvents events: [PumpHistoryEvent]) async {
        let settings = await settingsManager.settings
        let preferences = await settingsManager.preferences

        guard settings.useAppleHealth,
              let sampleType = Config.healthInsulinObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType),
              events.isNotEmpty
        else { return }

        func delete(syncIds: [String]) async {
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeySyncIdentifier,
                allowedValues: syncIds
            )

            do {
                try await self.healthKitStore.deleteObjects(of: sampleType, predicate: predicate)
            } catch {
                warning(.service, "failed to delete sampless from HealthKit: " + error.localizedDescription)
            }
        }

        func save(bolus: [InsulinBolus], basal: [InsulinBasal]) async {
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

            do {
                try await healthKitStore.save(bolusSamples + basalSamples)
            } catch {
                debug(.service, "failed to store insulin entry to HealthKit: " + error.localizedDescription)
            }
        }

        let samples = await loadSamplesFromHealth(sampleType: sampleType, withIDs: events.map(\.id))
        let sampleIDs = samples.compactMap(\.syncIdentifier)

        // delete existing event in HK where the amount is not the last value in the pumphistory
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
        await delete(syncIds: bolusToDelete)

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

                var minimalDose = preferences.bolusIncrement
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

        await save(bolus: bolus, basal: basal)
    }

    /// Try to load samples from Health store
    private func loadSamplesFromHealth(
        sampleType: HKQuantityType
    ) async -> [HKSample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: sampleType, predicate: nil)],
            sortDescriptors: [],
            limit: 100
        )
        do {
            return try await descriptor.result(for: healthKitStore)
        } catch {
            warning(.service, "failed to load samples from HealthKit", error: error)
            return []
        }
    }

    /// Try to load samples from Health store with id and do some work
    private func loadSamplesFromHealth(
        sampleType: HKQuantityType,
        withIDs ids: [String]
    ) async -> [HKSample] {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            allowedValues: ids
        )

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: sampleType, predicate: predicate)],
            sortDescriptors: [],
            limit: 100
        )
        do {
            return try await descriptor.result(for: healthKitStore)
        } catch {
            warning(.service, "failed to load samples from HealthKit", error: error)
            return []
        }
    }

    func deleteGlucose(syncID: String) async {
        let settings = await settingsManager.settings
        guard settings.useAppleHealth,
              let sampleType = Config.healthBGObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType)
        else { return }

        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            operatorType: .equalTo,
            value: syncID
        )

        do {
            let count = try await self.healthKitStore.deleteObjects(of: sampleType, predicate: predicate)
            debug(.service, "\(count) glucose entries deleted from Health Store", printToConsole: true)
        } catch {
            warning(.service, "Cannot delete sample with syncID: \(syncID)", error: error)
        }
    }

    // MARK: Carbs function

    func deleteCarbs(date: Date) async {
        let settings = await settingsManager.settings
        guard settings.useAppleHealth,
              let sampleType = Config.healthCarbObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType)
        else { return }

        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            operatorType: .equalTo,
            value: "\(date)"
        )

        do {
            let count = try await healthKitStore.deleteObjects(of: sampleType, predicate: predicate)
            debug(.service, "\(count) carb entries with date: \(date) deleted from Health Store", printToConsole: true)
        } catch {
            warning(.service, "Cannot delete sample with date: \(date)", error: error)
        }
    }

    // - MARK Insulin function

    func deleteInsulin(syncID: String) async {
        let settings = await settingsManager.settings
        guard settings.useAppleHealth,
              let sampleType = Config.healthInsulinObject,
              checkAvailabilitySave(objectTypeToHealthStore: sampleType)
        else { return }

        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            operatorType: .equalTo,
            value: syncID
        )

        do {
            let count = try await self.healthKitStore.deleteObjects(of: sampleType, predicate: predicate)
            debug(.service, "\(count) insulin entries with ID: \(syncID) deleted from Health Store")
        } catch {
            warning(.service, "Cannot delete sample with syncID: \(syncID)", error: error)
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
