//
//  PumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/7/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public protocol PumpEvent : DictionaryRepresentable {
    
    init?(availableData: Data, pumpModel: PumpModel)
    
    var rawData: Data {
        get
    }

    var length: Int {
        get
    }
    
}

public extension PumpEvent {
    func isDelayedAppend(with pumpModel: PumpModel) -> Bool {
        // Delays only occur for bolus events
        guard let bolus = self as? BolusNormalPumpEvent else {
            return false
        }

        // All normal bolus events are delayed
        guard bolus.type == .square else {
            return true
        }

        // Square-wave bolus events are delayed for certain pump models
        return !pumpModel.appendsSquareWaveToHistoryOnStartOfDelivery
    }
}
