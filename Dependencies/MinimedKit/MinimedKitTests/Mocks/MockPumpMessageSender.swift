//
//  MockPumpMessageSender.swift
//  MinimedKitTests
//
//  Created by Pete Schwamb on 1/7/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import MinimedKit
import RileyLinkBLEKit


class MockPumpMessageSender: PumpMessageSender {

    var pumpID = "636781"

    func listenForPacket(onChannel channel: Int, timeout: TimeInterval) throws -> RileyLinkBLEKit.RFPacket? {
        // do nothing
        return nil
    }

    func getRileyLinkStatistics() throws -> RileyLinkStatistics {
        throw PumpOpsError.noResponse(during: "Tests")
    }

    func makeMockResponse(_ messageType: MessageType, _ messageBody: MessageBody) -> PumpMessage {
        return PumpMessage(packetType: .carelink, address: pumpID, messageType: messageType, messageBody: messageBody)
    }

    var ack: PumpMessage {
        return PumpMessage(pumpID: pumpID, type: .pumpAck)
    }

    func sendAndListen(_ data: Data, repeatCount: Int, timeout: TimeInterval, retryCount: Int) throws -> RFPacket {
        guard let decoded = MinimedPacket(encodedData: data),
              let messageType = MessageType(rawValue: decoded.data[4])
        else {
            throw PumpOpsError.noResponse(during: "Tests")
        }

        let response: PumpMessage

        if let responseArray = responses[messageType] {
            let numberOfResponsesReceived: Int

            if let someValue = responsesHaveOccured[messageType] {
                numberOfResponsesReceived = someValue
            } else {
                numberOfResponsesReceived = 0
            }

            let nextNumberOfResponsesReceived = numberOfResponsesReceived + 1
            responsesHaveOccured[messageType] = nextNumberOfResponsesReceived

            if responseArray.count <= numberOfResponsesReceived {
                throw PumpOpsError.noResponse(during: data)
            }

            response = responseArray[numberOfResponsesReceived]
        } else {
            // .pumpAck from 636781 ?
            let packet = MinimedPacket(encodedData: Data(hexadecimalString: "a969a39966b1566555b235")!)!
            response = PumpMessage(rxData: packet.data)!
        }

        var encoded = MinimedPacket(outgoingData: response.txData).encodedData()
        encoded.insert(contentsOf: [0, 0], at: 0)

        guard let rfPacket = RFPacket(rfspyResponse: encoded) else {
            throw PumpOpsError.noResponse(during: data)
        }

        return rfPacket
    }

    func getResponse<T: MessageBody>(to message: PumpMessage, responseType: MessageType, repeatCount: Int, timeout: TimeInterval, retryCount: Int) throws -> T {

        let response = try sendAndListen(message, repeatCount: repeatCount, timeout: timeout, retryCount: retryCount)

        guard response.messageType == responseType, let body = response.messageBody as? T else {
            if let body = response.messageBody as? PumpErrorMessageBody {
                switch body.errorCode {
                case .known(let code):
                    throw PumpOpsError.pumpError(code)
                case .unknown(let code):
                    throw PumpOpsError.unknownPumpErrorCode(code)
                }
            } else {
                throw PumpOpsError.unexpectedResponse(response, from: message)
            }
        }
        return body
    }

    /// Sends a message to the pump, listening for a any known PumpMessage in reply
    ///
    /// - Parameters:
    ///   - message: The message to send
    ///   - repeatCount: The number of times to repeat the message before listening begins
    ///   - timeout: The length of time to listen for a pump response
    ///   - retryCount: The number of times to repeat the send & listen sequence
    /// - Returns: The message reply
    /// - Throws: An error describing a failure in the sending or receiving of a message:
    ///     - PumpOpsError.couldNotDecode
    ///     - PumpOpsError.crosstalk
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.unknownResponse
    func sendAndListen(_ message: PumpMessage, repeatCount: Int, timeout: TimeInterval, retryCount: Int) throws -> PumpMessage {
        let rfPacket = try sendAndListenForPacket(message, repeatCount: repeatCount, timeout: timeout, retryCount: retryCount)

        guard let packet = MinimedPacket(encodedData: rfPacket.data) else {
            throw PumpOpsError.couldNotDecode(rx: rfPacket.data, during: message)
        }

        guard let response = PumpMessage(rxData: packet.data) else {
            // Unknown packet type or message type
            throw PumpOpsError.unknownResponse(rx: packet.data, during: message)
        }

        guard response.address == message.address else {
            throw PumpOpsError.crosstalk(response, during: message)
        }

        return response
    }

    // Send a PumpMessage, and listens for a packet; used by callers who need to see RSSI
    /// - Throws:
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.deviceError
    func sendAndListenForPacket(_ message: PumpMessage, repeatCount: Int, timeout: TimeInterval, retryCount: Int) throws -> RFPacket {
        let packet: RFPacket?

        do {
            packet = try sendAndListen(MinimedPacket(outgoingData: message.txData).encodedData(), repeatCount: repeatCount, timeout: timeout, retryCount: retryCount)
        } catch let error as LocalizedError {
            throw error
        }

        guard let rfPacket = packet else {
            throw PumpOpsError.noResponse(during: message)
        }

        return rfPacket
    }

    func listen(onChannel channel: Int, timeout: TimeInterval) throws -> RFPacket? {
        throw PumpOpsError.noResponse(during: "Tests")
    }

    func send(_ msg: MinimedKit.PumpMessage) throws {
        // Do nothing
    }

    func updateRegister(_ address: CC111XRegister, value: UInt8) throws {
        throw PumpOpsError.noResponse(during: "Tests")
    }

    func resetRadioConfig() throws {
        throw PumpOpsError.noResponse(during: "Tests")
    }

    func setBaseFrequency(_ frequency: Measurement<UnitFrequency>) throws {
        throw PumpOpsError.noResponse(during: "Tests")
    }

    var responses = [MessageType: [PumpMessage]]()

    // internal tracking of how many times a response type has been received
    private var responsesHaveOccured = [MessageType: Int]()
}

extension MockPumpMessageSender: PumpOpsSessionDelegate {
    func pumpOpsSession(_ session: PumpOpsSession, didChange state: PumpState) {

    }

    func pumpOpsSessionDidChangeRadioConfig(_ session: PumpOpsSession) {

    }

}
