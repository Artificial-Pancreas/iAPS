//
//  ChangeMaxBolusMessageBody.swift
//  MinimedKit
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation


public class ChangeMaxBolusMessageBody: CarelinkLongMessageBody {

    static let multiplier: Double = 10

    public convenience init?(pumpModel: PumpModel, maxBolusUnits: Double) {
        guard maxBolusUnits >= 0 && maxBolusUnits <= 25 else {
            return nil
        }

        var data = Data()

        if pumpModel.usesTwoBytesForMaxBolus {
            let ticks = UInt16(maxBolusUnits * type(of: self).multiplier)
            data.appendBigEndian(ticks)
        } else {
            let ticks = UInt8(maxBolusUnits * type(of: self).multiplier)
            data.appendBigEndian(ticks)
        }

        let length = UInt8(clamping: data.count)
        data.insert(length, at: 0)

        self.init(rxData: data)
    }

}
