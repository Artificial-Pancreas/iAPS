@testable import MedtrumKit
import XCTest

final class SetBolusPacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = SetBolusPacket(bolusAmount: 2.35)

        let expected = Data([8, 19, 0, 0, 1, 47, 0, 159, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }
}
