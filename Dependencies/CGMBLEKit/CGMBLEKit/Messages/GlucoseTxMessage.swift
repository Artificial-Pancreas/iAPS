//
//  GlucoseTxMessage.swift
//  xDrip5
//
//  Created by Nathan Racklyeft on 11/23/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


struct GlucoseTxMessage: RespondableMessage {
    typealias Response = GlucoseRxMessage

    var data: Data {
        return Data(for: .glucoseTx).appendingCRC()
    }
}
