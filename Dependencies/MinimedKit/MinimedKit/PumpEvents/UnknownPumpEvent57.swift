//
//  UnknownPumpEvent57.swift
//  MinimedKit
//
//  Created by Pete Schwamb on 8/11/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation

public struct UnknownPumpEvent57: TimestampedPumpEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    
    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 10
        
        guard length <= availableData.count else {
            return nil
        }
        
        rawData = availableData.subdata(in: 0..<length)
        timestamp = DateComponents(pumpEventData: availableData, offset: 2)
    }
    
    public var dictionaryRepresentation: [String: Any] {
        let name: String
        if let type = PumpEventType(rawValue: rawData[0]) {
            name = String(describing: type).components(separatedBy: ".").last!
        } else {
            name = "UnknownPumpEvent57(\(rawData[0]))"
        }
        
        return [
            "_type": name,
        ]
    }
}
