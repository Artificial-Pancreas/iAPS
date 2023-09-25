//
//  OmniBLE.swift
//  OmniBLE
//
//  Created by Randall Knutson on 10/11/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import OSLog


public class OmniBLE {
    var manager: PeripheralManager
    var advertisement: PodAdvertisement?

    private let log = OSLog(category: "OmniBLE")

    init(peripheralManager: PeripheralManager, advertisement: PodAdvertisement?) {
        self.manager = peripheralManager        
        self.advertisement = advertisement
    }
}


extension OmniBLE: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "OmniBLE - advertisement: \(String(describing: advertisement))"
    }
}
