//
//  KeyExchangeTests.swift
//  OmniBLE
//
//  Created by Bill Gestrich on 12/11/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import OmniBLE

class KeyExchangeTest: XCTestCase {
    
    func testKeyExchange() {

        let pdmNonce = Data(hexadecimalString:"edfdacb242c7f4e1d2bc4d93ca3c5706")!
        
        let privateKey = Data(hexadecimalString: "27ec94b71a201c5e92698d668806ae5ba00594c307cf5566e60c1fc53a6f6bb6")!
        let privateKeyGenerator = MockFixedPrivateKeyGenerator(fixedPrivateKey: privateKey, generator: X25519KeyGenerator())
        let randomByteGenerator = MockRandomByteGenerator(fixedData: pdmNonce)
        let ke = try! KeyExchange(
            privateKeyGenerator,
            randomByteGenerator
        )
        let podPublicKey = Data(hexadecimalString:"2fe57da347cd62431528daac5fbb290730fff684afc4cfc2ed90995f58cb3b74")!
        let podNonce = Data(hexadecimalString: "00000000000000000000000000000000")!
        try! ke.updatePodPublicData(podPublicKey + podNonce)
        assert(ke.pdmPublic.hexadecimalString == "f2b6940243aba536a66e19fb9a39e37f1e76a1cd50ab59b3e05313b4fc93975e")
        assert(ke.pdmConf.hexadecimalString == "5fc3b4da865e838ceaf1e9e8bb85d1ac")
        try! ke.validatePodConf(Data(hexadecimalString: "af4f10db5f96e5d9cd6cfc1f54f4a92f")!)
        assert(ke.ltk.hexadecimalString == "341e16d13f1cbf73b19d1c2964fee02b")
    }
}



struct MockRandomByteGenerator: RandomByteGenerator {
    
    let fixedData: Data
    
    func nextBytes(length: Int) -> Data {
        return fixedData
    }
}

struct MockFixedPrivateKeyGenerator: PrivateKeyGenerator {
    
    let fixedPrivateKey: Data
    private let realGenerator: PrivateKeyGenerator
    
    init(fixedPrivateKey: Data, generator: PrivateKeyGenerator){
        self.fixedPrivateKey = fixedPrivateKey
        self.realGenerator = generator
    }
    
    func generatePrivateKey() -> Data {
        return fixedPrivateKey
    }
    
    func publicFromPrivate(_ privateKey: Data) throws -> Data {
        assert(privateKey == self.fixedPrivateKey)
        return try realGenerator.publicFromPrivate(privateKey)
    }
    
    func computeSharedSecret(_ privateKey: Data, _ publicKey: Data) throws -> Data {
        assert(privateKey == self.fixedPrivateKey)
        return try realGenerator.computeSharedSecret(privateKey, publicKey)
    }
    
}
