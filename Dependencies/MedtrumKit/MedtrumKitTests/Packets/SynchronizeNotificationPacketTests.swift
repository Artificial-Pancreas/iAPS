@testable import MedtrumKit
import XCTest

final class NotificationPacketTests: XCTestCase {
    func testBasalDataProvided() throws {
        let response = Data([32, 40, 64, 6, 25, 0, 14, 0, 84, 163, 173, 17, 17, 64, 0, 152, 14, 0, 16])
        var packet = NotificationPacket()

        packet.decode(response)

        let actual = packet.parseResponse()
        XCTAssertEqual(actual.state, .active)
        XCTAssertEqual(actual.basal?.type, .ABSOLUTE_TEMP)
        XCTAssertEqual(actual.basal?.rate ?? 0, 0.85, accuracy: 0.01)
        XCTAssertEqual(actual.basal?.sequence, 25)
        XCTAssertEqual(actual.basal?.startTime, Date(timeIntervalSince1970: 1_685_126_612))
        XCTAssertEqual(actual.reservoir ?? 0, 186.80, accuracy: 0.01)
    }

    func testSequenceDataProvided() throws {
        let response = Data([32, 0, 17, 167, 0, 14, 0, 0, 0, 0, 0, 0])
        var packet = NotificationPacket()

        packet.decode(response)

        let actual = packet.parseResponse()
        XCTAssertEqual(actual.state, .active)
        XCTAssertEqual(actual.storage?.sequence, 167)
    }

    func testBolusProgress() throws {
        let response = Data([32, 34, 16, 0, 3, 0, 198, 12, 0, 0, 0, 0, 0])
        var packet = NotificationPacket()

        packet.decode(response)

        let actual = packet.parseResponse()
        XCTAssertEqual(actual.state, .active)
        XCTAssertEqual(actual.bolus?.completed, false)
        XCTAssertEqual(actual.bolus?.delivered ?? 0, 0.15, accuracy: 0.01)
        XCTAssertEqual(actual.reservoir ?? 0, 163.50, accuracy: 0.01)
    }
}
