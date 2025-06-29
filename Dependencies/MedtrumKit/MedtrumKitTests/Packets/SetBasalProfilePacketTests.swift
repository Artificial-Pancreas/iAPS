@testable import MedtrumKit
import XCTest

final class SetBasalProfilePacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = SetBasalProfilePacket(basalProfile: Data([3, 16, 14, 0, 0, 1, 2, 12, 12, 12]))

        let expected = Data([16, 21, 0, 0, 1, 3, 16, 14, 0, 0, 1, 2, 12, 12, 12, 67, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }

    func testResponseGivenPacketWhenValuesSetThenReturnCorrectValues() throws {
        let response = Data([18, 21, 16, 0, 0, 0, 1, 22, 0, 3, 0, 146, 0, 224, 238, 88, 17, 64])
        var packet = SetBasalProfilePacket(basalProfile: Data([3, 16, 14, 0, 0, 1, 2, 12, 12, 12]))

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
        let response = Data([18, 21, 16, 0, 0, 0, 1, 22, 0, 3, 0, 146, 0, 224, 238, 88, 17])
        var packet = SetBasalProfilePacket(basalProfile: Data([3, 16, 14, 0, 0, 1, 2, 12, 12, 12]))

        packet.decode(response)
        XCTAssertTrue(packet.failed)
    }
}
