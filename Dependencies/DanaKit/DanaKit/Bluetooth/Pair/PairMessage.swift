//
//  PairMessage.swift
//  OmniBLE
//
//  Created by Randall Knutson on 8/4/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

struct PairMessage {
    public let sequenceNumber: UInt8
    public let source: Id
    public let destination: Id
    private let keys: [String]
    private let payloads: [Data]
    public let message: MessagePacket
    
    init(sequenceNumber: UInt8, source: Id, destination: Id, keys: [String], payloads: [Data]) {
        self.sequenceNumber = sequenceNumber
        self.source = source
        self.destination = destination
        self.keys = keys
        self.payloads = payloads
        message = MessagePacket(
            type: MessageType.PAIRING,
            source: source.toUInt32(),
            destination: destination.toUInt32(),
            payload: StringLengthPrefixEncoding.formatKeys(
                keys: keys,
                payloads: payloads
            ),
            sequenceNumber :sequenceNumber,
            sas: true
        )
    }
}
