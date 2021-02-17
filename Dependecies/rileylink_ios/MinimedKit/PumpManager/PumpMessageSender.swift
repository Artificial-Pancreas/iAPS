//
//  PumpMessageSender.swift
//  RileyLink
//
//  Created by Jaim Zuber on 3/2/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import Foundation
import RileyLinkBLEKit
import os.log

private let standardPumpResponseWindow: TimeInterval = .milliseconds(200)

private let log = OSLog(category: "PumpMessageSender")


protocol PumpMessageSender {
    /// - Throws: LocalizedError
    func resetRadioConfig() throws

    /// - Throws: LocalizedError
    func updateRegister(_ address: CC111XRegister, value: UInt8) throws

    /// - Throws: LocalizedError
    func setBaseFrequency(_ frequency: Measurement<UnitFrequency>) throws

    /// Sends data to the pump, listening for a reply
    ///
    /// - Parameters:
    ///   - data: The data to send
    ///   - repeatCount: The number of times to repeat the message before listening begins
    ///   - timeout: The length of time to listen for a response before timing out
    ///   - retryCount: The number of times to repeat the send & listen sequence
    /// - Returns: The packet reply
    /// - Throws: LocalizedError
    func sendAndListen(_ data: Data, repeatCount: Int, timeout: TimeInterval, retryCount: Int) throws -> RFPacket

    /// - Throws: LocalizedError
    func listen(onChannel channel: Int, timeout: TimeInterval) throws -> RFPacket?

    /// - Throws: LocalizedError
    func send(_ data: Data, onChannel channel: Int, timeout: TimeInterval) throws
    
    /// - Throws: LocalizedError
    func enableCCLEDs() throws
    
    /// - Throws: LocalizedError
    func getRileyLinkStatistics() throws -> RileyLinkStatistics
}

extension PumpMessageSender {
    /// - Throws: PumpOpsError.deviceError
    func send(_ msg: PumpMessage) throws {
        do {
            try send(MinimedPacket(outgoingData: msg.txData).encodedData(), onChannel: 0, timeout: 0)
        } catch let error as LocalizedError {
            throw PumpOpsError.deviceError(error)
        }
    }

    /// Sends a message to the pump, expecting a specific response body
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
    func getResponse<T: MessageBody>(to message: PumpMessage, responseType: MessageType = .pumpAck, repeatCount: Int = 0, timeout: TimeInterval = standardPumpResponseWindow, retryCount: Int = 3) throws -> T {
        
        log.debug("getResponse(%{public}@, %d, %f, %d)", String(describing: message), repeatCount, timeout, retryCount)
        
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

    /// Sends a message to the pump, listening for a message in reply
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
    func sendAndListen(_ message: PumpMessage, repeatCount: Int = 0, timeout: TimeInterval = standardPumpResponseWindow, retryCount: Int = 3) throws -> PumpMessage {
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

    /// - Throws:
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.deviceError
    func sendAndListenForPacket(_ message: PumpMessage, repeatCount: Int = 0, timeout: TimeInterval = standardPumpResponseWindow, retryCount: Int = 3) throws -> RFPacket {
        let packet: RFPacket?

        do {
            packet = try sendAndListen(MinimedPacket(outgoingData: message.txData).encodedData(), repeatCount: repeatCount, timeout: timeout, retryCount: retryCount)
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
