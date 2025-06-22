@testable import MedtrumKit
import XCTest

final class SetPatchPacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = SetPatchPacket(
            alarmSettings: .LightAndVibrate,
            hourlyMaxInsulin: 40,
            dailyMaxInsulin: 180,
            expirationTimer: 0
        )

        let expected = Data([16, 35, 0, 0, 1, 32, 3, 16, 14, 0, 0, 12, 0, 0, 30, 46, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }
}
