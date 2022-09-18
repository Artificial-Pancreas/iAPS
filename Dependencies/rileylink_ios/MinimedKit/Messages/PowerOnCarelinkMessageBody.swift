//
//  PowerOnCarelinkMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 12/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public struct PowerOnCarelinkMessageBody: MessageBody {
    public static var length: Int = 65

    public var txData: Data
    let duration: TimeInterval

    public init(duration: TimeInterval) {
        self.duration = duration
        let numArgs = 2
        let on = 1
        let durationMinutes: Int = Int(ceil(duration / 60.0))
        self.txData = Data(hexadecimalString: String(format: "%02x%02x%02x", numArgs, on, durationMinutes))!.paddedTo(length: PowerOnCarelinkMessageBody.length)
    }

    public var description: String {
        return "PowerOn(duration:\(duration))"
    }
}
