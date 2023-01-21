//
//  ReadRemainingInsulinMessageBody.swift
//  RileyLink
//
//  Created by Nathan Racklyeft on 5/25/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public class ReadRemainingInsulinMessageBody: DecodableMessageBody {
    public var txData: Data { return rxData }

    public var rxData: Data

    public static var length: Int = 65

    public func getUnitsRemaining(insulinBitPackingScale: Int) -> Double {

        let strokes: Data

        switch insulinBitPackingScale {
        case let x where x > 10:
            strokes = rxData.subdata(in: 3..<5)
        default:
            strokes = rxData.subdata(in: 1..<3)
        }

        return Double(Int(bigEndianBytes: strokes)) / Double(insulinBitPackingScale)
    }

    public required init?(rxData: Data) {
        guard rxData.count == type(of: self).length else {
            return nil
        }
        self.rxData = rxData
    }

    init(reservoirVolume: Double, insulinBitPackingScale: Int) {
        rxData = Data().paddedTo(length: Self.length)
        let scaledAmount = Int(reservoirVolume * Double(insulinBitPackingScale))
        let strokesData = Data(bigEndian: scaledAmount)
        let offset = insulinBitPackingScale > 10 ? 3 : 1
        rxData[offset] = strokesData[6]
        rxData[offset+1] = strokesData[7]
    }

    public var description: String {
        return "ReadRemainingInsulin(x23:\(getUnitsRemaining(insulinBitPackingScale: PumpModel.model523.insulinBitPackingScale)), x22:\(getUnitsRemaining(insulinBitPackingScale: PumpModel.model522.insulinBitPackingScale)))"
    }

}
