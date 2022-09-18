//
//  ChangeTempBasalCarelinkMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/6/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public class ChangeTempBasalCarelinkMessageBody: MessageBody {
    public static var length: Int = 65

    public var txData: Data

    let unitsPerHour: Double
    let duration: TimeInterval

    public init(unitsPerHour: Double, duration: TimeInterval) {

        self.unitsPerHour = unitsPerHour
        self.duration = duration

        let length = 3
        let strokesPerUnit: Double = 40
        let strokes = Int(unitsPerHour * strokesPerUnit)
        let timeSegments = Int(duration / TimeInterval(30 * 60))

        let data = Data(hexadecimalString: String(format: "%02x%04x%02x", length, strokes, timeSegments))!

        self.txData = data.paddedTo(length: type(of: self).length)
    }

    public var description: String {
        return "ChangeTempBasal(rate:\(unitsPerHour) U/hr duration:\(duration)"
    }

}
