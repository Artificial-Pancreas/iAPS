//
//  PlaceholderMessageBlock.swift
//  OmniKit
//
//  Created by Pete Schwamb on 10/24/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import Foundation

public struct PlaceholderMessageBlock: MessageBlock {
    public let blockType: MessageBlockType
    public let length: UInt8
    
    public let data: Data
    
    public init(encodedData: Data) throws {
        if encodedData.count < 2 {
            throw MessageBlockError.notEnoughData
        }
        guard let blockType = MessageBlockType(rawValue: encodedData[0]) else {
            throw MessageBlockError.unknownBlockType(rawVal: encodedData[0])
        }
        self.blockType = blockType
        length = encodedData[1]
        data = encodedData.prefix(upTo: Int(length))
    }
}

