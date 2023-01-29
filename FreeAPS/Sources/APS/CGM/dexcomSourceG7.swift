
import Combine
import Foundation
import G7SensorKit
import LoopKit
import LoopKitUI

final class DexcomSourceG7: GlucoseSource {
    private let processQueue = DispatchQueue(label: "DexcomSource.processQueue")
    private var timer: DispatchTimer?
    private var glucoseStorage: GlucoseStorage!

    var cgmManager: G7CGMManager

    var cgmHasValidSensorSession: Bool = false

    private var promise: Future<[BloodGlucose], Error>.Promise?

    init(glucoseStorage: GlucoseStorage) {
        cgmManager = G7CGMManager()
        cgmManager.cgmManagerDelegate = self
        self.glucoseStorage = glucoseStorage
    }

    func fetch(_ heartbeat: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        // dexcomManager.transmitter.resumeScanning()
        timer = heartbeat
        return Future<[BloodGlucose], Error> { [weak self] promise in
            self?.promise = promise
        }
        .timeout(60, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    deinit {
        // dexcomManager.transmitter.stopScanning()
    }
}

extension DexcomSourceG7: CGMManagerDelegate {
    func deviceManager(
        _: LoopKit.DeviceManager,
        logEventForDeviceIdentifier _: String?,
        type _: LoopKit.DeviceLogEntryType,
        message _: String,
        completion _: ((Error?) -> Void)?
    ) {}

    func issueAlert(_: LoopKit.Alert) {}

    func retractAlert(identifier _: LoopKit.Alert.Identifier) {}

    func doesIssuedAlertExist(identifier _: LoopKit.Alert.Identifier, completion _: @escaping (Result<Bool, Error>) -> Void) {}

    func lookupAllUnretracted(
        managerIdentifier _: String,
        completion _: @escaping (Result<[LoopKit.PersistedAlert], Error>) -> Void
    ) {}

    func lookupAllUnacknowledgedUnretracted(
        managerIdentifier _: String,
        completion _: @escaping (Result<[LoopKit.PersistedAlert], Error>) -> Void
    ) {}

    func recordRetractedAlert(_: LoopKit.Alert, at _: Date) {}

    func cgmManagerWantsDeletion(_: CGMManager) {}

    func cgmManager(_ manager: CGMManager, hasNew readingResult: CGMReadingResult) {
        dispatchPrecondition(condition: .onQueue(.main))
        processCGMReadingResult(manager, readingResult: readingResult) {
            // self.checkPumpDataAndLoop()
        }
    }

    func startDateToFilterNewData(for _: CGMManager) -> Date? {
        dispatchPrecondition(condition: .onQueue(.main))
        return glucoseStorage.lastGlucoseDate()
        //  return glucoseStore.latestGlucose?.startDate
    }

    func cgmManagerDidUpdateState(_: CGMManager) {}

    func credentialStoragePrefix(for _: CGMManager) -> String {
        // return string unique to this instance of the CGMManager
        UUID().uuidString
    }

    func cgmManager(_: CGMManager, didUpdate status: CGMManagerStatus) {
        DispatchQueue.main.async {
            if self.cgmHasValidSensorSession != status.hasValidSensorSession {
                self.cgmHasValidSensorSession = status.hasValidSensorSession
            }
        }
    }

    private func processCGMReadingResult(_: CGMManager, readingResult: CGMReadingResult, completion: @escaping () -> Void) {
        warning(.deviceManager, "DEXCOMG7 - Process CGM Reading Result launched")
        switch readingResult {
        case let .newData(values):
            let bloodGlucose = values.compactMap { newGlucoseSample -> BloodGlucose? in
                let quantity = newGlucoseSample.quantity
                let value = Int(quantity.doubleValue(for: .milligramsPerDeciliter))
                return BloodGlucose(
                    _id: newGlucoseSample.syncIdentifier,
                    sgv: value,
                    direction: .init(trendType: newGlucoseSample.trend),
                    date: Decimal(Int(newGlucoseSample.date.timeIntervalSince1970 * 1000)),
                    dateString: newGlucoseSample.date,
                    unfiltered: nil,
                    filtered: nil,
                    noise: nil,
                    glucose: value,
                    type: "sgv"
                )
            }
            promise?(.success(bloodGlucose))
            completion()
        case .unreliableData:
            // loopManager.receivedUnreliableCGMReading()
            promise?(.failure(GlucoseDataError.unreliableData))
            completion()
        case .noData:
            promise?(.failure(GlucoseDataError.noData))
            completion()
        case let .error(error):
            promise?(.failure(error))
            completion()
        }
    }
}

// extension DexcomSourceG7 {
//    func sourceInfo() -> [String: Any]? {
//        [GlucoseSourceKey.description.rawValue: "Dexcom tramsmitter ID: \(transmitterID)"]
//    }
// }
