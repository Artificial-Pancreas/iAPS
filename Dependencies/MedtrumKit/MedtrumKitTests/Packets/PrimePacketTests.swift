@testable import MedtrumKit
import XCTest

final class PrimePacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = PrimePacket()

        let expected = Data([5, 16, 0, 0, 164, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }
}
