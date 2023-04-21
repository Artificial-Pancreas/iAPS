//
//  MySentryAckMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/4/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


/// Describes an ACK message sent by a MySentry device in response to pump status messages.
/// a2 350535 06 59 000695 00 04 00 00 00 e2
public struct MySentryAckMessageBody: MessageBody {
    public static let length = 9

    let sequence: UInt8
    let mySentryID: Data
    let responseMessageTypes: [MessageType]

    public init?(sequence: UInt8, watchdogID: Data, responseMessageTypes: [MessageType]) {
        guard responseMessageTypes.count <= 4 && watchdogID.count == 3 else {
            return nil
        }

        self.sequence = sequence
        self.mySentryID = watchdogID
        self.responseMessageTypes = responseMessageTypes
    }

    public init?(rxData: Data) {
        guard rxData.count == type(of: self).length else {
            return nil
        }

        sequence = rxData[0]
        mySentryID = rxData.subdata(in: 1..<4)
        responseMessageTypes = rxData[5..<9].compactMap({ MessageType(rawValue: $0) })
    }

    public var txData: Data {
        var buffer = [UInt8](repeating: 0, count: type(of: self).length)

        buffer[0] = sequence
        buffer.replaceSubrange(1..<4, with: mySentryID[0..<3])

        buffer.replaceSubrange(5..<5 + responseMessageTypes.count, with: responseMessageTypes.map({ $0.rawValue }))

        return Data(buffer)
    }

    public var description: String {
        return "MySentryAck(\(sequence), \(mySentryID.hexadecimalString), \(responseMessageTypes))"
    }

}
