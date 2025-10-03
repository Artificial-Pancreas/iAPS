@testable import MedtrumKit
import XCTest

final class SetBolusMotorPacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = SetBolusMotorPacket()

        let expected = Data([5, 36, 0, 0, 18, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }
}
