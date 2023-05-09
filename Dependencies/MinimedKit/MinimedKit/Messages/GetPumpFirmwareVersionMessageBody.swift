//
//  GetPumpFirmwareVersionMessageBody.swift
//  MinimedKit
//
//  Created by Pete Schwamb on 10/10/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation

public class GetPumpFirmwareVersionMessageBody: CarelinkLongMessageBody {
    public let version: String
    
    public required init?(rxData: Data) {
        let stringEnd = rxData.firstIndex(of: 0) ?? rxData.count
        guard rxData.count == type(of: self).length,
            let vsn = String(data: rxData.subdata(in: 1..<stringEnd), encoding: String.Encoding.ascii) else {
                return nil
        }
        version = vsn
        super.init(rxData: rxData)
    }
    
    public required init?(rxData: NSData) {
        fatalError("init(rxData:) has not been implemented")
    }
}
