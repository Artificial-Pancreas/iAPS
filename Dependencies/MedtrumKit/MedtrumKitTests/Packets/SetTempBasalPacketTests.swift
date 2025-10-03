@testable import MedtrumKit
import XCTest

final class SetTempBasalPacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = SetTempBasalPacket(rate: 1.25, duration: .hours(1))

        let expected = Data([10, 24, 0, 0, 6, 25, 0, 60, 0, 59, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }

    func testResponseGivenPacketWhenValuesSetThenReturnCorrectValues() throws {
        let response = Data([18, 24, 12, 0, 0, 0, 6, 25, 0, 2, 0, 146, 0, 224, 238, 88, 17, 181])
        var packet = SetTempBasalPacket(rate: 1.25, duration: .hours(1))

        packet.decode(response)
        XCTAssertFalse(packet.failed)

        let actual = packet.parseResponse()
        XCTAssertEqual(actual.basalType, BasalType.ABSOLUTE_TEMP)
        XCTAssertEqual(actual.basalValue, 1.25)
        XCTAssertEqual(actual.basalSequence, 2)
        XCTAssertEqual(actual.basalPatchId, 146)
        XCTAssertEqual(actual.basalStartTime, Date(timeIntervalSince1970: 1_679_575_392))
    }

    func testResponseGivenResponseWhenMessageTooShortThenResultFalse() throws {
        let response = Data([18, 24, 12, 0, 0, 0, 6, 25, 0, 2, 0, 146, 0, 224, 238, 88, 17])
        var packet = SetTempBasalPacket(rate: 1.25, duration: .hours(1))

        packet.decode(response)
        XCTAssertTrue(packet.failed)
    }
}
