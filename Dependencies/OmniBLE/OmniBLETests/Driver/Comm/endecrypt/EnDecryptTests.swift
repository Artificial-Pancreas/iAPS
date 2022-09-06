//
//  EnDecryptTests.swift
//  OmniBLE
//
//  Created by Bill Gestrich on 12/11/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import OmniBLE

class EnDecryptTest: XCTestCase {

    func testDecrypt() {
        let received = "54,57,11,a1,0c,16,03,00,08,20,2e,a9,08,20,2e,a8,34,7c,b9,7b,38,5d,45,a3,c4,0e,40,4c,55,71,5e,f3,c3,86,50,17,36,7e,62,3c,7d,0b,46,9e,81,cd,fd,9a".replacingOccurrences(of:",", with:"")
        let decryptedPayload =
            "30,2e,30,3d,00,12,08,20,2e,a9,1c,0a,1d,05,00,16,b0,00,00,00,0b,ff,01,fe".replacingOccurrences(of:",", with:"")

        let enDecrypt = EnDecrypt(
            nonce: Nonce(prefix:
                Data(hexadecimalString:"6c,ff,5d,18,b7,61,6c,ae".replacingOccurrences(of:",", with:""))!
            ),
            ck: Data(hexadecimalString: "55,79,9f,d2,66,64,cb,f6,e4,76,52,5e,2d,ee,52,c6".replacingOccurrences(of:",", with:""))!
        )
        let encryptedMessage = Data(hexadecimalString: received)!
        let decrypted = Data(hexadecimalString: decryptedPayload)!
        do {
            let msg = try MessagePacket.parse(payload: encryptedMessage)
            //AndroidAPS provides the nonceSequence in the nonce initialer, and increments it when encrypt/decrypt are called
            //This implementation increments it in MessageTransport.incrementNonceSeq, before encrypt/decrypt are called.
            let decryptedMsg = try enDecrypt.decrypt(msg, 23)

            assert(decrypted.hexadecimalString == decryptedMsg.payload.hexadecimalString)
        } catch {
            print(error)
        }

    }

    
    func testEncrypt() {
        let enDecrypt = EnDecrypt(
            nonce:Nonce(prefix:
                Data(hexadecimalString: "dda23c090a0a0a0a")!
            ),
            ck: Data(hexadecimalString: "ba1283744b6de9fab6d9b77d95a71d6e")!
        )
        let expectedEncryptedData = Data(hexadecimalString:
            "54571101070003400242000002420001" + "e09158bcb0285a81bf30635f3a17ee73f0afbb3286bc524a8a66" + "fb1bc5b001e56543")!
        let command = Data(hexadecimalString:"53302e303d000effffffff00060704ffffffff82b22c47302e30")!
        var msg = try! MessagePacket.parse(payload: expectedEncryptedData)//.copy(payload = command) // copy for the headersE
        msg.payload = command
        //AndroidAPS provides the nonceSequence in the nonce initialer, and increments it when encrypt/decrypt are called
        //This implementation increments it in MessageTransport.incrementNonceSeq, before encrypt/decrypt are called.
        let encryptedData = try! enDecrypt.encrypt(msg, 1)

        print("Original Encrypted: \(expectedEncryptedData.hexadecimalString)")
        print("Test Encrypted: \(encryptedData.asData().hexadecimalString)")
        assert(expectedEncryptedData.hexadecimalString == encryptedData.asData().hexadecimalString)
    }
     
}
