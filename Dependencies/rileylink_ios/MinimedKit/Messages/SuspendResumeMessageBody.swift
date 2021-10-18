//
//  SuspendResumeMessageBody.swift
//  MinimedKit
//
//  Created by Pete Schwamb on 10/1/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

public class SuspendResumeMessageBody: CarelinkLongMessageBody {
    
    public enum SuspendResumeState: UInt8 {
        case suspend = 0x01
        case resume = 0x00
    }
    
    public convenience init(state: SuspendResumeState) {
        let numArgs = 1
        let data = Data(hexadecimalString: String(format: "%02x%02x", numArgs, state.rawValue))!
        
        self.init(rxData: data)!
    }
    
}
