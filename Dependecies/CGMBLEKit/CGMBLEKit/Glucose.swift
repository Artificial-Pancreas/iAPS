//
//  Glucose.swift
//  xDripG5
//
//  Created by Nate Racklyeft on 8/6/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


public struct Glucose {
    let glucoseMessage: GlucoseSubMessage
    let timeMessage: TransmitterTimeRxMessage

    init(
        transmitterID: String,
        glucoseMessage: GlucoseRxMessage,
        timeMessage: TransmitterTimeRxMessage,
        calibrationMessage: CalibrationDataRxMessage? = nil,
        activationDate: Date
    ) {
        self.init(
            transmitterID: transmitterID,
            status: glucoseMessage.status,
            glucoseMessage: glucoseMessage.glucose,
            timeMessage: timeMessage,
            calibrationMessage: calibrationMessage,
            activationDate: activationDate
        )
    }

    init(
        transmitterID: String,
        status: UInt8,
        glucoseMessage: GlucoseSubMessage,
        timeMessage: TransmitterTimeRxMessage,
        calibrationMessage: CalibrationDataRxMessage? = nil,
        activationDate: Date
    ) {
        self.transmitterID = transmitterID
        self.glucoseMessage = glucoseMessage
        self.timeMessage = timeMessage
        self.status = TransmitterStatus(rawValue: status)
        self.activationDate = activationDate

        sessionStartDate = activationDate.addingTimeInterval(TimeInterval(timeMessage.sessionStartTime))
        readDate = activationDate.addingTimeInterval(TimeInterval(glucoseMessage.timestamp))
        lastCalibration = calibrationMessage != nil ? Calibration(calibrationMessage: calibrationMessage!, activationDate: activationDate) : nil
    }

    // MARK: - Transmitter Info
    public let transmitterID: String
    public let status: TransmitterStatus
    public let activationDate: Date
    public let sessionStartDate: Date

    // MARK: - Glucose Info
    public let lastCalibration: Calibration?
    public let readDate: Date

    public var isDisplayOnly: Bool {
        return glucoseMessage.glucoseIsDisplayOnly
    }

    public var glucose: HKQuantity? {
        guard state.hasReliableGlucose && glucoseMessage.glucose >= 39 else { 
            return nil
        }

        let unit = HKUnit.milligramsPerDeciliter

        return HKQuantity(unit: unit, doubleValue: Double(glucoseMessage.glucose))
    }

    public var state: CalibrationState {
        return CalibrationState(rawValue: glucoseMessage.state)
    }

    public var trend: Int {
        return Int(glucoseMessage.trend)
    }

    public var trendRate: HKQuantity? {
        guard glucoseMessage.trend < Int8.max && glucoseMessage.trend > Int8.min else {
            return nil
        }

        let unit = HKUnit.milligramsPerDeciliterPerMinute
        return HKQuantity(unit: unit, doubleValue: Double(glucoseMessage.trend) / 10)
    }

    // An identifier for this reading thatʼs consistent between backfill/live data
    public var syncIdentifier: String {
        return "\(transmitterID) \(glucoseMessage.timestamp)"
    }
}


extension Glucose: Equatable {
    public static func ==(lhs: Glucose, rhs: Glucose) -> Bool {
        return lhs.glucoseMessage == rhs.glucoseMessage && lhs.syncIdentifier == rhs.syncIdentifier
    }
}
