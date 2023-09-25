//
//  X25519KeyGenerator.swift
//  OmniBLE
//
//  Created by Randall Knutson on 8/8/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//
import CryptoKit
import Foundation

struct X25519KeyGenerator: PrivateKeyGenerator {
    func generatePrivateKey() -> Data {
        let key = Curve25519.KeyAgreement.PrivateKey()
        return key.rawRepresentation
    }
    func publicFromPrivate(_ privateKey: Data) throws -> Data{
        let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        return key.publicKey.rawRepresentation
    }
    func computeSharedSecret(_ privateKey: Data, _ publicKey: Data) throws -> Data {
        let priv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        let pub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)
        let secret = try priv.sharedSecretFromKeyAgreement(with: pub)
        return secret.withUnsafeBytes({ return Data($0)})
    }
}

protocol PrivateKeyGenerator {
    func generatePrivateKey() -> Data
    func publicFromPrivate(_ privateKey: Data) throws -> Data
    func computeSharedSecret(_ privateKey: Data, _ publicKey: Data) throws -> Data
}
