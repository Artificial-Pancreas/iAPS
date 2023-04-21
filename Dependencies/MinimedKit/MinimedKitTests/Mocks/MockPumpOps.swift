//
//  MockPumpOps.swift
//  MinimedKitTests
//
//  Created by Pete Schwamb on 9/5/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import MinimedKit
import RileyLinkBLEKit

class MockPumpOps: PumpOps, PumpOpsSessionDelegate {

    let queue = DispatchQueue(label: "MockPumpOps")

    var pumpState: PumpState

    var pumpSettings: PumpSettings

    var messageSender: MockPumpMessageSender

    func pumpOpsSession(_ session: MinimedKit.PumpOpsSession, didChange state: MinimedKit.PumpState) {
        pumpState = state
    }

    func pumpOpsSessionDidChangeRadioConfig(_ session: MinimedKit.PumpOpsSession) { }

    public func runSession(withName name: String, using device: RileyLinkDevice, _ block: @escaping (_ session: PumpOpsSession) -> Void) {
        let session = PumpOpsSession(settings: self.pumpSettings, pumpState: self.pumpState, messageSender: messageSender, delegate: self)
        queue.async {
            block(session)
        }
    }

    init(pumpState: PumpState, pumpSettings: PumpSettings, messageSender: MockPumpMessageSender = MockPumpMessageSender()) {
        self.pumpState = pumpState
        self.pumpSettings = pumpSettings
        self.messageSender = messageSender
    }
}
