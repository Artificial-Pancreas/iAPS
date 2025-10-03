@testable import MedtrumKit
import XCTest

final class CancelTempBasalPacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = CancelTempBasalPacket()

        let expected = Data([5, 25, 0, 0, 167, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }

    func testResponseGivenPacketWhenValuesSetThenReturnCorrectValues() throws {
        let response = Data([18, 25, 16, 0, 0, 0, 1, 22, 0, 3, 0, 146, 0, 224, 238, 88, 17, 88])
        var packet = CancelTempBasalPacket()

        packet.decode(response)
        XCTAssertFalse(packet.failed)

        let actual = packet.parseResponse()
        XCTAssertEqual(actual.basalType, BasalType.STANDARD)
        XCTAssertEqual(actual.basalValue, 1.1)
        XCTAssertEqual(actual.basalSequence, 3)
        XCTAssertEqual(actual.basalPatchId, 146)
        XCTAssertEqual(actual.basalStartTime, Date(timeIntervalSince1970: 1_679_575_392))
    }

    func testResponseGivenResponseWhenMessageTooShortThenResultFalse() throws {
        let response = Data([18, 25, 16, 0, 0, 0, 1, 22, 0, 3, 0, 146, 0, 224, 238, 88, 17])
        var packet = CancelTempBasalPacket()

        packet.decode(response)
        XCTAssertTrue(packet.failed)
    }
}
