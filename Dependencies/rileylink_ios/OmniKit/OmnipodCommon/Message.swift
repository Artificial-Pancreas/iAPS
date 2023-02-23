//
//  Message.swift
//  OmniKit
//
//  Created by Pete Schwamb on 10/14/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import Foundation

public enum MessageError: Error {
    case notEnoughData
    case invalidCrc
    case invalidSequence
    case invalidAddress(address: UInt32)
    case parsingError(offset: Int, data: Data, error: Error)
    case unknownValue(value: UInt8, typeDescription: String)
    case validationFailed(description: String)
}

extension MessageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notEnoughData:
            return LocalizedString("Not enough data", comment: "Description for MessageError notEnoughData")
        case .invalidCrc:
            return LocalizedString("Invalid CRC", comment: "Description for MessageError invalidCrc")
        case .invalidSequence:
            return LocalizedString("Unexpected message sequence number", comment: "Description for MessageError invalidSequence")
        case .invalidAddress(address: let address):
            return String(format: LocalizedString("Invalid address: (%1$@)", comment: "Description for MessageError invalidAddress"), String(format: "%08x", address))
        case .parsingError(let offset, let data, let error):
            return String(format: LocalizedString("Parsing Error: %1$@ in (%2$@)", comment: "Description for MessageError parsingError. (1: decription of error), (2: hexadecimal data starting at offset)"), String(describing: error), data.suffix(from: offset).hexadecimalString)
        case .unknownValue(let value, let typeDescription):
            return String(format: LocalizedString("Unknown Value (%1$@) for type %2$@", comment: "Format string for description of MessageError unknownValue. (1: value) (2: Type)"), String(describing: value), typeDescription)
        case .validationFailed(let description):
            return String(format: LocalizedString("Validation failed: %1$@", comment: "Format string for description of MessageError validationFailed. (1: description of validation failure)"), description)
        }
    }
}

struct Message {
    let address: UInt32
    let messageBlocks: [MessageBlock]
    let sequenceNum: Int
    let expectFollowOnMessage: Bool
    
    init(address: UInt32, messageBlocks: [MessageBlock], sequenceNum: Int, expectFollowOnMessage: Bool = false) {
        self.address = address
        self.messageBlocks = messageBlocks
        self.sequenceNum = sequenceNum
        self.expectFollowOnMessage = expectFollowOnMessage
    }
    
    init(encodedData: Data, checkCRC: Bool = true) throws {
        guard encodedData.count >= 10 else {
            throw MessageError.notEnoughData
        }
        self.address = encodedData[0...].toBigEndian(UInt32.self)
        let b9 = encodedData[4]
        let bodyLen = encodedData[5]
        
        if bodyLen > encodedData.count - 8 {
            throw MessageError.notEnoughData
        }
        
        self.expectFollowOnMessage = (b9 & 0b10000000) != 0
        self.sequenceNum = Int((b9 >> 2) & 0b1111)
        let crc = (UInt16(encodedData[encodedData.count-2]) << 8) + UInt16(encodedData[encodedData.count-1])
        let msgWithoutCrc = encodedData.prefix(encodedData.count - 2)
        if checkCRC {
            guard msgWithoutCrc.crc16() == crc else {
                throw MessageError.invalidCrc
            }
        }
        self.messageBlocks = try Message.decodeBlocks(data: Data(msgWithoutCrc.suffix(from: 6)))
    }
    
    static private func decodeBlocks(data: Data) throws -> [MessageBlock]  {
        var blocks = [MessageBlock]()
        var idx = 0
        repeat {
            guard let blockType = MessageBlockType(rawValue: data[idx]) else {
                throw MessageBlockError.unknownBlockType(rawVal: data[idx])
            }
            do {
                let block = try blockType.blockType.init(encodedData: Data(data.suffix(from: idx)))
                blocks.append(block)
                idx += Int(block.data.count)
            } catch (let error) {
                throw MessageError.parsingError(offset: idx, data: data.suffix(from: idx), error: error)
            }
        } while idx < data.count
        return blocks
    }
    
    func encoded() -> Data {
        var bytes = Data(bigEndian: address)
        
        var cmdData = Data()
        for cmd in messageBlocks {
            cmdData.append(cmd.data)
        }
        
        let b9: UInt8 = ((expectFollowOnMessage ? 1 : 0) << 7) + (UInt8(sequenceNum & 0b1111) << 2) + UInt8((cmdData.count >> 8) & 0b11)
        bytes.append(b9)
        bytes.append(UInt8(cmdData.count & 0xff))
        
        var data = Data(bytes) + cmdData
        let crc: UInt16 = data.crc16()
        data.appendBigEndian(crc)
        return data
    }
    
    var fault: DetailedStatus? {
        if messageBlocks.count > 0 && messageBlocks[0].blockType == .podInfoResponse,
            let infoResponse = messageBlocks[0] as? PodInfoResponse,
            infoResponse.podInfoResponseSubType == .detailedStatus,
            let detailedStatus = infoResponse.podInfo as? DetailedStatus,
            detailedStatus.isFaulted
        {
            return detailedStatus
        } else {
            return nil
        }
    }
}

extension Message: CustomDebugStringConvertible {
    var debugDescription: String {
        let sequenceNumStr = String(format: "%02d", sequenceNum)
        return "Message(\(Data(bigEndian: address).hexadecimalString) seq:\(sequenceNumStr) \(messageBlocks))"
    }
}
