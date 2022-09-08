//
//  MinimedPumpManagerTests.swift
//  MinimedKitTests
//
//  Created by Pete Schwamb on 5/3/20.
//  Copyright © 2020 Pete Schwamb. All rights reserved.
//

import XCTest
import RileyLinkBLEKit
@testable import MinimedKit
import LoopKit

class MinimedPumpManagerTests: XCTestCase {

    var rlProvider: MockRileyLinkProvider!
    var mockPumpManagerDelegate: MockPumpManagerDelegate!
    var pumpManager: MinimedPumpManager!

    override func setUpWithError() throws {
        let device = MockRileyLinkDevice()
        rlProvider = MockRileyLinkProvider(devices: [device])
        let rlManagerState = RileyLinkConnectionState(autoConnectIDs: [])
        let state = MinimedPumpManagerState(
            isOnboarded: true,
            useMySentry: true,
            pumpColor: .blue,
            pumpID: "123456",
            pumpModel: .model523,
            pumpFirmwareVersion: "VER 2.4A1.1",
            pumpRegion: .northAmerica,
            rileyLinkConnectionState: rlManagerState,
            timeZone: .currentFixed,
            suspendState: .resumed(Date()),
            insulinType: .novolog,
            lastTuned: nil,
            lastValidFrequency: nil)
        let pumpOps = MockPumpOps(pumpState: state.pumpState, pumpSettings: state.pumpSettings)
        pumpManager = MinimedPumpManager(state: state, rileyLinkDeviceProvider: rlProvider, pumpOps: pumpOps)
        mockPumpManagerDelegate = MockPumpManagerDelegate()
        pumpManager.pumpManagerDelegate = mockPumpManagerDelegate
    }

    func testBolusWithInvalidResponse() {
        let exp = expectation(description: "enactBolus callback")
        pumpManager.enactBolus(units: 2.3, activationType: .manualNoRecommendation) { error in
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }
}
