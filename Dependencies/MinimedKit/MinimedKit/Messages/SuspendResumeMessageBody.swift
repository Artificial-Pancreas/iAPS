//
//  SuspendResumeMessageBody.swift
//  MinimedKit
//
//  Created by Pete Schwamb on 10/1/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation

public class SuspendResumeMessageBody: MessageBody {
    public static var length: Int = 65

    public var txData: Data

    public enum SuspendResumeState: UInt8 {
        case suspend = 0x01
        case resume = 0x00
    }

    let state: SuspendResumeState

    public init(state: SuspendResumeState) {
        self.state = state
        let numArgs = 1
        let data = Data(hexadecimalString: String(format: "%02x%02x", numArgs, state.rawValue))!
        self.txData = data.paddedTo(length: type(of: self).length)
    }

    public var description: String {
        return "SuspendResume(type:\(state)"
    }
}
