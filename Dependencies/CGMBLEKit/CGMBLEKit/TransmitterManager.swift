//
//  TransmitterManager.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import os.log
import HealthKit

public protocol TransmitterManagerDelegate: AnyObject {
    func transmitterManager(_ manager: TransmitterManager, didRead glucose: [Glucose])
    func transmitterManager(_ manager: TransmitterManager, didFailWith error: Error)
}

public struct TransmitterManagerState: Equatable {

    public static let version = 1

    public var transmitterID: String

    public var passiveModeEnabled: Bool = true
    
    public var shouldSyncToRemoteService: Bool

    public init(transmitterID: String, shouldSyncToRemoteService: Bool = false) {
        self.transmitterID = transmitterID
        self.shouldSyncToRemoteService = shouldSyncToRemoteService
    }
}


public protocol TransmitterManagerObserver: AnyObject {
    func transmitterManagerDidUpdateLatestReading(_ manager: TransmitterManager)
}

public class TransmitterManager: TransmitterDelegate {
    public weak var delegate: TransmitterManagerDelegate?

    private var state: TransmitterManagerState

    private let observers = WeakSynchronizedSet<TransmitterManagerObserver>()


    public var hasValidSensorSession: Bool {
        // TODO: we should decode and persist transmitter session state
        return !state.transmitterID.isEmpty
    }


    public required init(state: TransmitterManagerState) {
        self.state = state
        self.transmitter = Transmitter(id: state.transmitterID, passiveModeEnabled: state.passiveModeEnabled)

        self.transmitter.delegate = self
    }

    public var shouldSyncToRemoteService: Bool {
        get {
            return state.shouldSyncToRemoteService
        }
        set {
            self.state.shouldSyncToRemoteService = newValue
            notifyDelegateOfStateChange()
        }
    }


    private(set) public var latestConnection: Date? {
        get {
            return lockedLatestConnection.value
        }
        set {
            lockedLatestConnection.value = newValue
        }
    }
    private let lockedLatestConnection: Locked<Date?> = Locked(nil)

    public let transmitter: Transmitter
    let log = OSLog(category: "TransmitterManager")

    public var providesBLEHeartbeat: Bool {
        return dataIsFresh
    }

    private(set) public var latestReading: Glucose? {
        get {
            return lockedLatestReading.value
        }
        set {
            lockedLatestReading.value = newValue
        }
    }
    private let lockedLatestReading: Locked<Glucose?> = Locked(nil)

    private var dataIsFresh: Bool {
        guard let latestGlucose = latestReading,
            latestGlucose.readDate > Date(timeIntervalSinceNow: .minutes(-4.5)) else {
            return false
        }

        return true
    }

//    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMReadingResult) -> Void) {
//        // Ensure our transmitter connection is active
//        transmitter.resumeScanning()
//
//        // If our last glucose was less than 4.5 minutes ago, don't fetch.
//        guard !dataIsFresh else {
//            completion(.noData)
//            return
//        }
//
//        log.default("Fetching new glucose from Share because last reading is %{public}.1f minutes old", latestReading?.readDate.timeIntervalSinceNow.minutes ?? 0)
//    }

    public var debugDescription: String {
        return [
            "## \(String(describing: type(of: self)))",
            "latestReading: \(String(describing: latestReading))",
            "latestConnection: \(String(describing: latestConnection))",
            "dataIsFresh: \(dataIsFresh)",
            "providesBLEHeartbeat: \(providesBLEHeartbeat)",
            "observers.count: \(observers.cleanupDeallocatedElements().count)",
            String(reflecting: transmitter),
        ].joined(separator: "\n")
    }

//    private func updateDelegate(with result: CGMReadingResult) {
//        if let manager = self as? CGMManager {
//            shareManager.delegate.notify { (delegate) in
//                delegate?.cgmManager(manager, hasNew: result)
//            }
//        }
//
//        notifyObserversOfLatestReading()
//    }
    
    private func notifyDelegateOfStateChange() {
//        if let manager = self as? CGMManager {
//            shareManager.delegate.notify { (delegate) in
//                delegate?.cgmManagerDidUpdateState(manager)
//            }
//        }
    }


    // MARK: - TransmitterDelegate

    public func transmitterDidConnect(_ transmitter: Transmitter) {
        log.default("%{public}@", #function)
        latestConnection = Date()
//        logDeviceCommunication("Connected", type: .connection)
    }

    public func transmitter(_ transmitter: Transmitter, didError error: Error) {
        log.error("%{public}@: %{public}@", #function, String(describing: error))
//        updateDelegate(with: .error(error))
//        logDeviceCommunication("Error: \(error)", type: .error)
    }

    public func transmitter(_ transmitter: Transmitter, didRead glucose: Glucose) {
        guard glucose != latestReading else {
            delegate?.transmitterManager(self, didRead: [])
//            updateDelegate(with: .noData)
            return
        }

        latestReading = glucose

//        logDeviceCommunication("New reading: \(glucose.readDate)", type: .receive)

        guard glucose.state.hasReliableGlucose else {
            log.default("%{public}@: Unreliable glucose: %{public}@", #function, String(describing: glucose.state))
            delegate?.transmitterManager(self, didFailWith: CalibrationError.unreliableState(glucose.state))
//            updateDelegate(with: .error(CalibrationError.unreliableState(glucose.state)))
            return
        }
        
        guard glucose.glucose != nil else {
            delegate?.transmitterManager(self, didRead: [])
//            updateDelegate(with: .noData)
            return
        }

        log.default("%{public}@: New glucose", #function)

        delegate?.transmitterManager(self, didRead: [glucose])

//        updateDelegate(with: .newData([
//            NewGlucoseSample(
//                date: glucose.readDate,
//                quantity: quantity,
//                trend: glucose.trendType,
//                isDisplayOnly: glucose.isDisplayOnly,
//                wasUserEntered: glucose.isDisplayOnly,
//                syncIdentifier: glucose.syncIdentifier,
//                device: device
//            )
//        ]))
    }

    public func transmitter(_ transmitter: Transmitter, didReadBackfill glucose: [Glucose]) {
        let samples = glucose.filter { glucose -> Bool in
            guard glucose != latestReading, glucose.state.hasReliableGlucose, glucose.glucose != nil else {
                return false
            }
            return true
        }
        delegate?.transmitterManager(self, didRead: samples)
//
//        guard samples.count > 0 else {
//            return
//        }

//        updateDelegate(with: .newData(samples))

//        logDeviceCommunication("New backfill: \(String(describing: samples.first?.date))", type: .receive)
    }

    public func transmitter(_ transmitter: Transmitter, didReadUnknownData data: Data) {
        log.error("Unknown sensor data: %{public}@", data.hexadecimalString)
        // This can be used for protocol discovery, but isn't necessary for normal operation

//        logDeviceCommunication("Unknown sensor data: \(data.hexadecimalString)", type: .error)
    }
}


// MARK: - Observer management
extension TransmitterManager {
    public func addObserver(_ observer: TransmitterManagerObserver, queue: DispatchQueue) {
        observers.insert(observer, queue: queue)
    }

    public func removeObserver(_ observer: TransmitterManagerObserver) {
        observers.removeElement(observer)
    }

    private func notifyObserversOfLatestReading() {
        observers.forEach { (observer) in
            observer.transmitterManagerDidUpdateLatestReading(self)
        }
    }
}


public class G5CGMManager: TransmitterManager {
    public let managerIdentifier: String = "DexG5Transmitter"

    public let localizedTitle = LocalizedString("Dexcom G5", comment: "CGM display title")

    public let isOnboarded = true   // No distinction between created and onboarded

    public var appURL: URL? {
        return URL(string: "dexcomcgm://")
    }

    public var device: HKDevice? {
        return HKDevice(
            name: "CGMBLEKit",
            manufacturer: "Dexcom",
            model: "G5 Mobile",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: String(CGMBLEKitVersionNumber),
            localIdentifier: nil,
            udiDeviceIdentifier: "00386270000002"
        )
    }
    
//    func logDeviceCommunication(_ message: String, type: DeviceLogEntryType = .send) {
//        self.cgmManagerDelegate?.deviceManager(self, logEventForDeviceIdentifier: transmitter.ID, type: type, message: message, completion: nil)
//    }
    
}


public class G6CGMManager: TransmitterManager {
    public let managerIdentifier: String = "DexG6Transmitter"

    public let localizedTitle = LocalizedString("Dexcom G6", comment: "CGM display title")

    public let isOnboarded = true   // No distinction between created and onboarded

    public var appURL: URL? {
        return nil
    }

    public var device: HKDevice? {
        return HKDevice(
            name: "CGMBLEKit",
            manufacturer: "Dexcom",
            model: "G6",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: String(CGMBLEKitVersionNumber),
            localIdentifier: nil,
            udiDeviceIdentifier: "00386270000385"
        )
    }
    
//    func logDeviceCommunication(_ message: String, type: DeviceLogEntryType = .send) {
//        self.cgmManagerDelegate?.deviceManager(self, logEventForDeviceIdentifier: transmitter.ID, type: type, message: message, completion: nil)
//    }
}


enum CalibrationError: Error {
    case unreliableState(CalibrationState)
}

extension CalibrationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreliableState:
            return LocalizedString("Glucose data is unavailable", comment: "Error description for unreliable state")
        }
    }

    var failureReason: String? {
        switch self {
        case .unreliableState(let state):
            return state.localizedDescription
        }
    }
}

extension CalibrationState {
    public var localizedDescription: String {
        switch self {
        case .known(let state):
            switch state {
            case .needCalibration7, .needCalibration14, .needFirstInitialCalibration, .needSecondInitialCalibration, .calibrationError8, .calibrationError9, .calibrationError10, .calibrationError13:
                return LocalizedString("Sensor needs calibration", comment: "The description of sensor calibration state when sensor needs calibration.")
            case .ok:
                return LocalizedString("Sensor calibration is OK", comment: "The description of sensor calibration state when sensor calibration is ok.")
            case .stopped, .sensorFailure11, .sensorFailure12, .sessionFailure15, .sessionFailure16, .sessionFailure17:
                return LocalizedString("Sensor is stopped", comment: "The description of sensor calibration state when sensor sensor is stopped.")
            case .warmup, .questionMarks:
                return LocalizedString("Sensor is warming up", comment: "The description of sensor calibration state when sensor sensor is warming up.")
            }
        case .unknown(let rawValue):
            return String(format: LocalizedString("Sensor is in unknown state %1$d", comment: "The description of sensor calibration state when raw value is unknown. (1: missing data details)"), rawValue)
        }
    }
}

