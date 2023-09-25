//
//  RandomByteGenerator.swift
//  OmniBLE
//
//  Created by Randall Knutson on 8/8/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
class OmniRandomByteGenerator: RandomByteGenerator {
    func nextBytes(length: Int) -> Data {
        var bytes = [Int8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess { // Always test the status.
            return Data(bytes: bytes, count: bytes.count)
        }
        return Data()
    }
}

protocol RandomByteGenerator {
    func nextBytes(length: Int) -> Data
}
