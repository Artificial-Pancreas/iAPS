//
//  PumpMessageSender.swift
//  RileyLink
//
//  Created by Jaim Zuber on 3/2/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation
import RileyLinkBLEKit

public protocol PumpMessageSender {
    /// - Throws: LocalizedError
    func resetRadioConfig() throws

    /// - Throws: LocalizedError
    func updateRegister(_ address: CC111XRegister, value: UInt8) throws

    /// - Throws: LocalizedError
    func setBaseFrequency(_ frequency: Measurement<UnitFrequency>) throws

    /// - Throws: LocalizedError
    func listen(onChannel channel: Int, timeout: TimeInterval) throws -> RFPacket?

    /// - Throws: LocalizedError
    func send(_ msg: PumpMessage) throws

    /// - Throws: LocalizedError
    func getRileyLinkStatistics() throws -> RileyLinkStatistics

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
    func getResponse<T: MessageBody>(to message: PumpMessage, responseType: MessageType, repeatCount: Int, timeout: TimeInterval, retryCount: Int) throws -> T

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
    func sendAndListen(_ message: PumpMessage, repeatCount: Int, timeout: TimeInterval, retryCount: Int) throws -> PumpMessage

    // Send a PumpMessage, and listens for a packet; used by callers who need to see RSSI
    /// - Throws:
    ///     - PumpOpsError.noResponse
    ///     - PumpOpsError.deviceError
    func sendAndListenForPacket(_ message: PumpMessage, repeatCount: Int, timeout: TimeInterval, retryCount: Int) throws -> RFPacket

    /// - Throws: PumpOpsError.deviceError
    func listenForPacket(onChannel channel: Int, timeout: TimeInterval) throws -> RFPacket?
}

