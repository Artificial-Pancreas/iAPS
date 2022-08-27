//
//  PodAdvertisement.swift
//  OmniBLE
//
//  Created by Pete Schwamb on 1/13/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import CoreBluetooth

struct PodAdvertisement {
    let MAIN_SERVICE_UUID = "4024"
    let UNKNOWN_THIRD_SERVICE_UUID = "000A"
    
    var sequenceNo: UInt32
    var lotNo: UInt64
    var podId: UInt32

    var serviceUUIDs: [CBUUID]

    var pairable: Bool {
        return serviceUUIDs.count >= 5 && serviceUUIDs[3].uuidString == "FFFF" && serviceUUIDs[4].uuidString == "FFFE"
    }
    
    init?(_ advertisementData: [String: Any]) {
        guard var serviceUUIDs = advertisementData["kCBAdvDataServiceUUIDs"] as? [CBUUID] else {
            return nil
        }

        self.serviceUUIDs = serviceUUIDs
        
        // For some reason the pod simulator doesn't have two values.
        if serviceUUIDs.count == 7 {
            serviceUUIDs.append(CBUUID(string: "abcd"))
            serviceUUIDs.append(CBUUID(string: "dcba"))
        }
        
        guard serviceUUIDs.count == 9 else {
            return nil
        }
        
        guard serviceUUIDs[0].uuidString == MAIN_SERVICE_UUID else {
            return nil
        }
        
        // TODO understand what is serviceUUIDs[1]. 0x2470. Alarms?
        guard serviceUUIDs[2].uuidString == UNKNOWN_THIRD_SERVICE_UUID else {
            return nil
        }
        
        guard let decodedPodId = UInt32(serviceUUIDs[3].uuidString + serviceUUIDs[4].uuidString, radix: 16) else {
            return nil
        }
        podId = decodedPodId

        let lotNoString: String = serviceUUIDs[5].uuidString + serviceUUIDs[6].uuidString + serviceUUIDs[7].uuidString
        guard let decodedLotNo =  UInt64(lotNoString[lotNoString.startIndex..<lotNoString.index(lotNoString.startIndex, offsetBy: 10)], radix: 16) else {
            return nil
        }
        lotNo = decodedLotNo
        
        let lotSeqString: String = serviceUUIDs[7].uuidString + serviceUUIDs[8].uuidString
        guard let decodedSeqNo = UInt32(lotSeqString[lotSeqString.index(lotSeqString.startIndex, offsetBy: 2)..<lotSeqString.endIndex], radix: 16) else {
            return nil
        }
        sequenceNo = decodedSeqNo
    }
}
