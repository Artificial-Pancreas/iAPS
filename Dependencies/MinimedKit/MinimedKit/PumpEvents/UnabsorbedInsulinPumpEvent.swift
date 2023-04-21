//
//  UnabsorbedInsulinPumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/7/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct UnabsorbedInsulinPumpEvent: PumpEvent {
    
    public struct Record : DictionaryRepresentable {
        var amount: Double
        var age: Int
        
        init(amount: Double, age: Int) {
            self.amount = amount
            self.age = age
        }
        
        public var dictionaryRepresentation: [String: Any] {
            return [
                "amount": amount,
                "age": age,
            ]
        }
    }
    
    public let length: Int
    public let rawData: Data
    
    public let records: [Record]
    
    public init?(availableData: Data, pumpModel: PumpModel) {
        length = Int(max(availableData[1], 2))
        var records = [Record]()
        
        guard length <= availableData.count else {
            return nil
        }

        rawData = availableData.subdata(in: 0..<length)
        
        func d(_ idx: Int) -> Int {
            return Int(availableData[idx])
        }
        
        let numRecords = (d(1) - 2) / 3
        
        for idx in 0..<numRecords {
            let record = Record(
                amount:  Double(d(2 + idx * 3)) / 40,
                age: d(3 + idx * 3) + ((d(4 + idx * 3) & 0b110000) << 4))
            records.append(record)
        }

        self.records = records
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "UnabsorbedInsulin",
            "data": records.map({ (r: Record) -> [String: Any] in
                return r.dictionaryRepresentation
            }),
        ]
    }
}
