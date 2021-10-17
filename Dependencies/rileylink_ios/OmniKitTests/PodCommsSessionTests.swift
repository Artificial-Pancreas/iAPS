//
//  PodCommsSessionTests.swift
//  OmniKitTests
//
//  Created by Pete Schwamb on 3/25/19.
//  Copyright © 2019 Pete Schwamb. All rights reserved.
//

import Foundation

import XCTest
@testable import OmniKit

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

    func podCommsSession(_ podCommsSession: PodCommsSession, didChange state: PodState) {
        lastPodStateUpdate = state
    }


    func testNonceResync() {

        // From https://raw.githubusercontent.com/wiki/openaps/openomni/Full-life-of-a-pod-(omni-flo).md

        // 2018-05-25T13:03:51.765792 pod Message(ffffffff seq:01 [OmniKitPacketParser.VersionResponse(blockType: OmniKitPacketParser.MessageBlockType.versionResponse, lot: 43620, tid: 560313, address: Optional(521580830), pmVersion: 2.7.0, piVersion: 2.7.0, data: 23 bytes)])

        let podState = PodState(address: 521580830, piVersion: "2.7.0", pmVersion: "2.7.0", lot: 43620, tid: 560313, insulinType: .novolog)

        let messageTransport = MockMessageTransport(address: podState.address, messageNumber: 5)

        do {
            // 2018-05-26T09:11:08.580347 pod Message(1f16b11e seq:06 [OmniKitPacketParser.ErrorResponse(blockType: OmniKitPacketParser.MessageBlockType.errorResponse, errorReponseType: OmniKitPacketParser.ErrorResponse.ErrorReponseType.badNonce, nonceSearchKey: 43492, data: 5 bytes)])
            messageTransport.addResponse(try ErrorResponse(encodedData: Data(hexadecimalString: "060314a9e403f5")!))
            messageTransport.addResponse(try StatusResponse(encodedData: Data(hexadecimalString: "1d5800d1a8140012e3ff8018")!))
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
            return
        }

        let session = PodCommsSession(podState: podState, transport: messageTransport, delegate: self)


        // 2018-05-26T09:11:07.984983 pdm Message(1f16b11e seq:05 [SetInsulinScheduleCommand(nonce:2232447658, bolus(units: 1.0, timeBetweenPulses: 2.0)), OmniKitPacketParser.BolusExtraCommand(blockType: OmniKitPacketParser.MessageBlockType.bolusExtra, completionBeep: false, programReminderInterval: 0.0, units: 1.0, timeBetweenPulses: 2.0, squareWaveUnits: 0.0, squareWaveDuration: 0.0)])
        let bolusDelivery = SetInsulinScheduleCommand.DeliverySchedule.bolus(units: 1.0, timeBetweenPulses: 2.0)
        let sentCommand = SetInsulinScheduleCommand(nonce: 2232447658, deliverySchedule: bolusDelivery)

        do {
            let status: StatusResponse = try session.send([sentCommand])

            XCTAssertEqual(2, messageTransport.sentMessages.count)

            let bolusTry1 = messageTransport.sentMessages[0].messageBlocks[0] as! SetInsulinScheduleCommand
            XCTAssertEqual(2232447658, bolusTry1.nonce)

            let bolusTry2 = messageTransport.sentMessages[1].messageBlocks[0] as! SetInsulinScheduleCommand
            XCTAssertEqual(1521036535, bolusTry2.nonce)

            XCTAssert(status.deliveryStatus.bolusing)
        } catch (let error) {
            XCTFail("message sending error: \(error)")
        }

        // Try sending another bolus command: nonce should be 676940027
        XCTAssertEqual(545302454, lastPodStateUpdate!.currentNonce)

        let _ = session.bolus(units: 2, automatic: false)
        let bolusTry3 = messageTransport.sentMessages[2].messageBlocks[0] as! SetInsulinScheduleCommand
        XCTAssertEqual(545302454, bolusTry3.nonce)

    }
}
