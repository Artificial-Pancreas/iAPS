import Combine
import Foundation
import LibreTransmitter
import LoopKitUI
import Swinject
import LoopKit

protocol LibreTransmitterSource: GlucoseSource {
    var manager: LibreTransmitterManagerV3? { get set }
}

final class BaseLibreTransmitterSource: LibreTransmitterSource, Injectable {
    var cgmManager: CGMManagerUI?
    var cgmType: CGMType = .libreTransmitter

    private let processQueue = DispatchQueue(label: "BaseLibreTransmitterSource.processQueue")

    private let glucoseStorage: GlucoseStorage
    private let calibrationService: CalibrationService
    var glucoseManager: (any FetchGlucoseManager)?
    
    @Persisted(key: "LibreTransmitterManager.configured") private(set) var configured = false
    
    init(
      glucoseStorage: GlucoseStorage,
      glucoseManager: FetchGlucoseManager,
      calibrationService: CalibrationService
    ) {
        self.glucoseStorage = glucoseStorage
        self.calibrationService = calibrationService
        self.glucoseManager = glucoseManager
    }
    
    private var promise: Future<[BloodGlucose], Error>.Promise?

    var manager: LibreTransmitterManagerV3? {
        didSet {
            configured = manager != nil
            manager?.cgmManagerDelegate = self
        }
    }

    init(resolver: Resolver) {
        if configured {
            manager = LibreTransmitterManagerV3()
            manager?.cgmManagerDelegate = self
        }
        injectServices(resolver)
    }

    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        Future<[BloodGlucose], Error> { [weak self] promise in
            self?.promise = promise
        }
        .timeout(60, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        fetch(nil)
    }

    func sourceInfo() -> [String: Any]? {
        if let battery = manager?.batteryLevel {
            return ["transmitterBattery": battery]
        }
        return nil
    }
}

extension BaseLibreTransmitterSource: CGMManagerDelegate {
    func startDateToFilterNewData(for manager: any LoopKit.CGMManager) -> Date? {
        
    }
    
    func cgmManager(_ manager: any LoopKit.CGMManager, hasNew readingResult: LoopKit.CGMReadingResult) {
        
    }
    
    func cgmManager(_ manager: any LoopKit.CGMManager, hasNew events: [LoopKit.PersistedCgmEvent]) {
        
    }
    
    func cgmManagerWantsDeletion(_ manager: any LoopKit.CGMManager) {
        
    }
    
    func cgmManagerDidUpdateState(_ manager: any LoopKit.CGMManager) {
        
    }
    
    func credentialStoragePrefix(for manager: any LoopKit.CGMManager) -> String {
        
    }
    
    func deviceManager(_ manager: any LoopKit.DeviceManager, logEventForDeviceIdentifier deviceIdentifier: String?, type: LoopKit.DeviceLogEntryType, message: String, completion: (((any Error)?) -> Void)?) {
        
    }
    
    func cgmManager(_ manager: any LoopKit.CGMManager, didUpdate status: LoopKit.CGMManagerStatus) {
        
    }
    
    func issueAlert(_ alert: LoopKit.Alert) {
        
    }
    
    func retractAlert(identifier: LoopKit.Alert.Identifier) {
        
    }
    
    func doesIssuedAlertExist(identifier: LoopKit.Alert.Identifier, completion: @escaping (Result<Bool, any Error>) -> Void) {
        
    }
    
    func lookupAllUnretracted(managerIdentifier: String, completion: @escaping (Result<[LoopKit.PersistedAlert], any Error>) -> Void) {
        
    }
    
    func lookupAllUnacknowledgedUnretracted(managerIdentifier: String, completion: @escaping (Result<[LoopKit.PersistedAlert], any Error>) -> Void) {
        
    }
    
    func recordRetractedAlert(_ alert: LoopKit.Alert, at date: Date) {
        
    }
    
    
}


extension BaseLibreTransmitterSource {
    var queue: DispatchQueue { processQueue }

    func startDateToFilterNewData(for _: LibreTransmitterManagerV3) -> Date? {
        glucoseStorage.syncDate()
    }

    func cgmManager(_ manager: LibreTransmitterManagerV3, hasNew result: Result<[LibreGlucose], Error>) {
        switch result {
        case let .success(newGlucose):
            let glucose = newGlucose.map { value -> BloodGlucose in
                BloodGlucose(
                    _id: UUID().uuidString,
                    sgv: Int(value.glucose),
                    direction: manager.glucoseDisplay?.trendType
                        .map { .init(trendType: $0) },
                    date: Decimal(Int(value.startDate.timeIntervalSince1970 * 1000)),
                    dateString: value.startDate,
                    unfiltered: Decimal(value.unsmoothedGlucose),
                    filtered: nil,
                    noise: nil,
                    glucose: Int(value.glucose),
                    type: "sgv",
                    activationDate: /*value.sensorStartDate ?? */ manager.sensorInfoObservable.activatedAt,
                    sessionStartDate: /*value.sensorStartDate ?? */ manager.sensorInfoObservable.activatedAt,
                    transmitterID: manager.sensorInfoObservable.sensorSerial
                )
            }
            NSLog("Debug Libre \(glucose)")
            promise?(.success(glucose))

        case let .failure(error):
            warning(.service, "LibreTransmitter error:", error: error)
            promise?(.failure(error))
        }
    }

    func overcalibration(for _: LibreTransmitterManagerV3) -> ((Double) -> (Double))? {
        calibrationService.calibrate
    }
}
