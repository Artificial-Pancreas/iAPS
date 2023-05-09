//
//  BolusNormalPumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/7/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct BolusNormalPumpEvent: TimestampedPumpEvent {

    public enum BolusType: String {
        case normal = "Normal"
        case square = "Square"
    }

    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    public var unabsorbedInsulinRecord: UnabsorbedInsulinPumpEvent?
    public let amount: Double
    public let programmed: Double
    public let unabsorbedInsulinTotal: Double
    public let type: BolusType
    public let duration: TimeInterval
    public let wasRemotelyTriggered: Bool
    
    public init(length: Int, rawData: Data, timestamp: DateComponents, unabsorbedInsulinRecord: UnabsorbedInsulinPumpEvent?, amount: Double, programmed: Double, unabsorbedInsulinTotal: Double, type: BolusType, duration: TimeInterval, wasRemotelyTriggered: Bool) {
        self.length = length
        self.rawData = rawData
        self.timestamp = timestamp
        self.unabsorbedInsulinRecord = unabsorbedInsulinRecord
        self.amount = amount
        self.programmed = programmed
        self.unabsorbedInsulinTotal = unabsorbedInsulinTotal
        self.type = type
        self.duration = duration
        self.wasRemotelyTriggered = wasRemotelyTriggered
    }

    /*
     It takes a MM pump about 40s to deliver 1 Unit while bolusing
     See: http://www.healthline.com/diabetesmine/ask-dmine-speed-insulin-pumps#3
     */
    private let deliveryUnitsPerMinute = 1.5

    // The actual expected time of delivery, based on bolus speed
    public var deliveryTime: TimeInterval {
        if duration > 0 {
            return duration
        } else {
            return TimeInterval(minutes: programmed / deliveryUnitsPerMinute)
        }
    }
    
    public init?(availableData: Data, pumpModel: PumpModel) {
        
        func doubleValueFromData(at index: Int) -> Double {
            return Double(availableData[index])
        }
        
        func decodeInsulin(from bytes: Data) -> Double {
            return Double(Int(bigEndianBytes: bytes)) / Double(pumpModel.insulinBitPackingScale)
        }
        
        length = BolusNormalPumpEvent.calculateLength(pumpModel.larger)
        
        guard length <= availableData.count else {
            return nil
        }

        rawData = availableData.subdata(in: 0..<length)
        
        if pumpModel.larger {
            timestamp = DateComponents(pumpEventData: availableData, offset: 8)
            wasRemotelyTriggered = availableData[11] & 0b01000000 != 0
            programmed = decodeInsulin(from: availableData.subdata(in: 1..<3))
            amount = decodeInsulin(from: availableData.subdata(in: 3..<5))
            unabsorbedInsulinTotal = decodeInsulin(from: availableData.subdata(in: 5..<7))
            duration = TimeInterval(minutes: 30 * doubleValueFromData(at: 7))
        } else {
            timestamp = DateComponents(pumpEventData: availableData, offset: 4)
            wasRemotelyTriggered = availableData[7] & 0b01000000 != 0
            programmed = decodeInsulin(from: availableData.subdata(in: 1..<2))
            amount = decodeInsulin(from: availableData.subdata(in: 2..<3))
            duration = TimeInterval(minutes: 30 * doubleValueFromData(at: 3))
            unabsorbedInsulinTotal = 0
        }
        type = duration > 0 ? .square : .normal
    }

    func isMutable(atDate date: Date = Date(), forPump model: PumpModel) -> Bool {
        let deliveryFinishDate = date.addingTimeInterval(deliveryTime)
        return model.appendsSquareWaveToHistoryOnStartOfDelivery && type == .square && deliveryFinishDate > date
    }

    public var dictionaryRepresentation: [String: Any] {
        var dictionary: [String: Any] = [
            "_type": "BolusNormal",
            "amount": amount,
            "programmed": programmed,
            "type": type.rawValue,
            "wasRemotelyTriggered": wasRemotelyTriggered,
        ]
        
        if let unabsorbedInsulinRecord = unabsorbedInsulinRecord {
            dictionary["appended"] = unabsorbedInsulinRecord.dictionaryRepresentation
        }
        
        if unabsorbedInsulinTotal > 0 {
            dictionary["unabsorbed"] = unabsorbedInsulinTotal
        }
        
        if duration > 0 {
            dictionary["duration"] = duration
        }
        
        return dictionary
    }
    
    public static func calculateLength(_ isLarger:Bool) -> Int {
        if isLarger {
            return 13
        } else {
            return  9
        }
    }
}
