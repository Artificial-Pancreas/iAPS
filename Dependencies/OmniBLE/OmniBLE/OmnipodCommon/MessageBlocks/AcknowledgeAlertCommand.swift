//
//  AcknowledgeAlertCommand.swift
//  OmniBLE
//
//  From OmniKit/MessageTransport/MessageBlocks/AcknowledgeAlertCommand.swift
//  Created by Eelke Jager on 18/09/2018.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

public struct AcknowledgeAlertCommand : NonceResyncableMessageBlock {
    // OFF 1  2 3 4 5  6
    // 11 05 NNNNNNNN MM

    public let blockType: MessageBlockType = .acknowledgeAlert
    public let length: UInt8 = 5
    public var nonce: UInt32
    public let alerts: AlertSet
    
    public init(nonce: UInt32, alerts: AlertSet) {
        self.nonce = nonce
        self.alerts = alerts
    }
    
    public init(encodedData: Data) throws {
        if encodedData.count < 7 {
            throw MessageBlockError.notEnoughData
        }
        self.nonce = encodedData[2...].toBigEndian(UInt32.self)
        self.alerts = AlertSet(rawValue: encodedData[6])
    }
    
    public var data:  Data {
        var data = Data([
            blockType.rawValue,
            length
            ])
        data.appendBigEndian(nonce)
        data.append(alerts.rawValue)
        return data
    }
}

extension AcknowledgeAlertCommand: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "AcknowledgeAlertCommand(blockType:\(blockType), length:\(length), alerts:\(alerts))"
    }
}
