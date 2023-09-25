//
//  PodCommsSessionTests.swift
//  OmniBLE
//
//  Created by Pete Schwamb on 3/25/19.
//  Copyright © 2019 Pete Schwamb. All rights reserved.
//  From OmniKitTests/PodCommsSessionTests.swift
//

import Foundation

import XCTest
@testable import OmniBLE

class MockMessageTransport: MessageTransport {
    var delegate: MessageTransportDelegate?

    var messageNumber: Int

    var responseMessageBlocks = [MessageBlock]()
    public var sentMessages = [Message]()

    var address: UInt32

    var sentMessageHandler: ((Message) -> Void)?

    init(address: UInt32, messageNumber: Int) {
        self.address = address
        self.messageNumber = messageNumber
    }

    func sendMessage(_ message: Message) throws -> Message {
        sentMessages.append(message)
        if responseMessageBlocks.isEmpty {
            throw PodCommsError.noResponse
        }
        return Message(address: address, messageBlocks: [responseMessageBlocks.removeFirst()], sequenceNum: messageNumber)
    }

    func addResponse(_ messageBlock: MessageBlock) {
        responseMessageBlocks.append(messageBlock)
    }

    func assertOnSessionQueue() {
        // Do nothing in tests
    }
}

class PodCommsSessionTests: XCTestCase, PodCommsSessionDelegate {

    var lastPodStateUpdate: PodState?

    let address: UInt32 = 521580830
    let fakeLtk = Data(hexadecimalString: "fedcba98765432100123456789abcdef")!
    var mockTransport: MockMessageTransport! = nil
    var podState: PodState! = nil

    override func setUp() {
        mockTransport = MockMessageTransport(address: address, messageNumber: 1)
        podState = PodState(address: address, ltk: fakeLtk, firmwareVersion: "2.7.0", bleFirmwareVersion: "2.7.0", lotNo: 43620, lotSeq: 560313, productId: dashProductId, bleIdentifier: "0000-0000", insulinType: .novolog)
    }

    func podCommsSession(_ podCommsSession: PodCommsSession, didChange state: PodState) {
        lastPodStateUpdate = state
    }

    func testBolusFinishedEarlyOnPodIsMarkedNonMutable() {
         let mockStart = Date()
         podState.unfinalizedBolus = UnfinalizedDose(bolusAmount: 4.45, startTime: mockStart, scheduledCertainty: .certain, insulinType: .novolog)
         let session = PodCommsSession(podState: podState, transport: mockTransport, delegate: self)

         // Simulate a status request a bit before the bolus is expected to finish
         let statusRequestTime = podState.unfinalizedBolus!.finishTime!.addingTimeInterval(-5)
         session.mockCurrentDate = statusRequestTime

         let statusResponse = StatusResponse(
             deliveryStatus: .scheduledBasal,
             podProgressStatus: .aboveFiftyUnits,
             timeActive: .minutes(10),
             reservoirLevel: Pod.reservoirLevelAboveThresholdMagicNumber,
             insulinDelivered: 25,
             bolusNotDelivered: 0,
             lastProgrammingMessageSeqNum: 5,
             alerts: AlertSet(slots: []))

         mockTransport.addResponse(statusResponse)

         let _ = try! session.getStatus()

         XCTAssertEqual(1, lastPodStateUpdate!.finalizedDoses.count)

         let finalizedBolus = lastPodStateUpdate!.finalizedDoses[0]

         XCTAssertTrue(finalizedBolus.isFinished(at: statusRequestTime))
         XCTAssertFalse(finalizedBolus.isMutable(at: statusRequestTime))
     }

}
