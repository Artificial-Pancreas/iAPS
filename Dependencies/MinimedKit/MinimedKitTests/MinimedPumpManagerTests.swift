//
//  MinimedPumpManagerTests.swift
//  MinimedKitTests
//
//  Created by Pete Schwamb on 5/3/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import RileyLinkBLEKit
@testable import MinimedKit
import LoopKit

class MinimedPumpManagerTests: XCTestCase {

    var rlProvider: MockRileyLinkProvider!
    var mockPumpManagerDelegate: MockPumpManagerDelegate!
    var pumpManager: MinimedPumpManager!

    var mockMessageSender: MockPumpMessageSender!

    // Date simulation
    private var dateFormatter = ISO8601DateFormatter()
    private var simulatedDate: Date = ISO8601DateFormatter().date(from: "2023-01-06T23:45:57Z")!
    private var dateSimulationOffset: TimeInterval = 0

    private func setSimulatedDate(from dateString: String) {
        simulatedDate = dateFormatter.date(from: dateString)!
        dateSimulationOffset = 0
    }

    private func timeTravel(_ time: TimeInterval) {
        dateSimulationOffset += time
    }

    private func dateGenerator() -> Date {
        return self.simulatedDate + dateSimulationOffset
    }


    override func setUpWithError() throws {
        let device = MockRileyLinkDevice()
        
        rlProvider = MockRileyLinkProvider(devices: [device])
        let rlManagerState = RileyLinkConnectionState(autoConnectIDs: [])
        mockMessageSender = MockPumpMessageSender()
        let pumpID = "636781"
        mockMessageSender.pumpID = pumpID
        let state = MinimedPumpManagerState(
            isOnboarded: true,
            useMySentry: true,
            pumpColor: .blue,
            pumpID: pumpID,
            pumpModel: .model522,
            pumpFirmwareVersion: "VER 2.4A1.1",
            pumpRegion: .northAmerica,
            rileyLinkConnectionState: rlManagerState,
            timeZone: .currentFixed,
            suspendState: .resumed(Date()),
            insulinType: .novolog,
            lastTuned: simulatedDate,
            lastValidFrequency: nil,
            basalSchedule: BasalSchedule(entries: [BasalScheduleEntry(index: 0, timeOffset: 0, rate: 1.0)]))

        var pumpState = state.pumpState
        pumpState.awakeUntil = .distantFuture
        let pumpOps = MockPumpOps(pumpState: pumpState, pumpSettings: state.pumpSettings, messageSender: mockMessageSender)

        pumpManager = MinimedPumpManager(state: state, rileyLinkDeviceProvider: rlProvider, pumpOps: pumpOps, dateGenerator: dateGenerator)
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

    func testBolusWithUncertainResponseIsReported() {
        mockMessageSender.responses = [
            .readPumpStatus: [mockMessageSender.makeMockResponse(.readPumpStatus, ReadPumpStatusMessageBody(bolusing: false, suspended: false))],
            .bolus: [mockMessageSender.ack], // Second ack missing will cause PumpOpsError.noReponse during second exchange
        ]

        let exp = expectation(description: "enactBolus callback")
        pumpManager.enactBolus(units: 2.3, activationType: .manualNoRecommendation) { error in
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(mockPumpManagerDelegate.reportedPumpEvents.count, 1)
        let report = mockPumpManagerDelegate.reportedPumpEvents.first!
        XCTAssertEqual(report.events.count, 1)
        let event = report.events.first!
        XCTAssertEqual(event.type, .bolus)
        XCTAssertEqual(event.dose!.deliveredUnits, 2.3)
    }

    func testPendingBolusRemovedIfMissingFromHistory() {

        mockMessageSender.responses = [
            .readPumpStatus: [mockMessageSender.makeMockResponse(.readPumpStatus, ReadPumpStatusMessageBody(bolusing: false, suspended: false))],
            .bolus: [mockMessageSender.ack, mockMessageSender.ack],
        ]

        var exp = expectation(description: "enactBolus callback")
        pumpManager.enactBolus(units: 3.2, activationType: .manualNoRecommendation) { error in
            XCTAssertNil(error)
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(mockPumpManagerDelegate.reportedPumpEvents.count, 1)

        timeTravel(.minutes(2))
        timeTravel(.seconds(8))

        // Setup responses for successful history fetch

        mockPumpManagerDelegate.historyFetchStartDate = simulatedDate

        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar(identifier: Calendar.Identifier.gregorian)
        dateComponents.year   = 2023
        dateComponents.month  = 1
        dateComponents.day    = 6
        dateComponents.hour   = 17
        dateComponents.minute = 48
        dateComponents.second = 05
        

        let pumpStatusResponse = mockMessageSender.makeMockResponse(.readPumpStatus, ReadPumpStatusMessageBody(bolusing: false, suspended: false))

        let historyPageResponsesHex = [
            "0116012f6f094617331a306f094617001601306f09461701010100336f29461733002b740946170016012b740946173300304c0a4617001601304c0a461733002b",
            "02600a46170016012b600a4617330a2b650a46170016012b650a4617331c2d6a0a46170016012d6a0a461701010100316a2a4617010101002c6f2a461701010100",
            "0334742a4617010404001f772a461733002d790a46170016002d790a46170101010031792a4617010101002c422b4617331c30470b461700160130470b46170101",
            "04010033472b461733142b4c0b46170016012b4c0b461733002b510b46170016012b510b4617330e29560b461700160129560b4617331c2c5b0b46170016012c5b",
            "050b461733102b650b46170016012b650b4617330e2b6a0b46170016012b6a0b461733122f6f0b46170016012f6f0b461733102b740b46170016012b740b461733",
            "060c2b790b46170016012b790b4617330e2b420c46170016012b420c4617330030470c461700160130470c461733182d4c0c46170016012d4c0c4617010707000d",
            "07502c4617330022510c461700160022510c4617331a295b0c4617001601295b0c4617010101002e652c4617010101002c6a2c461733162d6f0c46170016012d6f",
            "080c461733082c740c46170016012c740c461733002b790c46170016012b790c4617330a30420d461700160130420d4617331a2a470d46170016012a470d461701",
            "092525000a482d4617331a2d5b0d46170016012d5b0d461701010100315b2d461733142d650d46170016012d650d4617331a2b6a0d46170016012b6a0d46170101",
            "0a01002c6f2d461733182b740d46170016012b740d461733002e790d46170016012e790d461733002d510e46170016012d510e461733042d600e46170016012d60",
            "0b0e461733002b650e46170016012b650e461733042d6f0e46170016012d6f0e4617330e2d740e46170016012d740e461733022d790e46170016012d790e461733",
            "0c002b420f46170016012b420f461733022e470f46170016012e470f461733040e480f46170016010e480f461733082c4c0f46170016012c4c0f4617330c2b510f",
            "0d46170016012b510f46173300295b0f4617001601295b0f461733062d600f46170016012d600f4617330a1f650f46170016011f650f461733002c6a0f46170016",
            "0e002c6a0f4617010101002c6f2f4617010202002c742f4617010101002c792f461733082e421046170016012e4210461733022b471046170016012b4710461733",
            "0f00204c104617001601204c10461733002a601046170016012a6010461733002074104617001601207410461733002b4c1146170016012b4c11461733002b6011",
            "9046170016012b6011461700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000656b"
        ]

        let mockHistoryPageResponses = historyPageResponsesHex.map { hex in
            mockMessageSender.makeMockResponse(.getHistoryPage, CarelinkLongMessageBody(rxData: Data(hexadecimalString: hex)!)!)
        }

        mockMessageSender.responses = [
            .getBattery: [mockMessageSender.makeMockResponse(.getBattery, GetBatteryCarelinkMessageBody(status: .normal, volts: 1.44))],
            .readPumpStatus: [pumpStatusResponse, pumpStatusResponse],
            .readTime: [mockMessageSender.makeMockResponse(.readTime, ReadTimeCarelinkMessageBody(dateComponents: dateComponents))],
            .readRemainingInsulin: [mockMessageSender.makeMockResponse(.readRemainingInsulin, ReadRemainingInsulinMessageBody(reservoirVolume: 115.7, insulinBitPackingScale: PumpModel.model522.insulinBitPackingScale))],
            .getHistoryPage: [mockMessageSender.ack, mockHistoryPageResponses.first!],
            .pumpAck: Array(mockHistoryPageResponses.dropFirst())
        ]

        exp = expectation(description: "ensureCurrentPumpData callback")
        pumpManager.ensureCurrentPumpData { date in
            exp.fulfill()
        }

        waitForExpectations(timeout: 3)
    }
}
