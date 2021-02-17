//
//  Packet.swift
//  OmniKit
//
//  Created by Pete Schwamb on 10/14/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//
import Foundation

public enum PacketError: Error {
    case insufficientData
    case crcMismatch
    case unknownPacketType(rawType: UInt8)
}


public enum PacketType: UInt8 {
    case pod = 0b111
    case pdm = 0b101
    case con = 0b100
    case ack = 0b010
    
    func maxBodyLen() -> Int {
        switch self {
        case .ack:
            return 4
        case .con, .pdm, .pod:
            return 31
        }
    }
}

public struct Packet {

    let address: UInt32
    let packetType: PacketType
    let sequenceNum: Int
    let data: Data
    
    init(address: UInt32, packetType: PacketType, sequenceNum: Int, data: Data = Data()) {
        self.address = address
        self.packetType = packetType
        self.sequenceNum = sequenceNum
        
        let bodyMaxLen = packetType.maxBodyLen()
        if data.count > bodyMaxLen {
            self.data = data.subdata(in: 0..<bodyMaxLen)
        } else {
            self.data = data
        }
    }
    
    init(encodedData: Data) throws {
        guard encodedData.count >= 7 else {
            // Not enough data for packet
            throw PacketError.insufficientData
        }
        
        self.address = encodedData[0...].toBigEndian(UInt32.self)
        
        guard let packetType = PacketType(rawValue: encodedData[4] >> 5) else {
            throw PacketError.unknownPacketType(rawType: encodedData[4])
        }
        self.packetType = packetType
        self.sequenceNum = Int(encodedData[4] & 0b11111)
        
        let len = encodedData.count

        // Check crc
        guard encodedData[0..<len-1].crc8() == encodedData[len-1] else {
            // Invalid CRC
            throw PacketError.crcMismatch
        }
        
        self.data = encodedData.subdata(in: 5..<len-1)
    }
    
    func encoded() -> Data {
        var output = Data(bigEndian: address)
        output.append(UInt8(packetType.rawValue << 5) + UInt8(sequenceNum & 0b11111))
        output.append(data)
        output.append(output.crc8())
        return output
    }
}

extension Packet: CustomDebugStringConvertible {
    public var debugDescription: String {
        let sequenceNumStr = String(format: "%02d", sequenceNum)
        return "Packet(\(Data(bigEndian: address).hexadecimalString) packetType:\(packetType) seq:\(sequenceNumStr) data:\(data.hexadecimalString))"
    }
}

