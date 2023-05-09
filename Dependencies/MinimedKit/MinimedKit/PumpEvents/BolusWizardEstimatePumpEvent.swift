//
//  BolusWizardEstimatePumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/8/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct BolusWizardEstimatePumpEvent: TimestampedPumpEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    public let carbohydrates: Int
    public let bloodGlucose: Int
    public let foodEstimate: Double
    public let correctionEstimate: Double
    public let bolusEstimate: Double
    public let unabsorbedInsulinTotal: Double
    public let bgTargetLow: Int
    public let bgTargetHigh: Int
    public let insulinSensitivity: Int
    public let carbRatio: Double
    
    public init?(availableData: Data, pumpModel: PumpModel) {
        
        func d(_ idx: Int) -> Int {
            return Int(availableData[idx])
        }
        
        func insulinDecode(_ a: Int, b: Int) -> Double {
            return Double((a << 8) + b) / 40.0
        }
        
        if pumpModel.larger {
            length = 22
        } else {
            length = 20
        }

        guard length <= availableData.count else {
            return nil
        }

        rawData = availableData.subdata(in: 0..<length)

        timestamp = DateComponents(pumpEventData: availableData, offset: 2)
        
        if pumpModel.larger {
            carbohydrates = ((d(8) & 0xc) << 6) + d(7)
            bloodGlucose = ((d(8) & 0x3) << 8) + d(1)
            foodEstimate = insulinDecode(d(14), b: d(15))
            correctionEstimate = Double(((d(16) & 0b111000) << 5) + d(13)) / 40.0
            bolusEstimate = insulinDecode(d(19), b: d(20))
            unabsorbedInsulinTotal = insulinDecode(d(17), b: d(18))
            bgTargetLow = d(12)
            bgTargetHigh = d(21)
            insulinSensitivity = d(11)
            carbRatio = Double(((d(9) & 0x7) << 8) + d(10)) / 10.0
        } else {
            carbohydrates = d(7)
            bloodGlucose = ((d(8) & 0x3) << 8) + d(1)
            foodEstimate = Double(d(13))/10.0
            correctionEstimate = Double((d(14) << 8) + d(12)) / 10.0
            bolusEstimate = Double(d(18))/10.0
            unabsorbedInsulinTotal = Double(d(16))/10.0
            bgTargetLow = d(11)
            bgTargetHigh = d(19)
            insulinSensitivity = d(10)
            carbRatio = Double(d(9))
        }
        
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "BolusWizardBolusEstimate",
            "bg": bloodGlucose,
            "bgTargetHigh": bgTargetHigh,
            "correctionEstimate": correctionEstimate,
            "carbInput": carbohydrates,
            "unabsorbedInsulinTotal": unabsorbedInsulinTotal,
            "bolusEstimate": bolusEstimate,
            "carbRatio": carbRatio,
            "foodEstimate": foodEstimate,
            "bgTargetLow": bgTargetLow,
            "insulinSensitivity": insulinSensitivity
        ]
    }
    
}
