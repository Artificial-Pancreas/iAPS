//
//  SessionEstablisher.swift
//  OmniBLE
//
//  Created by Randall Knutson on 11/8/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import OSLog

enum SessionResult {
    case SessionKeys(SessionKeys)
    case SessionNegotiationResynchronization(SessionNegotiationResynchronization)
}

enum SessionEstablishmentException: Error {
    case InvalidParameter(String)
    case CommunicationError(String)
}

class SessionEstablisher {
    private static let IV_SIZE = 4

    private let manager: PeripheralManager
    private let ltk: Data
    private let eapSqn: Data
    private let myId: UInt32
    private let podId: UInt32
    private var msgSeq: Int
    
    private var controllerIV: Data
    private var nodeIV: Data = Data()
    private var identifier: UInt8 = 0
    private let milenage: Milenage
    private let log = OSLog(category: "SessionEstablisher")
    
    init(manager: PeripheralManager, ltk: Data, eapSqn: Int, myId: UInt32, podId: UInt32, msgSeq: Int) throws {
//        guard eapSqn.count == 6 else { throw SessionEstablishmentException.InvalidParameter("EAP-SQN has to be 6 bytes long") }
        guard ltk.count == 16 else { throw SessionEstablishmentException.InvalidParameter("LTK has to be 16 bytes long") }

        let random = OmniRandomByteGenerator()
        controllerIV = random.nextBytes(length: SessionEstablisher.IV_SIZE)

        self.manager = manager
        self.ltk = ltk
        self.eapSqn = Data(bigEndian: eapSqn).subdata(in: 2..<8)
        self.myId = myId
        self.podId = podId
        self.msgSeq = msgSeq
        self.milenage = try Milenage(k: ltk, sqn: self.eapSqn)
    }
    
    func negotiateSessionKeys() throws -> SessionResult {
        msgSeq += 1
        let challenge = try eapAkaChallenge()
        let sendResult = manager.sendMessagePacket(challenge)
        guard case .sentWithAcknowledgment = sendResult else {
            throw SessionEstablishmentException.CommunicationError("Could not send the EAP AKA challenge: $sendResult")
        }
        guard let challengeResponse = try manager.readMessagePacket() else {
            throw SessionEstablishmentException.CommunicationError("Could not establish session")
        }

        let newSqn = try processChallengeResponse(challengeResponse: challengeResponse)
        if (newSqn != nil) {
            return .SessionNegotiationResynchronization(SessionNegotiationResynchronization(
                synchronizedEapSqn: newSqn!,
                msgSequenceNumber: UInt8(msgSeq)
            ))
        }

        msgSeq += 1
        let success = eapSuccess()
        let _ = manager.sendMessagePacket(success)

        return .SessionKeys(SessionKeys(
            ck: milenage.ck,
            nonce:  Nonce(prefix: controllerIV + nodeIV),
            msgSequenceNumber: msgSeq
        ))
    }

    private func eapAkaChallenge() throws -> MessagePacket {
        let attributes = [
            try EapAkaAttributeAutn(payload: milenage.autn),
            try EapAkaAttributeRand(payload: milenage.rand),
            try EapAkaAttributeCustomIV(payload: controllerIV)
        ]

        let eapMsg = EapMessage(
            code: EapCode.REQUEST,
            identifier: identifier,
            attributes: attributes
        )
        return MessagePacket(
            type: MessageType.SESSION_ESTABLISHMENT,
            source: myId,
            destination: podId,
            payload: eapMsg.toData(),
            sequenceNumber: UInt8(msgSeq)
        )
    }

    private func assertIdentifier(msg: EapMessage) throws {
        if (msg.identifier != identifier) {
            log.debug("EAP-AKA: got incorrect identifier ${msg.identifier} expected: $identifier")
            throw SessionEstablishmentException.CommunicationError("Received incorrect EAP identifier: ${msg.identifier}")
        }
    }

    private func processChallengeResponse(challengeResponse: MessagePacket) throws -> EapSqn? {
        let eapMsg = try EapMessage.parse(payload: challengeResponse.payload)

        try assertIdentifier(msg: eapMsg)

        let eapSqn = try isResynchronization(eapMsg: eapMsg)
        if (eapSqn != nil) {
            return eapSqn
        }

        try assertValidAkaMessage(eapMsg: eapMsg)

        for attr in eapMsg.attributes {
            switch attr {
            case is EapAkaAttributeRes:
                if (milenage.res != attr.payload) {
                    throw SessionEstablishmentException.CommunicationError(
                        "RES mismatch." +
                            "Expected: ${milenage.res.toHex()}." +
                            "Actual: ${attr.payload.toHex()}."
                    )
                }
            case is EapAkaAttributeCustomIV:
                nodeIV = attr.payload.subdata(in: 0..<SessionEstablisher.IV_SIZE)
            default:
                throw SessionEstablishmentException.CommunicationError("Unknown attribute received: $attr")
            }
        }
        return nil
    }

    private func assertValidAkaMessage(eapMsg: EapMessage) throws {
        if (eapMsg.attributes.count != 2) {
            log.debug("EAP-AKA: got incorrect: $eapMsg")
            if (eapMsg.attributes.count == 1 && eapMsg.attributes[0] is EapAkaAttributeClientErrorCode) {
                throw SessionEstablishmentException.CommunicationError(
                    "Received CLIENT_ERROR_CODE for EAP-AKA challenge: ${eapMsg.attributes[0].toByteArray().toHex()}"
                )
            }
        throw SessionEstablishmentException.CommunicationError("Expecting two attributes, got: ${eapMsg.attributes.count}")
        }
    }

    private func isResynchronization(eapMsg: EapMessage) throws -> EapSqn? {
        if (eapMsg.subType != EapMessage.SUBTYPE_SYNCRONIZATION_FAILURE ||
            eapMsg.attributes.count != 1 ||
            eapMsg.attributes[0] as? EapAkaAttributeAuts == nil
        ) {
            return nil
        }

        let auts = eapMsg.attributes[0] as! EapAkaAttributeAuts
        let autsMilenage = try Milenage(
            k: ltk,
            sqn: eapSqn,
            randParam: milenage.rand,
            auts: auts.payload
        )

        let newSqnMilenage = try Milenage(
            k: ltk,
            sqn: autsMilenage.synchronizationSqn,
            randParam: milenage.rand,
            auts: auts.payload,
            amf: Milenage.RESYNC_AMF
        )

        if (newSqnMilenage.macS != newSqnMilenage.receivedMacS) {
            throw SessionEstablishmentException.CommunicationError(
                "MacS mismatch. " +
                    "Expected: ${newSqnMilenage.macS.toHex()}. " +
                    "Received: ${newSqnMilenage.receivedMacS.toHex()}"
            )
        }
        return try EapSqn(data: autsMilenage.synchronizationSqn)
    }

    private func eapSuccess() ->  MessagePacket {
        let eapMsg = EapMessage(
            code: EapCode.SUCCESS,
            identifier: UInt8(identifier),
            attributes: Array()
        )

        return MessagePacket(
            type: MessageType.SESSION_ESTABLISHMENT,
            source: myId,
            destination: podId,
            payload: eapMsg.toData(),
            sequenceNumber: UInt8(msgSeq)
        )
    }
}
