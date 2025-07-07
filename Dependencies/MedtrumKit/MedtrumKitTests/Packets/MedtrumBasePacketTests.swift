@testable import MedtrumKit
import XCTest

final class MedtrumBasePacketTests: XCTestCase {
    func testWriteAuthorizeCommandExpectOnePacket() throws {
        let input = AuthorizePacket(pumpSN: Data([217, 249, 118, 170]), sessionToken: Data([0, 0, 0, 0]))
        let expected = Data([14, 5, 0, 0, 2, 0, 0, 0, 0, 235, 57, 134, 200, 163, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }

    func testWriteActivateCommandExpectThreePackets() throws {
        let input = ActivatePacket(
            expirationTimer: 0,
            alarmSetting: .LightOnly,
            hourlyMaxInsulin: 40,
            dailyMaxInsulin: 180,
            currentTDD: 0,
            basalProfile: Data([7, 0, 160, 2, 240, 96, 2, 104, 33, 2, 224, 225, 1, 192, 3, 2, 236, 36, 2, 100, 133, 2])
        )

        let expected1 = Data([41, 18, 0, 1, 0, 12, 0, 3, 0, 0, 30, 32, 3, 16, 14, 0, 0, 1, 7, 173])
        let expected2 = Data([41, 18, 0, 2, 0, 160, 2, 240, 96, 2, 104, 33, 2, 224, 225, 1, 192, 3, 2, 253])
        let expected3 = Data([41, 18, 0, 3, 236, 36, 2, 100, 133, 2, 144, 163])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 3)
        XCTAssertEqual(actual[0], expected1)
        XCTAssertEqual(actual[1], expected2)
        XCTAssertEqual(actual[2], expected3)
    }
}
