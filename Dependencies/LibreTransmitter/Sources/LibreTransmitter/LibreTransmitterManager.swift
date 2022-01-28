//
//  LibreTransmitterManager.swift
//  Created by Bjørn Inge Berg on 25/02/2019.
//  Copyright © 2019 Bjørn Inge Berg. All rights reserved.
//
import Foundation
import UserNotifications
import Combine
import UIKit
import CoreBluetooth
import HealthKit
import os.log

public protocol LibreTransmitterManagerDelegate: AnyObject {
    var queue: DispatchQueue { get }

    func startDateToFilterNewData(for: LibreTransmitterManager) -> Date?

    func cgmManager(_:LibreTransmitterManager, hasNew result: Result<[LibreGlucose], Error>)

    func overcalibration(for: LibreTransmitterManager) -> ((Double) -> (Double))?
}

public final class LibreTransmitterManager: LibreTransmitterDelegate {

    public typealias GlucoseArrayWithPrediction = (glucose:[LibreGlucose], prediction:[LibreGlucose])
    public lazy var logger = Logger(forType: Self.self)


    public let isOnboarded = true   // No distinction between created and onboarded
    public var hasValidSensorSession: Bool {
        lastConnected != nil
    }

    public var glucoseDisplay: GlucoseDisplayable?
    public var trend: GlucoseTrend?


    public func libreManagerDidRestoreState(found peripherals: [CBPeripheral], connected to: CBPeripheral?) {
        let devicename = to?.name  ?? "no device"
        let id = to?.identifier.uuidString ?? "null"
        let msg = String(format: NSLocalizedString("Bluetooth State restored (APS restarted?). Found %d peripherals, and connected to %@ with identifier %@", comment: "Restored state message"), peripherals.count, devicename, id)

        NotificationHelper.sendRestoredStateNotification(msg: msg)
    }

    public var batteryLevel: Double? {
        let batt = self.proxy?.metadata?.battery
        logger.debug("dabear:: LibreTransmitterManager was asked to return battery: \(batt.debugDescription)")
        //convert from 8% -> 0.8
        if let battery = proxy?.metadata?.battery {
            return Double(battery) / 100
        }

        return nil
    }



    public var cgmManagerDelegate: LibreTransmitterManagerDelegate? {
        get {
            return delegate.delegate
        }
        set {
            delegate.delegate = newValue
        }
    }

    public var delegateQueue: DispatchQueue! {
        get {
            return delegate.queue
        }
        set {
            delegate.queue = newValue
        }
    }

    public let delegate = WeakSynchronizedDelegate<LibreTransmitterManagerDelegate>()

    public var managedDataInterval: TimeInterval?


    private func getPersistedSensorDataForDebug() -> String {
        guard let data = UserDefaults.standard.queuedSensorData else {
            return "nil"
        }

        let c = self.calibrationData?.description ?? "no calibrationdata"
        return data.array.map {
            "SensorData(uuid: \"0123\".data(using: .ascii)!, bytes: \($0.bytes))!"
        }
        .joined(separator: ",\n")
        + ",\n Calibrationdata: \(c)"
    }

    public var debugDescription: String {

        return [
            "## LibreTransmitterManager",
            "Testdata: foo",
            "lastConnected: \(String(describing: lastConnected))",
            "Connection state: \(connectionState)",
            "Sensor state: \(sensorStateDescription)",
            "transmitterbattery: \(batteryString)",
            "SensorData: \(getPersistedSensorDataForDebug())",
            "Metainfo::\n\(AppMetaData.allProperties)",
            ""
        ].joined(separator: "\n")
    }

    public private(set) var lastConnected: Date?

    public private(set) var latestPrediction: LibreGlucose?
    public private(set) var latestBackfill: LibreGlucose? {
        willSet(newValue) {
            guard let newValue = newValue else {
                return
            }

            var trend: GlucoseTrend?
            let oldValue = latestBackfill

            logger.debug("dabear:: latestBackfill set, newvalue is \(newValue.description)")

            if let oldValue = oldValue {
                // the idea here is to use the diff between the old and the new glucose to calculate slope and direction, rather than using trend from the glucose value.
                // this is because the old and new glucose values represent earlier readouts, while the trend buffer contains somewhat more jumpy (noisy) values.
                let timediff = LibreGlucose.timeDifference(oldGlucose: oldValue, newGlucose: newValue)
                logger.debug("dabear:: timediff is \(timediff)")
                let oldIsRecentEnough = timediff <= TimeInterval.minutes(15)

                trend = oldIsRecentEnough ? newValue.GetGlucoseTrend(last: oldValue) : nil

                var batteries : [(name: String, percentage: Int)]?
                if let metaData = metaData, let battery = battery {
                    batteries = [(name: metaData.name, percentage: battery)]
                }

                self.glucoseDisplay = ConcreteGlucoseDisplayable(isStateValid: newValue.isStateValid, trendType: trend, isLocal: true, batteries: batteries)
            } else {
                //could consider setting this to ConcreteSensorDisplayable with trendtype GlucoseTrend.flat, but that would be kinda lying
                self.glucoseDisplay = nil
            }
        }

    }

    static public var managerIdentifier : String {
        Self.className
    }

    static public let localizedTitle = LocalizedString("Libre Bluetooth", comment: "Title for the CGMManager option")



    public init() {
        lastConnected = nil
        //let isui = (self is CGMManagerUI)
        //self.miaomiaoService = MiaomiaoService(keychainManager: keychain)
        logger.debug("dabear: LibreTransmitterManager will be created now")
        //proxy = MiaoMiaoBluetoothManager()
        proxy?.delegate = self
    }

    public func disconnect() {
        logger.debug("dabear:: LibreTransmitterManager disconnect called")

        proxy?.disconnectManually()
        proxy?.delegate = nil
    }

    deinit {
        logger.debug("dabear:: LibreTransmitterManager deinit called")
        //cleanup any references to events to this class
        disconnect()
    }

    //lazy because we don't want to scan immediately
    private lazy var proxy: LibreTransmitterProxyManager? = LibreTransmitterProxyManager()

    /*
     These properties are mostly useful for swiftui
     */
    public var transmitterInfoObservable = TransmitterInfo()
    public var sensorInfoObservable = SensorInfo()
    public var glucoseInfoObservable = GlucoseInfo()



    var longDateFormatter : DateFormatter = ({
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .long
        df.doesRelativeDateFormatting = true
        return df
    })()

    var dateFormatter : DateFormatter = ({
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .full
        df.locale = Locale.current
        return df
    })()


    //when was the libre2 direct ble update last received?
    var lastDirectUpdate : Date? = nil

    private var countTimesWithoutData: Int = 0


}


// MARK: - Convenience functions
extension LibreTransmitterManager {
    func setObservables(sensorData: SensorData?, bleData: Libre2.LibreBLEResponse?, metaData: LibreTransmitterMetadata?) {
        logger.debug("dabear:: setObservables called")
        DispatchQueue.main.async {


            if let metaData=metaData {
                self.logger.debug("dabear::will set transmitterInfoObservable")
                self.transmitterInfoObservable.battery = metaData.batteryString
                self.transmitterInfoObservable.hardware = metaData.hardware
                self.transmitterInfoObservable.firmware = metaData.firmware
                self.transmitterInfoObservable.sensorType = metaData.sensorType()?.description ?? "Unknown"
                self.transmitterInfoObservable.transmitterIdentifier = metaData.macAddress ??  UserDefaults.standard.preSelectedDevice ?? "Unknown"


            }

            self.transmitterInfoObservable.connectionState = self.proxy?.connectionStateString ?? "n/a"
            self.transmitterInfoObservable.transmitterType = self.proxy?.shortTransmitterName ?? "Unknown"

            if let sensorData = sensorData {
                self.logger.debug("dabear::will set sensorInfoObservable")
                self.sensorInfoObservable.sensorAge = sensorData.humanReadableSensorAge
                self.sensorInfoObservable.sensorAgeLeft = sensorData.humanReadableTimeLeft

                self.sensorInfoObservable.sensorState = sensorData.state.description
                self.sensorInfoObservable.sensorSerial = sensorData.serialNumber

                self.glucoseInfoObservable.checksum = String(sensorData.footerCrc.byteSwapped)



                if let sensorEndTime = sensorData.sensorEndTime {
                    self.sensorInfoObservable.sensorEndTime = self.dateFormatter.string(from: sensorEndTime )

                } else {
                    self.sensorInfoObservable.sensorEndTime = "Unknown or ended"

                }

            } else if let bleData = bleData, let sensor = UserDefaults.standard.preSelectedSensor {
                let aday = 86_400.0 //in seconds
                var humanReadableSensorAge: String {
                    let days = TimeInterval(bleData.age * 60) / aday
                    return String(format: "%.2f", days) + NSLocalizedString(" day(s)", comment: "Sensor day(s)")
                }


                var maxMinutesWearTime : Int{
                    sensor.maxAge
                }

                var minutesLeft: Int {
                    maxMinutesWearTime - bleData.age
                }


                var humanReadableTimeLeft: String {
                    let days = TimeInterval(minutesLeft * 60) / aday
                    return String(format: "%.2f", days) + NSLocalizedString(" day(s)", comment: "Sensor day(s)")
                }

                //once the sensor has ended we don't know the exact date anymore
                var sensorEndTime: Date? {
                    if minutesLeft <= 0 {
                        return nil
                    }

                    // we can assume that the libre2 direct bluetooth packet is received immediately
                    // after the sensor has been done a new measurement, so using Date() should be fine here
                    return Date().addingTimeInterval(TimeInterval(minutes: Double(minutesLeft)))
                }

                self.sensorInfoObservable.sensorAge = humanReadableSensorAge
                self.sensorInfoObservable.sensorAgeLeft = humanReadableTimeLeft
                self.sensorInfoObservable.sensorState = "Operational"
                self.sensorInfoObservable.sensorState = "Operational"
                self.sensorInfoObservable.sensorSerial = SensorSerialNumber(withUID: sensor.uuid)?.serialNumber ?? "-"

                if let mapping = UserDefaults.standard.calibrationMapping,
                   let calibration = self.calibrationData ,
                   mapping.uuid == sensor.uuid && calibration.isValidForFooterWithReverseCRCs ==  mapping.reverseFooterCRC {
                    self.glucoseInfoObservable.checksum = "\(mapping.reverseFooterCRC)"
                }

                if let sensorEndTime = sensorEndTime {
                    self.sensorInfoObservable.sensorEndTime = self.dateFormatter.string(from: sensorEndTime )

                } else {
                    self.sensorInfoObservable.sensorEndTime = "Unknown or ended"

                }

            }

            let formatter = QuantityFormatter()
            let preferredUnit = UserDefaults.standard.mmGlucoseUnit ?? .millimolesPerLiter


            if let d = self.latestBackfill {
                self.logger.debug("dabear::will set glucoseInfoObservable")

                formatter.setPreferredNumberFormatter(for: .millimolesPerLiter)
                self.glucoseInfoObservable.glucoseMMOL = formatter.string(from: d.quantity, for: .millimolesPerLiter) ?? "-"


                formatter.setPreferredNumberFormatter(for: .milligramsPerDeciliter)
                self.glucoseInfoObservable.glucoseMGDL = formatter.string(from: d.quantity, for: .milligramsPerDeciliter) ?? "-"

                //backward compat
                if preferredUnit == .millimolesPerLiter {
                    self.glucoseInfoObservable.glucose = self.glucoseInfoObservable.glucoseMMOL
                } else if preferredUnit == .milligramsPerDeciliter {
                    self.glucoseInfoObservable.glucose = self.glucoseInfoObservable.glucoseMGDL
                }



                self.glucoseInfoObservable.date = self.longDateFormatter.string(from: d.timestamp)
            }

            if let d = self.latestPrediction {
                formatter.setPreferredNumberFormatter(for: .millimolesPerLiter)
                self.glucoseInfoObservable.predictionMMOL = formatter.string(from: d.quantity, for: .millimolesPerLiter) ?? "-"


                formatter.setPreferredNumberFormatter(for: .milligramsPerDeciliter)
                self.glucoseInfoObservable.predictionMGDL = formatter.string(from: d.quantity, for: .milligramsPerDeciliter) ?? "-"
                self.glucoseInfoObservable.predictionDate = self.longDateFormatter.string(from: d.timestamp)


            }





        }


    }

    func getStartDateForFilter() -> Date?{
        var startDate: Date?

        self.delegateQueue.sync {
            startDate = self.cgmManagerDelegate?.startDateToFilterNewData(for: self) ?? self.latestBackfill?.startDate
        }

        // add one second to startdate to make this an exclusive (non overlapping) match
        return startDate?.addingTimeInterval(1)
    }

    func glucosesToSamplesFilter(_ array: [LibreGlucose], startDate: Date?) -> [LibreGlucose] {
        array
            .filterDateRange(startDate, nil)
            .filter { $0.isStateValid }
            .compactMap { $0 }
    }

    public var calibrationData: SensorData.CalibrationInfo? {
        KeychainManagerWrapper.standard.getLibreNativeCalibrationData()
    }
}


// MARK: - Direct bluetooth updates
extension LibreTransmitterManager {

    public func libreSensorDidUpdate(with bleData: Libre2.LibreBLEResponse, and device: LibreTransmitterMetadata) {
        self.logger.debug("dabear:: got sensordata: \(String(describing: bleData))")
        let typeDesc = device.sensorType().debugDescription

        let now = Date()
        //only once per mins minute
        let mins =  4.5
        if let earlierplus = lastDirectUpdate?.addingTimeInterval(mins * 60), earlierplus >= now  {
            logger.debug("last ble update was less than \(mins) minutes ago, aborting loop update")
            return
        }

        logger.debug("Directly connected to libresensor of type \(typeDesc). Details:  \(device.description)")

        guard let mapping = UserDefaults.standard.calibrationMapping,
              let calibrationData = calibrationData,
              let sensor = UserDefaults.standard.preSelectedSensor else {
            logger.error("calibrationdata, sensor uid or mapping missing, could not continue")
            self.delegateQueue.async {
                self.cgmManagerDelegate?.cgmManager(self, hasNew: .failure(LibreError.noCalibrationData))
            }
            return
        }

        guard mapping.reverseFooterCRC == calibrationData.isValidForFooterWithReverseCRCs &&
                mapping.uuid == sensor.uuid else {
            logger.error("Calibrationdata was not correct for these bluetooth packets. This is a fatal error, we cannot calibrate without re-pairing")
            self.delegateQueue.async {
                self.cgmManagerDelegate?.cgmManager(self, hasNew: .failure(LibreError.noCalibrationData))
            }
            return
        }

        guard bleData.crcVerified else {
            self.delegateQueue.async {
                self.cgmManagerDelegate?.cgmManager(self, hasNew: .failure(LibreError.checksumValidationError))
            }

            logger.debug("did not get bledata with valid crcs")
            return
        }

        if sensor.maxAge > 0 {
            let minutesLeft = Double(sensor.maxAge - bleData.age)
            NotificationHelper.sendSensorExpireAlertIfNeeded(minutesLeft: minutesLeft)

        }


//        let device = self.proxy?.device



        let sortedTrends = bleData.trend.sorted{ $0.date > $1.date}

        let glucose = LibreGlucose.fromTrendMeasurements(sortedTrends, nativeCalibrationData: calibrationData, returnAll: UserDefaults.standard.mmBackfillFromTrend)
        //glucose += LibreGlucose.fromHistoryMeasurements(bleData.history, nativeCalibrationData: calibrationData)
        // while libre2 fram scans contains historymeasurements for the last 8 hours,
        // history from bledata contains just a couple of data points, so we don't bother
        /*if UserDefaults.standard.mmBackfillFromHistory {
            let sortedHistory = bleData.history.sorted{ $0.date > $1.date}
            glucose += LibreGlucose.fromHistoryMeasurements(sortedHistory, nativeCalibrationData: calibrationData)
        }*/

        var newGlucose = glucosesToSamplesFilter(glucose, startDate: getStartDateForFilter())

        if newGlucose.isEmpty {
            self.countTimesWithoutData &+= 1
        } else {
            self.latestBackfill = glucose.max { $0.startDate < $1.startDate }
            self.logger.debug("dabear:: latestbackfill set to \(self.latestBackfill.debugDescription)")
            self.countTimesWithoutData = 0
        }

        //todo: predictions also for libre2 bluetooth data
        //self.latestPrediction = prediction?.first
        var predictions: [LibreGlucose] = []

        overcalibrate(entries: &newGlucose, prediction: &predictions)

        self.setObservables(sensorData: nil, bleData: bleData, metaData: device)

        self.logger.debug("dabear:: handleGoodReading returned with \(newGlucose.count) entries")
        self.delegateQueue.async {
            var result: Result<[LibreGlucose], Error>
            // If several readings from a valid and running sensor come out empty,
            // we have (with a large degree of confidence) a sensor that has been
            // ripped off the body
            if self.countTimesWithoutData > 1 {
                result = .failure(LibreError.noValidSensorData)
            } else {
                result = .success(newGlucose)
            }
            self.cgmManagerDelegate?.cgmManager(self, hasNew: result)
        }

        lastDirectUpdate = Date()

    }
}

// MARK: - Bluetooth transmitter data
extension LibreTransmitterManager {

    public func noLibreTransmitterSelected() {
        NotificationHelper.sendNoTransmitterSelectedNotification()
    }

    public func libreTransmitterDidUpdate(with sensorData: SensorData, and device: LibreTransmitterMetadata) {

        self.logger.debug("dabear:: got sensordata: \(String(describing: sensorData)), bytescount: \( sensorData.bytes.count), bytes: \(sensorData.bytes)")
        var sensorData = sensorData

        NotificationHelper.sendLowBatteryNotificationIfNeeded(device: device)
        self.setObservables(sensorData: sensorData, bleData: nil, metaData: device)

         if !sensorData.isLikelyLibre1FRAM {
            if let patchInfo = device.patchInfo, let sensorType = SensorType(patchInfo: patchInfo) {
                let needsDecryption = [SensorType.libre2, .libreUS14day].contains(sensorType)
                if needsDecryption, let uid = device.uid {
                    sensorData.decrypt(patchInfo: patchInfo, uid: uid)
                }
            } else {
                logger.debug("Sensor type was incorrect, and no decryption of sensor was possible")
                self.cgmManagerDelegate?.cgmManager(self, hasNew: .failure(LibreError.encryptedSensor))
                return
            }
        }

        let typeDesc = device.sensorType().debugDescription

        logger.debug("Transmitter connected to libresensor of type \(typeDesc). Details:  \(device.description)")

        tryPersistSensorData(with: sensorData)

        NotificationHelper.sendInvalidSensorNotificationIfNeeded(sensorData: sensorData)
        NotificationHelper.sendInvalidChecksumIfDeveloper(sensorData)



        guard sensorData.hasValidCRCs else {
            self.delegateQueue.async {
                self.cgmManagerDelegate?.cgmManager(self, hasNew: .failure(LibreError.checksumValidationError))
            }

            logger.debug("did not get sensordata with valid crcs")
            return
        }

        NotificationHelper.sendSensorExpireAlertIfNeeded(sensorData: sensorData)

        guard sensorData.state == .ready || sensorData.state == .starting else {
            logger.debug("dabear:: got sensordata with valid crcs, but sensor is either expired or failed")
            self.delegateQueue.async {
                self.cgmManagerDelegate?.cgmManager(self, hasNew: .failure(LibreError.expiredSensor))
            }
            return
        }

        logger.debug("dabear:: got sensordata with valid crcs, sensor was ready")
//        self.lastValidSensorData = sensorData


        self.handleGoodReading(data: sensorData) { [weak self] error, glucoseArrayWithPrediction in
            guard let self = self else {
                print("dabear:: handleGoodReading could not lock on self, aborting")
                return
            }
            if let error = error {
                self.logger.error("dabear:: handleGoodReading returned with error: \(error.errorDescription)")
                self.delegateQueue.async {
                    self.cgmManagerDelegate?.cgmManager(self, hasNew: .failure(error))
                }
                return
            }


            guard let glucose = glucoseArrayWithPrediction?.glucose else {
                self.logger.debug("dabear:: handleGoodReading returned with no data")
                self.delegateQueue.async {
                    self.cgmManagerDelegate?.cgmManager(self, hasNew: .success([]))
                }
                return
            }

            let prediction = glucoseArrayWithPrediction?.prediction



//            let device = self.proxy?.device
            let newGlucose = self.glucosesToSamplesFilter(glucose, startDate: self.getStartDateForFilter())



            if newGlucose.isEmpty {
                self.countTimesWithoutData &+= 1
            } else {
                self.latestBackfill = glucose.max { $0.startDate < $1.startDate }
                self.logger.debug("dabear:: latestbackfill set to \(self.latestBackfill.debugDescription)")
                self.countTimesWithoutData = 0
            }

            self.latestPrediction = prediction?.first

            //must be inside this handler as setobservables "depend" on latestbackfill
            self.setObservables(sensorData: sensorData, bleData: nil, metaData: nil)

            self.logger.debug("dabear:: handleGoodReading returned with \(newGlucose.count) entries")
            self.delegateQueue.async {
                var result: Result<[LibreGlucose], Error>
                // If several readings from a valid and running sensor come out empty,
                // we have (with a large degree of confidence) a sensor that has been
                // ripped off the body
                if self.countTimesWithoutData > 1 {
                    result = .failure(LibreError.noValidSensorData)
                } else {
                    result = .success(newGlucose)
                }
                self.cgmManagerDelegate?.cgmManager(self, hasNew: result)
            }
        }

    }
    private func readingToGlucose(_ data: SensorData, calibration: SensorData.CalibrationInfo) -> GlucoseArrayWithPrediction {

        var entries: [LibreGlucose] = []
        var prediction: [LibreGlucose] = []

        let predictGlucose = true

        // Increase to up to 15 to move closer to real blood sugar
        // The cost is slightly more noise on consecutive readings
        let glucosePredictionMinutes : Double = 10

        if predictGlucose {
            // We cheat here by forcing the loop to think that the predicted glucose value is the current blood sugar value.
            logger.debug("Predicting glucose value")
            if let predicted = data.predictBloodSugar(glucosePredictionMinutes){
                let currentBg = predicted.roundedGlucoseValueFromRaw2(calibrationInfo: calibration)
                let bgDate = predicted.date.addingTimeInterval(60 * -glucosePredictionMinutes)

                prediction.append(LibreGlucose(unsmoothedGlucose: currentBg, glucoseDouble: currentBg, timestamp: bgDate))
                logger.debug("Predicted glucose (not used) was: \(currentBg)")
            } else {
                logger.debug("Tried to predict glucose value but failed!")
            }

        }

        let trends = data.trendMeasurements()
        let firstTrend = trends.first?.roundedGlucoseValueFromRaw2(calibrationInfo: calibration)
        logger.debug("first trend was: \(String(describing: firstTrend))")
        entries = LibreGlucose.fromTrendMeasurements(trends, nativeCalibrationData: calibration, returnAll: UserDefaults.standard.mmBackfillFromTrend)

        if UserDefaults.standard.mmBackfillFromHistory {
            let history = data.historyMeasurements()
            entries += LibreGlucose.fromHistoryMeasurements(history, nativeCalibrationData: calibration)
        }

        overcalibrate(entries: &entries, prediction: &prediction)

        return (glucose: entries, prediction: prediction)
    }

    private func overcalibrate(entries: inout [LibreGlucose], prediction: inout [LibreGlucose]) {
        // overcalibrate
        var overcalibration: ((Double) -> (Double))? = nil
        delegateQueue.sync { overcalibration = cgmManagerDelegate?.overcalibration(for: self) }

        if let overcalibration = overcalibration {
            func overcalibrate(entries: [LibreGlucose]) -> [LibreGlucose] {
                entries.map { entry in
                    var entry = entry
                    entry.glucoseDouble = overcalibration(entry.glucoseDouble)
                    return entry
                }
            }

            entries = overcalibrate(entries: entries)
            prediction = overcalibrate(entries: prediction)
        }
    }

    public func handleGoodReading(data: SensorData?, _ callback: @escaping (LibreError?, GlucoseArrayWithPrediction?) -> Void) {
        //only care about the once per minute readings here, historical data will not be considered
        guard let data = data else {
            callback(.noSensorData, nil)
            return
        }


        if let calibrationdata = calibrationData {
            logger.debug("dabear:: calibrationdata loaded")

            if calibrationdata.isValidForFooterWithReverseCRCs == data.footerCrc.byteSwapped {
                logger.debug("dabear:: calibrationdata correct for this sensor, returning last values")

                callback(nil, readingToGlucose(data, calibration: calibrationdata))
                return
            } else {
                logger.debug("dabear:: calibrationdata incorrect for this sensor, calibrationdata.isValidForFooterWithReverseCRCs: \(calibrationdata.isValidForFooterWithReverseCRCs),  data.footerCrc.byteSwapped: \(data.footerCrc.byteSwapped)")
            }
        } else {
            logger.debug("dabear:: calibrationdata was nil")
        }

        calibrateSensor(sensordata: data) { [weak self] calibrationparams  in
            do {
                try KeychainManagerWrapper.standard.setLibreNativeCalibrationData(calibrationparams)
            } catch {
                NotificationHelper.sendCalibrationNotification(.invalidCalibrationData)
                callback(.invalidCalibrationData, nil)
                return
            }
            //here we assume success, data is not changed,
            //and we trust that the remote endpoint returns correct data for the sensor
            NotificationHelper.sendCalibrationNotification(.success)
            callback(nil, self?.readingToGlucose(data, calibration: calibrationparams))
        }
    }

    //will be called on utility queue
    public func libreTransmitterStateChanged(_ state: BluetoothmanagerState) {
        DispatchQueue.main.async {
            self.transmitterInfoObservable.connectionState = self.proxy?.connectionStateString ?? "n/a"
            self.transmitterInfoObservable.transmitterType = self.proxy?.shortTransmitterName ?? "Unknown"
        }
        switch state {
        case .Connected:
            lastConnected = Date()
        case .powerOff:
            NotificationHelper.sendBluetoothPowerOffNotification()
        default:
            break
        }
        return
    }

    //will be called on utility queue
    public func libreTransmitterReceivedMessage(_ messageIdentifier: UInt16, txFlags: UInt8, payloadData: Data) {
        guard let packet = MiaoMiaoResponseState(rawValue: txFlags) else {
            // Incomplete package?
            // this would only happen if delegate is called manually with an unknown txFlags value
            // this was the case for readouts that were not yet complete
            // but that was commented out in MiaoMiaoManager.swift, see comment there:
            // "dabear-edit: don't notify on incomplete readouts"
            logger.debug("dabear:: incomplete package or unknown response state")
            return
        }

        switch packet {
        case .newSensor:
            logger.debug("dabear:: new libresensor detected")
            NotificationHelper.sendSensorChangeNotificationIfNeeded()
            NotificationCenter.default.post(name: .newSensorDetected, object: nil)
        case .noSensor:
            logger.debug("dabear:: no libresensor detected")
            NotificationHelper.sendSensorNotDetectedNotificationIfNeeded(noSensor: true)
        case .frequencyChangedResponse:
            logger.debug("dabear:: transmitter readout interval has changed!")

        default:
            //we don't care about the rest!
            break
        }

        return
    }

    func tryPersistSensorData(with sensorData: SensorData) {
        guard UserDefaults.standard.shouldPersistSensorData else {
            return
        }

        //yeah, we really really need to persist any changes right away
        var data = UserDefaults.standard.queuedSensorData ?? LimitedQueue<SensorData>()
        data.enqueue(sensorData)
        UserDefaults.standard.queuedSensorData = data
    }
}

// MARK: - conventience properties to access the enclosed proxy's properties
extension LibreTransmitterManager {
    public var device: HKDevice? {
         //proxy?.OnQueue_device
        proxy?.device
    }

    static var className: String {
        String(describing: Self.self)
    }
    //cannot be called from managerQueue
    public var identifier: String {
        //proxy?.OnQueue_identifer?.uuidString ?? "n/a"
        proxy?.identifier?.uuidString ?? "n/a"
    }

    public var metaData: LibreTransmitterMetadata? {
        //proxy?.OnQueue_metadata
         proxy?.metadata
    }

    //cannot be called from managerQueue
    public var connectionState: String {
        //proxy?.connectionStateString ?? "n/a"
        proxy?.connectionStateString ?? "n/a"
    }
    //cannot be called from managerQueue
    public var sensorSerialNumber: String {
        //proxy?.OnQueue_sensorData?.serialNumber ?? "n/a"
        proxy?.sensorData?.serialNumber ?? "n/a"
    }

    //cannot be called from managerQueue
    public var sensorAge: String {
        //proxy?.OnQueue_sensorData?.humanReadableSensorAge ?? "n/a"
        proxy?.sensorData?.humanReadableSensorAge ?? "n/a"
    }

    public var sensorEndTime : String {
        if let endtime = proxy?.sensorData?.sensorEndTime  {
            let mydf = DateFormatter()
            mydf.dateStyle = .long
            mydf.timeStyle = .full
            mydf.locale = Locale.current
            return mydf.string(from: endtime)
        }
        return "Unknown or Ended"
    }

    public var sensorTimeLeft: String {
        //proxy?.OnQueue_sensorData?.humanReadableSensorAge ?? "n/a"
        proxy?.sensorData?.humanReadableTimeLeft ?? "n/a"
    }

    //cannot be called from managerQueue
    public var sensorFooterChecksums: String {
        //(proxy?.OnQueue_sensorData?.footerCrc.byteSwapped).map(String.init)
        (proxy?.sensorData?.footerCrc.byteSwapped).map(String.init)

            ?? "n/a"
    }



    //cannot be called from managerQueue
    public var sensorStateDescription: String {
        //proxy?.OnQueue_sensorData?.state.description ?? "n/a"
        proxy?.sensorData?.state.description ?? "n/a"
    }
    //cannot be called from managerQueue
    public var firmwareVersion: String {
        proxy?.metadata?.firmware ?? "n/a"
    }

    //cannot be called from managerQueue
    public var hardwareVersion: String {
        proxy?.metadata?.hardware ?? "n/a"
    }

    //cannot be called from managerQueue
    public var batteryString: String {
        proxy?.metadata?.batteryString ?? "n/a"
    }

    public var battery: Int? {
        proxy?.metadata?.battery
    }

    public func getDeviceType() -> String {
        proxy?.shortTransmitterName ?? "Unknown"
    }
    public func getSmallImage() -> UIImage? {
        proxy?.activePluginType?.smallImage ?? UIImage(named: "libresensor", in: Bundle.module, compatibleWith: nil)
    }
}
