//
//  MinimedPumpMessageSender.swift
//  MinimedKit
//
//  Created by Pete Schwamb on 9/3/22.
//  Copyright © 2022 Pete Schwamb. All rights reserved.
//

import Foundation
import RileyLinkBLEKit
import os.log


public protocol CommsLogger: AnyObject {
    // Comms logging
    func willSend(_ message: String)
    func didReceive(_ message: String)
    func didError(_ message: String)
}

private let log = OSLog(category: "MinimedPumpMessageSender")

struct MinimedPumpMessageSender: PumpMessageSender {

    static let standardPumpResponseWindow: TimeInterval = .milliseconds(200)

    var commandSession: CommandSession
    weak var commsLogger: CommsLogger?

    func resetRadioConfig() throws {
        try commandSession.resetRadioConfig()
    }

    func updateRegister(_ address: RileyLinkBLEKit.CC111XRegister, value: UInt8) throws {
        try commandSession.updateRegister(address, value: value)
    }

    func setBaseFrequency(_ frequency: Measurement<UnitFrequency>) throws {
        try commandSession.setBaseFrequency(frequency)
    }

    func listen(onChannel channel: Int, timeout: TimeInterval) throws -> RileyLinkBLEKit.RFPacket? {
        return try commandSession.listen(onChannel: channel, timeout: timeout)
    }

    func getRileyLinkStatistics() throws -> RileyLinkBLEKit.RileyLinkStatistics {
        return try commandSession.getRileyLinkStatistics()
    }

    /// - Throws: PumpOpsError.deviceError
    func send(_ msg: PumpMessage) throws {
        do {
            try commandSession.send(MinimedPacket(outgoingData: msg.txData).encodedData(), onChannel: 0, timeout: 0)
        } catch let error as LocalizedError {
            throw PumpOpsError.deviceError(error)
        }
    }

    /// Sends a message to the pump, expecting a PumpMessage with specific response body type
    ///
    /// - Parameters:
    ///   - message: The message to send
    ///   - responseType: The expected response message type
    ///   - repeatCount: The number of times to repeat the message before listening begins
    ///   - timeout: The length of time to listen for a pump response
    ///   - retryCount: The number of times to repeat the send & listen sequence
    /// - Returns: The expected response message body
    /// - Throws:
    ///     - PumpOpsError.couldNotDecode
    ///     - PumpOpsError.crosstalk
    ///     - PumpOpsError.deviceError
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.pumpError
    ///     - PumpOpsError.unexpectedResponse
    ///     - PumpOpsError.unknownResponse
    func getResponse<T: MessageBody>(to message: PumpMessage, responseType: MessageType, repeatCount: Int, timeout: TimeInterval, retryCount: Int) throws -> T {

        commsLogger?.willSend(String(describing: message))

        do {
            let response = try sendAndListen(message, repeatCount: repeatCount, timeout: timeout, retryCount: retryCount)

            guard response.messageType == responseType, let body = response.messageBody as? T else {
                if let body = response.messageBody as? PumpErrorMessageBody {
                    commsLogger?.didReceive(String(describing: response))
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
            commsLogger?.didReceive(String(describing: response))
            usleep(200000) // 0.2s
            return body
        } catch {
            commsLogger?.didError(error.localizedDescription)
            throw error
        }
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
            packet = try commandSession.sendAndListen(MinimedPacket(outgoingData: message.txData).encodedData(), repeatCount: repeatCount, timeout: timeout, retryCount: retryCount)
        } catch let error as LocalizedError {
            throw PumpOpsError.deviceError(error)
        }

        guard let rfPacket = packet else {
            throw PumpOpsError.noResponse(during: message)
        }

        return rfPacket
    }

    /// - Throws: PumpOpsError.deviceError
    func listenForPacket(onChannel channel: Int, timeout: TimeInterval) throws -> RFPacket? {
        do {
            return try listen(onChannel: channel, timeout: timeout)
        } catch let error as LocalizedError {
            throw PumpOpsError.deviceError(error)
        }
    }
}
