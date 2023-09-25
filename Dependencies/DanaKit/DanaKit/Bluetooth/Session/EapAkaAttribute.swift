//
//  EapAkaAttribute.swift
//  OmniBLE
//
//  Created by Randall Knutson on 11/8/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

enum EapAkaAttributeType: UInt8 {
    case AT_RAND = 0x01
    case AT_AUTN = 0x02
    case AT_RES = 0x03
    case AT_AUTS = 0x04
    case AT_CLIENT_ERROR_CODE = 0x22
    case AT_CUSTOM_IV = 126;
}

class EapAkaAttribute {
    let SIZE_MULTIPLIER = 4 // The length for EAP-AKA attributes is a multiple of 4
    var payload: Data = Data()

    func toData() -> Data {
        return Data()
    }

    static func parseAttributes(payload: Data) throws -> Array<EapAkaAttribute>{
        var tail = payload
        var ret = Array<EapAkaAttribute>()
        while (tail.count > 0) {
            if (tail.count < 2) {
                throw MessageError.notEnoughData
            }
            let size = 4 * Int(tail[1])
            if (tail.count < size) {
                throw MessageError.notEnoughData
            }
            let type = EapAkaAttributeType(rawValue: tail[0])
            switch (type) {
            case .AT_RES:
                ret.append(try EapAkaAttributeRes.parse(payload: tail.subdata(in: 2..<EapAkaAttributeRes.SIZE)))
            case .AT_CUSTOM_IV:
                ret.append(try EapAkaAttributeCustomIV.parse(payload: tail.subdata(in: 2..<EapAkaAttributeCustomIV.SIZE)))
            case .AT_AUTN:
                ret.append(try EapAkaAttributeAutn.parse(tail.subdata(in: 2..<EapAkaAttributeAutn.SIZE)))
            case .AT_AUTS:
                ret.append(try EapAkaAttributeAuts.parse(payload: tail.subdata(in: 2..<EapAkaAttributeAuts.SIZE)))
            case .AT_RAND:
                ret.append(try EapAkaAttributeRand.parse(tail.subdata(in: 2..<EapAkaAttributeRand.SIZE)))
            case .AT_CLIENT_ERROR_CODE:
                ret.append(try EapAkaAttributeClientErrorCode.parse(payload: tail.subdata(in: 2..<EapAkaAttributeClientErrorCode.SIZE)))
            case .none:
                throw MessageError.notEnoughData
            }
            tail = tail.subdata(in: size..<tail.count)
        }
        return ret
    }
    
}

class EapAkaAttributeRand : EapAkaAttribute {
    init(payload: Data) throws {
        super.init()
        self.payload = payload
        if payload.count != 16 { throw MessageError.notEnoughData }
    }

    override func toData() -> Data {
        return Data([EapAkaAttributeType.AT_RAND.rawValue, UInt8(EapAkaAttributeRand.SIZE / SIZE_MULTIPLIER), 0x00, 0x00]) + payload
    }

    static func parse(_ payload: Data) throws -> EapAkaAttribute {
        if (payload.count < 2 + 16) {
            throw MessageError.notEnoughData
        }
        return try EapAkaAttributeRand(payload: payload.subdata(in: 2..<2 + 16))
    }

    static let SIZE = 20 // type, size, 2 reserved bytes, payload=16
}

class EapAkaAttributeAutn : EapAkaAttribute {
    init(payload: Data) throws {
        super.init()
        self.payload = payload
        if payload.count != 16 { throw MessageError.notEnoughData }
    }

    override func toData() -> Data {
        return Data([EapAkaAttributeType.AT_AUTN.rawValue, UInt8(EapAkaAttributeAutn.SIZE / SIZE_MULTIPLIER), 0x00, 0x00]) + payload
    }

    static func parse(_ payload: Data) throws -> EapAkaAttribute {
        if (payload.count < 2 + 16) {
            throw MessageError.notEnoughData
        }
        return try EapAkaAttributeAutn(payload: payload.subdata(in: 2..<2 + 16))
    }

    static let SIZE = 20 // type, size, 2 reserved bytes, payload=16
}

class EapAkaAttributeAuts : EapAkaAttribute {

    init(payload: Data) throws {
        super.init()
        self.payload = payload
        if payload.count != 14 { throw MessageError.notEnoughData }
    }

    override func toData() -> Data {
        return Data([EapAkaAttributeType.AT_AUTS.rawValue, UInt8(EapAkaAttributeAuts.SIZE / SIZE_MULTIPLIER), 0x00, 0x00]) + payload
    }


    static func parse(payload: Data) throws -> EapAkaAttribute {
        if (payload.count < SIZE - 2) {
            throw MessageError.notEnoughData
        }
        return try EapAkaAttributeAuts(payload: payload)
    }

    static let SIZE = 16 // type, size, 2 reserved bytes, payload=16
}

class EapAkaAttributeRes: EapAkaAttribute {

    init(payload: Data) throws {
        super.init()
        self.payload = payload
        if payload.count != 8 { throw MessageError.notEnoughData }
    }

    override func toData() -> Data {
        return Data([
            EapAkaAttributeType.AT_RES.rawValue,
            UInt8(EapAkaAttributeRes.SIZE / SIZE_MULTIPLIER),
            0x00,
            UInt8(EapAkaAttributeRes.PAYLOAD_SIZE_BITS)
        ]) + payload
    }

    static func parse(payload: Data) throws -> EapAkaAttributeRes {
        if (payload.count < 2 + 8) {
            throw MessageError.notEnoughData
        }
        return try EapAkaAttributeRes(payload: payload.subdata(in: 2..<2 + 8))
    }

    static let SIZE = 12 // type, size, len in bits=2, payload=8
    static private let PAYLOAD_SIZE_BITS = 0x64 // type, size, 2 reserved bytes, payload
}

class EapAkaAttributeCustomIV: EapAkaAttribute {

    init(payload: Data) throws {
        super.init()
        self.payload = payload
        if payload.count != 4 { throw MessageError.notEnoughData }
    }

    override func toData() -> Data {
        return Data([EapAkaAttributeType.AT_CUSTOM_IV.rawValue, UInt8(EapAkaAttributeCustomIV.SIZE / SIZE_MULTIPLIER), 0x00, 0x00]) + payload
    }

    static func parse(payload: Data) throws -> EapAkaAttributeCustomIV {
        if (payload.count < 2 + 4) {
            throw MessageError.notEnoughData
        }
        return try EapAkaAttributeCustomIV(payload: payload.subdata(in: 2..<2 + 4))
    }

    static let SIZE = 8 // type, size, 2 reserved bytes, payload=4
}

class EapAkaAttributeClientErrorCode: EapAkaAttribute {

    init(payload: Data) throws {
        super.init()
        self.payload = payload
        if payload.count != 2 { throw MessageError.notEnoughData }
    }

    override func toData() -> Data {
        return Data([EapAkaAttributeType.AT_CLIENT_ERROR_CODE.rawValue, UInt8(EapAkaAttributeClientErrorCode.SIZE / SIZE_MULTIPLIER), 0x00, 0x00]) + payload
    }

    static func parse(payload: Data) throws -> EapAkaAttributeClientErrorCode {
        if (payload.count < 2 + 2) {
            throw MessageError.notEnoughData
        }
        return try EapAkaAttributeClientErrorCode(payload: payload.subdata(in: 2..<4))
    }

    static let SIZE = 4 // type, size=1, payload:2
}
