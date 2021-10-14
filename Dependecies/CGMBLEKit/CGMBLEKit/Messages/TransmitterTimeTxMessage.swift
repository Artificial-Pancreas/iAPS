//
//  TransmitterTimeTxMessage.swift
//  xDrip5
//
//  Created by Nathan Racklyeft on 11/23/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


struct TransmitterTimeTxMessage: RespondableMessage {
    typealias Response = TransmitterTimeRxMessage

    var data: Data {
        return Data(for: .transmitterTimeTx).appendingCRC()
    }
}
