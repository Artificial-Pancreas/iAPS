//
//  LTKExchanger.swift
//  OmniBLE
//
//  Created by Randall Knutson on 8/3/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//
import Foundation
import os.log

class LTKExchanger {
    static let GET_POD_STATUS_HEX_COMMAND: Data = Data(hex: "ffc32dbd08030e0100008a")
    // This is the binary representation of "GetPodStatus command"

    static private let SP1 = "SP1="
    static private let SP2 = ",SP2="
    static private let SPS1 = "SPS1="
    static private let SPS2 = "SPS2="
    static private let SP0GP0 = "SP0,GP0"
    static private let P0 = "P0="
    static private let UNKNOWN_P0_PAYLOAD = Data([0xa5])

    private let manager: PeripheralManager
    private let ids: Ids
    private let podAddress = Ids.notActivated()
    private let keyExchange = try! KeyExchange(X25519KeyGenerator(), OmniRandomByteGenerator())
    private var seq: UInt8 = 1
    
    private let log = OSLog(category: "LTKExchanger")

    init(manager: PeripheralManager, ids: Ids) {
        self.manager = manager
        self.ids = ids
    }

    func negotiateLTK() throws -> PairResult {
        log.debug("Sending sp1sp2")
        let sp1sp2 = PairMessage(
            sequenceNumber: seq,
            source: ids.myId,
            destination: podAddress,
            keys: [LTKExchanger.SP1, LTKExchanger.SP2],
            payloads: [ids.podId.address, sp2()]
        )
        try throwOnSendError(sp1sp2.message, LTKExchanger.SP1 + LTKExchanger.SP2)

        seq += 1
        log.debug("Sending sps1")
        let sps1 = PairMessage(
            sequenceNumber: seq,
            source: ids.myId,
            destination: podAddress,
            keys: [LTKExchanger.SPS1],
            payloads: [keyExchange.pdmPublic + keyExchange.pdmNonce]
        )
        try throwOnSendError(sps1.message, LTKExchanger.SPS1)

        log.debug("Reading sps1")
        let podSps1 = try manager.readMessagePacket()
        guard let _ = podSps1 else {
            throw PodProtocolError.pairingException("Could not read SPS1")
        }
        try processSps1FromPod(podSps1!)
        // now we have all the data to generate: confPod, confPdm, ltk and noncePrefix

        log.debug("Sending sps2")
        seq += 1
        let sps2 = PairMessage(
            sequenceNumber: seq,
            source: ids.myId,
            destination: podAddress,
            keys: [LTKExchanger.SPS2],
            payloads: [keyExchange.pdmConf]
        )
        try throwOnSendError(sps2.message, LTKExchanger.SPS2)

        let podSps2 = try manager.readMessagePacket()
        guard let _ = podSps2 else {
            throw PodProtocolError.pairingException("Could not read SPS2")
        }
        try validatePodSps2(podSps2!)
        // No exception throwing after this point. It is possible that the pod saved the LTK

        seq += 1
        // send SP0GP0
        let sp0gp0 = PairMessage(
            sequenceNumber: seq,
            source: ids.myId,
            destination: podAddress,
            keys: [LTKExchanger.SP0GP0],
            payloads: [Data()]
        )
        let result = manager.sendMessagePacket(sp0gp0.message)
        guard case .sentWithAcknowledgment = result else {
            throw PodProtocolError.pairingException("Error sending SP0GP0: \(result)")
        }

        let p0 = try manager.readMessagePacket()
        guard let _ = p0 else {
            throw PodProtocolError.pairingException("Could not read P0")
        }
        try validateP0(p0!)
        
        guard keyExchange.ltk.count == 16 else {
            throw PodProtocolError.invalidLTKKey("Invalid Key, got \(String(data: keyExchange.ltk, encoding: .utf8) ?? "")")
        }

        return PairResult(
            ltk: keyExchange.ltk,
            address: ids.podId.toUInt32(),
            msgSeq: seq
        )
    }

    private func throwOnSendError(_ msg: MessagePacket, _ msgType: String) throws {
        let result = manager.sendMessagePacket(msg)
        guard case .sentWithAcknowledgment = result else {
            throw PodProtocolError.pairingException("Send failure: \(result)")
        }
    }

    private func processSps1FromPod(_ msg: MessagePacket) throws {
        log.debug("Received SPS1 from pod: %@", msg.payload.hexadecimalString)

        let payload = try StringLengthPrefixEncoding.parseKeys([LTKExchanger.SPS1], msg.payload)[0]
        log.debug("SPS1 payload from pod: %@", payload.hexadecimalString)
        try keyExchange.updatePodPublicData(payload)
    }

    private func validatePodSps2(_ msg: MessagePacket) throws {
        log.debug("Received SPS2 from pod: %@", msg.payload.hexadecimalString)

        let payload = try StringLengthPrefixEncoding.parseKeys([LTKExchanger.SPS2], msg.payload)[0]
        log.debug("SPS2 payload from pod: %@", payload.hexadecimalString)

        if (payload.count != KeyExchange.CMAC_SIZE) {
            throw PodProtocolError.messageIOException("Invalid payload size")
        }
        try keyExchange.validatePodConf(payload)
    }

    private func sp2() -> Data {
        // This is GetPodStatus command, with page 0 parameter.
        // We could replace that in the future with the serialized GetPodStatus()
        return LTKExchanger.GET_POD_STATUS_HEX_COMMAND
    }

    private func validateP0(_ msg: MessagePacket) throws {
        log.debug("Received P0 from pod: %@", msg.payload.hexadecimalString)

        let payload = try StringLengthPrefixEncoding.parseKeys([LTKExchanger.P0], msg.payload)[0]
        log.debug("P0 payload from pod: %@", payload.hexadecimalString)
        if (payload != LTKExchanger.UNKNOWN_P0_PAYLOAD) {
            throw PodProtocolError.pairingException("Reveived invalid P0 payload: \(payload)")
        }
    }
}
