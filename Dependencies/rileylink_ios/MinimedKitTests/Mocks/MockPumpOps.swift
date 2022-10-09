//
//  MockPumpOps.swift
//  MinimedKitTests
//
//  Created by Pete Schwamb on 9/5/22.
//  Copyright © 2022 Pete Schwamb. All rights reserved.
//

import Foundation
import MinimedKit
import RileyLinkBLEKit

class MockPumpOps: PumpOps, PumpOpsSessionDelegate {

    var pumpState: PumpState

    var pumpSettings: PumpSettings

    func pumpOpsSession(_ session: MinimedKit.PumpOpsSession, didChange state: MinimedKit.PumpState) {
        pumpState = state
    }

    func pumpOpsSessionDidChangeRadioConfig(_ session: MinimedKit.PumpOpsSession) { }

    public func runSession(withName name: String, using device: RileyLinkDevice, _ block: @escaping (_ session: PumpOpsSession) -> Void) {
        let minimedPumpMessageSender = MockPumpMessageSender()
        let session = PumpOpsSession(settings: self.pumpSettings, pumpState: self.pumpState, messageSender: minimedPumpMessageSender, delegate: self)
        block(session)
    }

    init(pumpState: PumpState, pumpSettings: PumpSettings) {
        self.pumpState = pumpState
        self.pumpSettings = pumpSettings
    }
}
