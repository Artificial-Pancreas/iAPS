//
//  EapMessage.swift
//  OmniBLE
//
//  Created by Randall Knutson on 11/8/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

enum EapCode: UInt8 {
    case REQUEST = 0x01
    case RESPONSE = 0x02
    case SUCCESS = 0x03
    case FAILURE = 0x04
}

struct EapMessage {
    var code: EapCode
    var identifier: UInt8
    var subType: UInt8 = 0
    var attributes: [EapAkaAttribute]

    func toData() -> Data {

        var joinedAttributes = Data()
        for attribute in attributes {
            joinedAttributes.append(attribute.toData())
        }

        let attrSize = joinedAttributes.count
        if (attrSize == 0) {
            return Data([code.rawValue, identifier, 0x00, 0x04])
        }
        let totalSize = EapMessage.HEADER_SIZE + attrSize

        var bb = Data()
        bb.append(code.rawValue)
        bb.append(identifier)
        bb.append(UInt8((totalSize >> 8) & 0xFF))
        bb.append(UInt8(totalSize & 0xFF))
        bb.append(UInt8(EapMessage.AKA_PACKET_TYPE))
        bb.append(UInt8(EapMessage.SUBTYPE_AKA_CHALLENGE))
        bb.append(Data([0x00, 0x00]))
        bb.append(joinedAttributes)

        return bb
    }

    private static let HEADER_SIZE = 8
    private static let SUBTYPE_AKA_CHALLENGE = 0x01
    static let SUBTYPE_SYNCRONIZATION_FAILURE = 0x04

    private static let AKA_PACKET_TYPE = 0x17

    static func parse(payload: Data) throws -> EapMessage {
        guard payload.count > 4 else { throw MessageError.notEnoughData }

        let totalSize = (Int(payload[2]) << 8) | Int(payload[3])
        guard payload.count == totalSize else { throw MessageError.notEnoughData }


        if (payload.count == 4) { // SUCCESS/FAILURE
            return EapMessage(
                code: EapCode(rawValue: payload[0])!,
                identifier: payload[1],
                attributes: []
            )
        }
        if (totalSize > 0 && payload[4] != AKA_PACKET_TYPE) {
            throw MessageError.validationFailed(description: "Invalid eap payload.")
        }
        let attributesPayload = payload.subdata(in: 8..<totalSize)

        return EapMessage(
            code: EapCode(rawValue: payload[0])!,
            identifier: payload[1],
            subType: payload[5],
            attributes: try EapAkaAttribute.parseAttributes(payload: attributesPayload)
        )
        
    }
}
