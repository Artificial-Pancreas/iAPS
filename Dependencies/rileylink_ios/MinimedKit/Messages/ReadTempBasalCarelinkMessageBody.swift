//
//  ReadTempBasalCarelinkMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/7/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public class ReadTempBasalCarelinkMessageBody: CarelinkLongMessageBody {

    // MMX12 and above
    private static let strokesPerUnit = 40

    public enum RateType {
        case absolute
        case percent
    }

    public let timeRemaining: TimeInterval
    public let rate: Double
    public let rateType: RateType

    public required init?(rxData: Data) {
        guard rxData.count == type(of: self).length else {
            return nil
        }

        let rawRateType: UInt8 = rxData[1]
        switch rawRateType {
        case 0:
            rateType = .absolute
            let strokes = Int(bigEndianBytes: rxData.subdata(in: 3..<5))
            rate = Double(strokes) / Double(type(of: self).strokesPerUnit)
        case 1:
            rateType = .percent
            let rawRate: UInt8 = rxData[2]
            rate = Double(rawRate)
        default:
            return nil
        }

        let minutesRemaining = Int(bigEndianBytes: rxData.subdata(in: 5..<7))
        timeRemaining = TimeInterval(minutesRemaining * 60)

        super.init(rxData: rxData)
    }

    public required init?(rxData: NSData) {
        fatalError("init(rxData:) has not been implemented")
    }
}
