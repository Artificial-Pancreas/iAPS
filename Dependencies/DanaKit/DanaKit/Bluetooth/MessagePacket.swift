//
//  MessagePacket.swift
//  OmniBLE
//
//  Created by Randall Knutson on 8/4/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//
import Foundation

enum MessageType: UInt8 {
    case CLEAR = 0, ENCRYPTED, SESSION_ESTABLISHMENT, PAIRING
}

struct MessagePacket {
    private static let MAGIC_PATTERN = "TW" // all messages start with this string
    private static let HEADER_SIZE = 16

    static func parse(payload: Data) throws -> MessagePacket {
        guard payload.count >= HEADER_SIZE else {
            throw PodProtocolError.couldNotParseMessageException("Incorrect header size")
        }

        guard (String(data: payload.subdata(in: 0..<2), encoding: .utf8) == MAGIC_PATTERN) else {
            throw PodProtocolError.couldNotParseMessageException("Magic pattern mismatch")
        }
        let payloadData = payload
        
        let f1 = Flag(payloadData[2])
        let sas = f1.get(3) != 0
        let tfs = f1.get(4) != 0
        let version = Int16(((f1.get(0) << 2) | (f1.get(1) << 1) | (f1.get(2) << 0)))
        let eqos = Int16((f1.get(7) | (f1.get(6) << 1) | (f1.get(5) << 2)))

        let f2 = Flag(payloadData[3])
        let ack = f2.get(0) != 0
        let priority = f2.get(1) != 0
        let lastMessage = f2.get(2) != 0
        let gateway = f2.get(3) != 0
        let type: MessageType = MessageType(rawValue: UInt8(f2.get(7) | (f2.get(6) << 1) | (f2.get(5) << 2) | (f2.get(4) << 3))) ?? .CLEAR
        if (version != 0) {
            throw PodProtocolError.couldNotParseMessageException("Wrong version")
        }
        let sequenceNumber = payloadData[4]
        let ackNumber = payloadData[5]
        let size = (UInt16(payloadData[6]) << 3) | (UInt16(payloadData[7]) >> 5)
        guard payload.count >= (Int(size) + MessagePacket.HEADER_SIZE) else {
            throw PodProtocolError.couldNotParseMessageException("Wrong payload size")
        }

        let payloadEnd = Int(16 + size + (type == MessageType.ENCRYPTED ? 8 : 0))

        return MessagePacket(
            type: type,
            source: Id(payload.subdata(in: 8..<12)).toUInt32(),
            destination: Id(payload.subdata(in: 12..<16)).toUInt32(),
            payload: payload.subdata(in: 16..<payloadEnd),
            sequenceNumber: sequenceNumber,
            ack: ack,
            ackNumber:ackNumber,
            eqos: eqos,
            priority: priority,
            lastMessage: lastMessage,
            gateway: gateway,
            sas: sas,
            tfs: tfs,
            version: version
        )
    }

    let type: MessageType
    var source: Id
    let destination: Id
    var payload: Data
    let sequenceNumber: UInt8
    let ack: Bool
    let ackNumber: UInt8
    let eqos: Int16
    let priority: Bool
    let lastMessage: Bool
    let gateway: Bool
    let sas: Bool // TODO: understand, seems to always be true
    let tfs: Bool // TODO: understand, seems to be false
    let version: Int16
    init(type: MessageType, source: UInt32, destination: UInt32, payload: Data, sequenceNumber: UInt8, ack: Bool = false, ackNumber: UInt8 = 0, eqos: Int16 = 0, priority: Bool = false, lastMessage: Bool = false, gateway: Bool = false, sas: Bool = true, tfs: Bool = false, version: Int16 = 0) {
        self.type = type
        self.source = Id.fromUInt32(source)
        self.destination = Id.fromUInt32(destination)
        self.payload = payload
        self.sequenceNumber = sequenceNumber
        self.ack = ack
        self.ackNumber = ackNumber
        self.eqos = eqos
        self.priority = priority
        self.lastMessage = lastMessage
        self.gateway = gateway
        self.sas = sas
        self.tfs = tfs
        self.version = version
    }

    func asData(forEncryption: Bool = false) -> Data {
        var bb = Data(capacity: 16 + payload.count)
        bb.append(MessagePacket.MAGIC_PATTERN.data(using: .utf8)!)

        let f1 = Flag()
        f1.set(0, self.version & 4 != 0)
        f1.set(1, self.version & 2 != 0)
        f1.set(2, self.version & 1 != 0)
        f1.set(3, self.sas)
        f1.set(4, self.tfs)
        f1.set(5, self.eqos & 4 != 0)
        f1.set(6, self.eqos & 2 != 0)
        f1.set(7, self.eqos & 1 != 0)

        let f2 = Flag()
        f2.set(0, self.ack)
        f2.set(1, self.priority)
        f2.set(2, self.lastMessage)
        f2.set(3, self.gateway)
        f2.set(4, self.type.rawValue & 8 != 0)
        f2.set(5, self.type.rawValue & 4 != 0)
        f2.set(6, self.type.rawValue & 2 != 0)
        f2.set(7, self.type.rawValue & 1 != 0)

        bb.append(f1.value)
        bb.append(f2.value)
        bb.append(self.sequenceNumber)
        bb.append(self.ackNumber)
        let size = payload.count - ((type == MessageType.ENCRYPTED && !forEncryption) ? 8 : 0)
        bb.append(UInt8(size >> 3))
        bb.append(UInt8((size << 5) & 0xff))
        bb.append(self.source.address)
        bb.append(self.destination.address)

        bb.append(self.payload)

        return bb
    }
}

private class Flag {
    var value: UInt8
    
    init(_ value: UInt8 = 0) {
        self.value = value
    }
    
    func set(_ idx: UInt8, _ set: Bool) {
        let mask: UInt8 = 1 << (7 - idx)
        if (!set) {
            return
        }
        value = value | mask
    }

    func get(_ idx: UInt8) -> UInt8 {
        let mask: UInt8 = 1 << (7 - idx)
        if (value & mask == 0) {
            return 0
        }
        return 1
    }
}
