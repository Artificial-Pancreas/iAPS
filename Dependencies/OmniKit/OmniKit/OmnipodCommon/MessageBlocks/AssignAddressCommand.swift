//
//  AssignAddressCommand.swift
//  OmniKit
//
//  Created by Pete Schwamb on 2/12/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

public struct AssignAddressCommand : MessageBlock {
    
    public let blockType: MessageBlockType = .assignAddress
    public let length: Int = 6
    
    let address: UInt32

    public var data: Data {
        var data = Data([
            blockType.rawValue,
            4
        ])
        data.appendBigEndian(self.address)
        return data
    }

    public init(encodedData: Data) throws {
        if encodedData.count < length {
            throw MessageBlockError.notEnoughData
        }
        
        self.address = encodedData[2...].toBigEndian(UInt32.self)
    }
    
    public init(address: UInt32) {
        self.address = address
    }
}

extension AssignAddressCommand: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "AssignAddressCommand(address:\(Data(bigEndian: address).hexadecimalString))"
    }
}
