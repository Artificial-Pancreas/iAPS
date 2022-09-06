//
//  Milenage.swift
//  OmniBLE
//
//  Created by Randall Knutson on 11/8/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import os.log
import CryptoSwift

enum MilenageError: Error {
    case Error(String)
}

class Milenage {
    static let RESYNC_AMF = Data(hex: "0000")
    static let MILENAGE_OP = Data(hex: "cdc202d5123e20f62b6d676ac72cb318")
    static let MILENAGE_AMF = Data(hex: "b9b9")
    static let KEY_SIZE = 16
    static let AUTS_SIZE = 14
    static private let SQN = 6

    private let log = OSLog(subsystem: "Milenage", category: "Milenage")
    private let k: Data
    let sqn: Data
    let auts: Data
    let amf: Data
    var ck: Data
    var autn: Data
    var rand: Data
    var synchronizationSqn: Data
    var res: Data
    var ak: Data
    var macS: Data
    var receivedMacS: Data

    init(k: Data, sqn: Data, randParam: Data? = nil, auts: Data = Data(repeating: 0x00, count: 14), amf: Data = Milenage.MILENAGE_AMF) throws {
        guard (k.count == Milenage.KEY_SIZE) else { throw MilenageError.Error("Milenage key has to be \(Milenage.KEY_SIZE) bytes long. Received: \(k.hexadecimalString)") }
        guard (sqn.count == Milenage.SQN) else { throw MilenageError.Error("Milenage SQN has to be \(Milenage.SQN) long. Received: \(sqn.hexadecimalString)") }
        guard (auts.count == Milenage.AUTS_SIZE) else { throw MilenageError.Error("Milenage AUTS has to be \(Milenage.AUTS_SIZE) long. Received: \(auts.hexadecimalString)") }
        guard (amf.count == Milenage.MILENAGE_AMF.count) else {
                throw MilenageError.Error("Milenage AMF has to be ${MILENAGE_AMF.count} long." +
                    "Received: ${amf.toHex()}")
            }
        self.k = k
        self.sqn = sqn
        self.auts = auts
        self.amf = amf

        let cipher = try AES(key: k.bytes, blockMode: ECB(), padding: .noPadding)

        let random = OmniRandomByteGenerator()
        rand = randParam ?? random.nextBytes(length: Milenage.KEY_SIZE)

        let opc = Data(try cipher.encrypt(Milenage.MILENAGE_OP.bytes)) ^ Milenage.MILENAGE_OP
        let randOpcEncrypted = Data(try cipher.encrypt((rand ^ opc).bytes))
        let randOpcEncryptedxorOpc = randOpcEncrypted ^ opc
        var resAkInput = randOpcEncryptedxorOpc.subdata(in: 0..<Milenage.KEY_SIZE)

        resAkInput[15] = UInt8(Int(resAkInput[15]) ^ 1)

        let resAk = Data(try cipher.encrypt(resAkInput.bytes)) ^ opc

        res = resAk.subdata(in: 8..<16)
        ak = resAk.subdata(in: 0..<6)

        var ckInput = Array<UInt8>(repeating: 0x00, count: Milenage.KEY_SIZE)

        for i in 0...15 {
            ckInput[(i + 12) % 16] = randOpcEncryptedxorOpc[i]
        }
        ckInput[15] = UInt8((Int(ckInput[15]) ^ 2))

        ck = Data(try cipher.encrypt(ckInput)) ^ opc

        let sqnAmf = sqn + amf + sqn + amf
        let sqnAmfxorOpc = sqnAmf ^ opc
        var macAInput = Array<UInt8>(repeating: 0x00, count: Milenage.KEY_SIZE)

        for i in 0...15 {
            macAInput[(i + 8) % 16] = sqnAmfxorOpc[i]
        }

        let macAFull = Data(try cipher.encrypt((Data(macAInput) ^ randOpcEncrypted).bytes)) ^ opc
        let macA = macAFull.subdata(in: 0..<8)
        macS = macAFull.subdata(in: 8..<16)

        autn = (ak ^ sqn) + amf + macA

        // Used for re-synchronisation AUTS = SQN^AK || MAC-S
        var akStarInput = Array<UInt8>(repeating: 0x00, count: Milenage.KEY_SIZE)

        for i in 0...15 {
            akStarInput[(i + 4) % 16] = randOpcEncryptedxorOpc[i]
        }
        akStarInput[15] = UInt8((Int(akStarInput[15]) ^ 8))

        let akStarFull = Data(try cipher.encrypt(akStarInput)) ^ opc
        let akStar = akStarFull.subdata(in: 0..<6)

        let seqxorAkStar = auts.subdata(in: 0..<6)
        synchronizationSqn = akStar ^ seqxorAkStar
        receivedMacS = auts.subdata(in: 6..<14)

        // print("Milenage K: \(k.hexadecimalString)")
        // print("Milenage RAND: \(rand.hexadecimalString)")
        // print("Milenage SQN: \(sqn.hexadecimalString)")
        // print("Milenage CK: \(ck.hexadecimalString)")
        // print("Milenage AUTN: \(autn.hexadecimalString)")
        // print("Milenage RES: \(res.hexadecimalString)")
        // print("Milenage AK: \(ak.hexadecimalString)")
        // print("Milenage AK STAR: \(akStar.hexadecimalString)")
        // print("Milenage OPC: \(opc.hexadecimalString)")
        // print("Milenage FullMAC: \(macAFull.hexadecimalString)")
        // print("Milenage MacA: \(macA.hexadecimalString)")
        // print("Milenage MacS: \(macS.hexadecimalString)")
        // print("Milenage AUTS: \(auts.hexadecimalString)")
        // print("Milenage synchronizationSqn: \(synchronizationSqn.hexadecimalString)")
        // print("Milenage receivedMacS: \(receivedMacS.hexadecimalString)")
    }

}

extension Data {
    static func ^ (left: Data, right: Data) -> Data {
        var out = Array<UInt8>(repeating: 0x00, count: left.count)
        for i in 0..<left.count {
            out[i] = UInt8(Int(left[i]) ^ Int(right[i]))
        }
        return Data(out)
    }
}
