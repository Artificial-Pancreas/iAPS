//
//  UnknownGlucoseEvent.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 10/19/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct UnknownGlucoseEvent: GlucoseEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    private let op: String
    
    public init?(availableData: Data, relativeTimestamp: DateComponents) {
        length = 1
        
        guard length <= availableData.count else {
            return nil
        }
        
        rawData = availableData.subdata(in: 0..<length)
        op = rawData.hexadecimalString
        timestamp = relativeTimestamp
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "name": "Could Not Decode",
            "op": op
        ]
    }
}
