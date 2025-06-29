@testable import MedtrumKit
import XCTest

final class ActivatePacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = ActivatePacket(
            expirationTimer: 1,
            alarmSetting: .BeepOnly,
            hourlyMaxInsulin: 40,
            dailyMaxInsulin: 180,
            currentTDD: 0,
            basalProfile: Data([3, 16, 14, 0, 0, 1, 2, 12, 12, 12])
        )

        let expected1 = Data([29, 18, 0, 1, 0, 12, 1, 6, 0, 0, 30, 32, 3, 16, 14, 0, 0, 1, 3, 150])
        let expected2 = Data([29, 18, 0, 2, 16, 14, 0, 0, 1, 2, 12, 12, 12, 217, 9])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 2)
        XCTAssertEqual(actual[0], expected1)
        XCTAssertEqual(actual[1], expected2)
    }

    func testResponseGivenPacketWhenValuesSetThenReturnCorrectValues() throws {
        let response = Data([26, 18, 19, 1, 0, 0, 41, 0, 0, 0, 152, 91, 28, 17, 1, 30, 0, 1, 0, 41, 0, 224, 238, 88, 17, 184])
        var packet = ActivatePacket(
            expirationTimer: 1,
            alarmSetting: .BeepOnly,
            hourlyMaxInsulin: 40,
            dailyMaxInsulin: 180,
            currentTDD: 0,
            basalProfile: Data([3, 16, 14, 0, 0, 1, 2, 12, 12, 12])
        )

        packet.decode(response)
        XCTAssertFalse(packet.failed)

        let actual = packet.parseResponse()
        XCTAssertEqual(actual.patchId, Data([41, 0, 0, 0]))
        XCTAssertEqual(actual.time, Date(timeIntervalSince1970: 1_675_605_528))
        XCTAssertEqual(actual.basalType, BasalType.STANDARD)
        XCTAssertEqual(actual.basalValue, 1.5)
        XCTAssertEqual(actual.basalSequence, 1)
        XCTAssertEqual(actual.basalPatchId, 41)
        XCTAssertEqual(actual.basalStartTime, Date(timeIntervalSince1970: 1_679_575_392))
    }

    func testResponseGivenResponseWhenMessageTooShortThenResultFalse() throws {
        let response = Data([26, 18, 19, 1, 0, 0, 41, 0, 0, 0, 152, 91, 28, 17, 1, 30, 0, 1, 0, 41, 0, 152, 91, 28, 17])
        var packet = ActivatePacket(
            expirationTimer: 1,
            alarmSetting: .BeepOnly,
            hourlyMaxInsulin: 40,
            dailyMaxInsulin: 180,
            currentTDD: 0,
            basalProfile: Data([3, 16, 14, 0, 0, 1, 2, 12, 12, 12])
        )

        packet.decode(response)
        XCTAssertTrue(packet.failed)
    }
}
