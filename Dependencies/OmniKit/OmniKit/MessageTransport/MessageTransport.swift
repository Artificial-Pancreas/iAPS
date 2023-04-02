//
//  MessageTransport.swift
//  OmniKit
//
//  Created by Pete Schwamb on 8/5/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation
import os.log

import RileyLinkBLEKit

protocol MessageLogger: AnyObject {
    // Comms logging
    func didSend(_ message: Data)
    func didReceive(_ message: Data)
    func didError(_ message: String)
}

public struct MessageTransportState: Equatable, RawRepresentable {
    public typealias RawValue = [String: Any]

    public var packetNumber: Int
    public var messageNumber: Int
    
    init(packetNumber: Int, messageNumber: Int) {
        self.packetNumber = packetNumber
        self.messageNumber = messageNumber
    }
    
    // RawRepresentable
    public init?(rawValue: RawValue) {
        guard
            let packetNumber = rawValue["packetNumber"] as? Int,
            let messageNumber = rawValue["messageNumber"] as? Int
            else {
                return nil
        }
        self.packetNumber = packetNumber
        self.messageNumber = messageNumber
    }
    
    public var rawValue: RawValue {
        return [
            "packetNumber": packetNumber,
            "messageNumber": messageNumber
        ]
    }

}

protocol MessageTransportDelegate: AnyObject {
    func messageTransport(_ messageTransport: MessageTransport, didUpdate state: MessageTransportState)
}

protocol MessageTransport {
    var delegate: MessageTransportDelegate? { get set }

    var messageNumber: Int { get }

    func sendMessage(_ message: Message) throws -> Message

    /// Asserts that the caller is currently on the session's queue
    func assertOnSessionQueue()
}

class PodMessageTransport: MessageTransport {
    
    private let session: CommandSession
    
    private let log = OSLog(category: "PodMessageTransport")
    
    private var state: MessageTransportState {
        didSet {
            self.delegate?.messageTransport(self, didUpdate: state)
        }
    }
    
    private(set) var packetNumber: Int {
        get {
            return state.packetNumber
        }
        set {
            state.packetNumber = newValue
        }
    }
    
    private(set) var messageNumber: Int {
        get {
            return state.messageNumber
        }
        set {
            state.messageNumber = newValue
        }
    }
    
    private let address: UInt32
    private var ackAddress: UInt32 // During pairing, PDM acks with address it is assigning to channel
    
    weak var messageLogger: MessageLogger?
    weak var delegate: MessageTransportDelegate?

    init(session: CommandSession, address: UInt32 = 0xffffffff, ackAddress: UInt32? = nil, state: MessageTransportState) {
        self.session = session
        self.address = address
        self.ackAddress = ackAddress ?? address
        self.state = state
    }
    
    private func incrementPacketNumber(_ count: Int = 1) {
        packetNumber = (packetNumber + count) & 0b11111
    }
    
    private func incrementMessageNumber(_ count: Int = 1) {
        messageNumber = (messageNumber + count) & 0b1111
    }
    
    func makeAckPacket() -> Packet {
        return Packet(address: address, packetType: .ack, sequenceNum: packetNumber, data: Data(bigEndian: ackAddress))
    }
    
    func ackUntilQuiet() {
        
        let packetData = makeAckPacket().encoded()
        
        var lastHeardAt = Date()
        let quietWindow = TimeInterval(milliseconds: 300)
        while lastHeardAt.timeIntervalSinceNow > -quietWindow {
            do {
                let rfPacket = try session.sendAndListen(packetData, repeatCount: 1, timeout: quietWindow, retryCount: 0, preambleExtension: TimeInterval(milliseconds: 40))
                let packet = try Packet(rfPacket: rfPacket)
                if packet.address == address {
                    lastHeardAt = Date() // Pod still sending
                }
            } catch RileyLinkDeviceError.responseTimeout {
                // Haven't heard anything in 300ms.  POD heard our ack.
                break
            } catch {
                continue
            }
        }
        incrementPacketNumber()
    }
    

    /// Encodes and sends a packet to the pod, and receives and decodes its response
    ///
    /// - Parameters:
    ///   - packet: The packet to send
    ///   - repeatCount: Number of times to repeat packet before listening for a response. 0 = send once and do not repeat.
    ///   - packetResponseTimeout: The amount of time to wait before retrying
    ///   - exchangeTimeout: The amount of time to continue retrying before giving up
    ///   - preambleExtension: Duration of preamble. Default is 127ms
    /// - Returns: The received response packet
    /// - Throws:
    ///     - PodCommsError.noResponse
    ///     - RileyLinkDeviceError
    func exchangePackets(packet: Packet, repeatCount: Int = 0, packetResponseTimeout: TimeInterval = .milliseconds(333), exchangeTimeout:TimeInterval = .seconds(9), preambleExtension: TimeInterval = .milliseconds(127)) throws -> Packet {
        let packetData = packet.encoded()
        let radioRetryCount = 9
        
        let start = Date()
        
        incrementPacketNumber()
        
        while (-start.timeIntervalSinceNow < exchangeTimeout)  {
            do {
                let rfPacket = try session.sendAndListen(packetData, repeatCount: repeatCount, timeout: packetResponseTimeout, retryCount: radioRetryCount, preambleExtension: preambleExtension)
                
                let candidatePacket: Packet
                
                do {
                    candidatePacket = try Packet(rfPacket: rfPacket)
                    log.default("Received packet (%d): %@", rfPacket.rssi, rfPacket.data.hexadecimalString)
                } catch PacketError.insufficientData {
                    log.default("Insufficient packet data: %@", rfPacket.data.hexadecimalString)
                    continue
                } catch let error {
                    log.default("Packet error: %@", String(describing: error))
                    continue
                }

                guard candidatePacket.address == packet.address || candidatePacket.address == 0xFFFFFFFF else {
                    log.default("Packet address 0x%x does not match 0x%x", candidatePacket.address, packet.address)
                    continue
                }
                
                guard candidatePacket.sequenceNum == ((packet.sequenceNum + 1) & 0b11111) else {
                    log.default("Packet sequence %@ does not match %@", String(describing: candidatePacket.sequenceNum), String(describing: ((packet.sequenceNum + 1) & 0b11111)))
                    continue
                }
                
                // Once we have verification that the POD heard us, we can increment our counters
                incrementPacketNumber()
                
                return candidatePacket
            } catch RileyLinkDeviceError.responseTimeout {
                continue
            }
        }
        
        throw PodCommsError.noResponse
    }

    /// Packetizes a message, and performs a set of packet exchanges to send a message and receive the response
    ///
    /// - Parameters:
    ///   - message: The message to send
    /// - Returns: The received message response
    /// - Throws:
    ///     - PodCommsError.noResponse
    ///     - PodCommsError.podAckedInsteadOfReturningResponse
    ///     - PodCommsError.unexpectedPacketType
    ///     - PodCommsError.emptyResponse
    ///     - PodCommsError.unacknowledgedMessage
    ///     - PodCommsError.commsError
    func sendMessage(_ message: Message) throws -> Message {
        
        messageNumber = message.sequenceNum
        incrementMessageNumber()
        var sentFullMessage = false

        do {
            let responsePacket = try { () throws -> Packet in
                var firstPacket = true
                log.debug("Send: %@", String(describing: message))
                var dataRemaining = message.encoded()
                log.default("Send(Hex): %@", dataRemaining.hexadecimalString)
                messageLogger?.didSend(dataRemaining)
                while true {
                    let packetType: PacketType = firstPacket ? .pdm : .con
                    let sendPacket = Packet(address: address, packetType: packetType, sequenceNum: self.packetNumber, data: dataRemaining)
                    dataRemaining = dataRemaining.subdata(in: sendPacket.data.count..<dataRemaining.count)
                    firstPacket = false
                    if dataRemaining.count == 0 {
                        sentFullMessage = true
                    }
                    let response = try self.exchangePackets(packet: sendPacket)
                    if dataRemaining.count == 0 {
                        return response
                    }
                }
            }()
            
            guard responsePacket.packetType != .ack else {
                messageLogger?.didReceive(responsePacket.encoded())
                log.default("Pod responded with ack instead of response: %@", String(describing: responsePacket))
                throw PodCommsError.podAckedInsteadOfReturningResponse
            }
            
            // Assemble fragmented message from multiple packets
            let response = try { () throws -> Message in
                var responseData = responsePacket.data
                while true {
                    do {
                        let msg = try Message(encodedData: responseData)
                        log.default("Recv(Hex): %@", responseData.hexadecimalString)
                        guard msg.address == address else {
                            throw MessageError.invalidAddress(address: msg.address)
                        }
                        guard msg.sequenceNum == messageNumber else {
                            throw MessageError.invalidSequence
                        }
                        messageLogger?.didReceive(responseData)
                        return msg
                    } catch MessageError.notEnoughData {
                        log.debug("Sending ACK for CON")
                        let conPacket = try self.exchangePackets(packet: makeAckPacket(), repeatCount: 3, preambleExtension:TimeInterval(milliseconds: 40))
                        
                        guard conPacket.packetType == .con else {
                            log.default("Expected CON packet, received; %@", String(describing: conPacket))
                            throw PodCommsError.unexpectedPacketType(packetType: conPacket.packetType)
                        }
                        responseData += conPacket.data
                    } catch MessageError.invalidCrc {
                        // throw the error without any logging for a garbage message
                        throw MessageError.invalidCrc
                    } catch let error {
                        // log any other non-garbage messages that generate errors
                        log.error("Error (%{public}@) Recv(Hex): %@", String(describing: error), responseData.hexadecimalString)
                        messageLogger?.didReceive(responseData)
                        throw error
                    }
                }
            }()

            ackUntilQuiet()
            
            guard response.messageBlocks.count > 0 else {
                log.default("Empty response")
                throw PodCommsError.emptyResponse
            }
            
            incrementMessageNumber()
            
            return response
        } catch let error {
            if sentFullMessage {
                messageLogger?.didError("Unacknowledged message. seq:\(message.sequenceNum), error = \(error)")
                throw PodCommsError.unacknowledgedMessage(sequenceNumber: message.sequenceNum, error: error)
            } else if let podCommsError = error as? PodCommsError {
                throw podCommsError
            } else {
                throw PodCommsError.commsError(error: error)
            }
        }
    }

    func assertOnSessionQueue() {
        session.assertOnSessionQueue()
    }
}
