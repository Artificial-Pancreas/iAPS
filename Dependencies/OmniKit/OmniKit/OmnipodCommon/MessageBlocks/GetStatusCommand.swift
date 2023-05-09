//
//  GetStatusCommand.swift
//  OmniKit
//
//  Created by Pete Schwamb on 10/14/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import Foundation

public struct GetStatusCommand : MessageBlock {
    // OFF 1  2
    // Oe 01 TT

    public let blockType: MessageBlockType = .getStatus
    public let length: UInt8 = 1
    public let podInfoType: PodInfoResponseSubType

    public init(podInfoType: PodInfoResponseSubType = .normal) {
        self.podInfoType = podInfoType
    }
    
    public init(encodedData: Data) throws {
        if encodedData.count < 3 {
            throw MessageBlockError.notEnoughData
        }
        guard let podInfoType = PodInfoResponseSubType(rawValue: encodedData[2]) else {
            throw MessageError.unknownValue(value: encodedData[2], typeDescription: "PodInfoResponseSubType")
        }
        self.podInfoType = podInfoType
    }
        
    public var data:  Data {
        var data = Data([
            blockType.rawValue,
            length
            ])
        data.append(podInfoType.rawValue)
        return data
    }
}

extension GetStatusCommand: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "GetStatusCommand(\(podInfoType))"
    }
}
