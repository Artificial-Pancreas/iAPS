import Combine
import EversenseKit
import LoopKit
import LoopKitUI

final class EversenseSource: GlucoseSource {
    private let processQueue = DispatchQueue(label: "EversenseSource.processQueue")
    private var glucoseStorage: GlucoseStorage!
    var glucoseManager: (any FetchGlucoseManager)?
    var cgmManager: (any LoopKitUI.CGMManagerUI)?

    let cgmType: CGMType = .eversense
    private var promise: Future<[BloodGlucose], Error>.Promise?

    init(glucoseStorage: GlucoseStorage, glucoseManager: FetchGlucoseManager) {
        self.glucoseStorage = glucoseStorage
        self.glucoseManager = glucoseManager
        cgmManager = EversenseCGMManager(rawState: UserDefaults.standard.eversenseRawState ?? [:])
        cgmManager?.cgmManagerDelegate = self
        cgmManager?.delegateQueue = processQueue
    }

    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        Future<[BloodGlucose], Error> { [weak self] promise in
            self?.promise = promise
        }
        .timeout(60 * 5, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        Future<[BloodGlucose], Error> { _ in
            self.processQueue.async {
                guard let cgmManager = self.cgmManager else { return }
                cgmManager.fetchNewDataIfNeeded { _ in
//                    self.processCGMReadingResult(cgmManager, readingResult: result) {
//                        // nothing to do
//                    }
                }
            }
        }
        .timeout(60, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }
}

extension EversenseSource: CGMManagerDelegate {
    func deviceManager(
        _: any LoopKit.DeviceManager,
        logEventForDeviceIdentifier deviceIdentifier: String?,
        type _: LoopKit.DeviceLogEntryType,
        message: String,
        completion _: (((any Error)?) -> Void)?
    ) {
        debug(.deviceManager, "device Manager for \(String(describing: deviceIdentifier)) : \(message)")
    }

    func cgmManager(_ manager: any LoopKit.CGMManager, didUpdate _: LoopKit.CGMManagerStatus) {
        UserDefaults.standard.eversenseRawState = manager.rawState
    }

    func issueAlert(_: LoopKit.Alert) {}

    func retractAlert(identifier _: LoopKit.Alert.Identifier) {}

    func doesIssuedAlertExist(
        identifier _: LoopKit.Alert.Identifier,
        completion _: @escaping (Result<Bool, any Error>) -> Void
    ) {}

    func lookupAllUnretracted(
        managerIdentifier _: String,
        completion _: @escaping (Result<[LoopKit.PersistedAlert], any Error>) -> Void
    ) {}

    func lookupAllUnacknowledgedUnretracted(
        managerIdentifier _: String,
        completion _: @escaping (Result<[LoopKit.PersistedAlert], any Error>) -> Void
    ) {}

    func recordRetractedAlert(_: LoopKit.Alert, at _: Date) {}

    func startDateToFilterNewData(for _: any LoopKit.CGMManager) -> Date? {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return glucoseStorage.lastGlucoseDate()
    }

    func cgmManager(_: any LoopKit.CGMManager, hasNew _: LoopKit.CGMReadingResult) {
        // TODO:
    }

    func cgmManagerWantsDeletion(_ manager: any LoopKit.CGMManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, " CGM Manager with identifier \(manager.managerIdentifier) wants deletion")
        glucoseManager?.cgmGlucoseSourceType = nil
    }

    func cgmManagerDidUpdateState(_ manager: any LoopKit.CGMManager) {
        UserDefaults.standard.eversenseRawState = manager.rawState
    }

    func credentialStoragePrefix(for _: any LoopKit.CGMManager) -> String {
        // return string unique to this instance of the CGMManager
        UUID().uuidString
    }
}

extension UserDefaults {
    @objc var eversenseRawState: CGMManager.RawStateValue? {
        get {
            dictionary(forKey: "EversenseSource.rawState")
        }
        set {
            set(newValue, forKey: "EversenseSource.rawState")
        }
    }
}
