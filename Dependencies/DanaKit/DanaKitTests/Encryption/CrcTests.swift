//
//  CrcTests.swift
//  DanaKitTests
//
//  Created by Bastiaan Verhaar on 06/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

import XCTest
@testable import DanaKit

class CRCTests: XCTestCase {

    func testGenerateCrcEnhancedEncryption0IsEncryptionCommandTrue() {
        // pump_check command
        let data: [UInt8] = [1, 0] + Array(DEVICE_NAME.utf8)
        let crc = generateCrc(buffer: Data(data), enhancedEncryption: 0, isEncryptionCommand: true)
        
        XCTAssertEqual(crc, 0xbc7a)
    }

    func testGenerateCrcEnhancedEncryption1IsEncryptionCommandFalse() {
        // BasalSetTemporary command (200%, 1 hour)
        let data: [UInt8] = [161, 96, 200, 1]
        let crc = generateCrc(buffer: Data(data), enhancedEncryption: 1, isEncryptionCommand: false)

        XCTAssertEqual(crc, 0x33fd)
    }

    func testGenerateCrcEnhancedEncryption1IsEncryptionCommandTrue() {
        // TIME_INFORMATION command -> sendTimeInfo
        let data: [UInt8] = [1, 1]
        let crc = generateCrc(buffer: Data(data), enhancedEncryption: 1, isEncryptionCommand: true)

        XCTAssertEqual(crc, 0x0990)
    }

    func testGenerateCrcEnhancedEncryption2IsEncryptionCommandFalse() {
        // BasalSetTemporary command (200%, 1 hour)
        let data: [UInt8] = [161, 96, 200, 1]
        let crc = generateCrc(buffer: Data(data), enhancedEncryption: 2, isEncryptionCommand: false)

        XCTAssertEqual(crc, 0x7a1a)
    }

    func testGenerateCrcEnhancedEncryption2IsEncryptionCommandTrue() {
        // TIME_INFORMATION command -> sendBLE5PairingInformation
        let data: [UInt8] = [1, 1, 0, 0, 0, 0]
        let crc = generateCrc(buffer: Data(data), enhancedEncryption: 2, isEncryptionCommand: true)

        XCTAssertEqual(crc, 0x1fef)
    }
}
