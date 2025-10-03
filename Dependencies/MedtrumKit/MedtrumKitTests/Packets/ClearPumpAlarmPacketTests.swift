@testable import MedtrumKit
import XCTest

final class ClearPumpAlarmPacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = ClearPumpAlarmPacket(alarmType: .hourlyMax)

        let expected = Data([6, 115, 0, 0, 4, 10, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }
}
