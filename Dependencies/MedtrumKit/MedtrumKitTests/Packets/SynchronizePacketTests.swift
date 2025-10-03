@testable import MedtrumKit
import XCTest

final class SynchronizePacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = SynchronizePacket()

        let expected = Data([5, 3, 0, 0, 252, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }

    func testResponseGivenPacketWhenValuesSetThenReturnCorrectValues() throws {
        let response = Data([
            0,
            3,
            0,
            0,
            0,
            0,
            1,
            206,
            15,
            0,
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            11,
            12,
            13,
            14,
            15,
            16,
            17,
            18,
            19,
            20,
            21,
            22,
            23,
            24,
            26,
            27,
            28,
            29,
            30,
            31,
            32,
            33,
            34,
            35,
            36,
            37,
            38,
            39,
            40,
            41,
            42,
            233
        ])
        var packet = SynchronizePacket()

        packet.decode(response)
        XCTAssertFalse(packet.failed)

        let actual = packet.parseResponse()
        XCTAssertEqual(actual.state, .idle)
    }

    func testResponseGivenSplittedPacketsWhenValuesSetThenReturnCorrectValues() throws {
        let response1 = Data([23, 3, 4, 1, 0, 0, 2, 160, 5, 59, 15, 132, 59, 90, 1, 0, 50, 0, 110, 48])
        let response2 = Data([23, 3, 4, 2, 6, 0, 0, 182, 224])
        var packet = SynchronizePacket()

        packet.decode(response1)
        packet.decode(response2)
        XCTAssertFalse(packet.failed)
        XCTAssertTrue(packet.isComplete)

        let actual = packet.parseResponse()
        XCTAssertEqual(actual.state, .filled)
    }

    func testResponseGivenResponseWhenMessageTooShortThenResultFalse() throws {
        let response = Data([
            0,
            3,
            0,
            0,
            0,
            0,
            1,
            206,
            15,
            0,
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            11,
            12,
            13,
            14,
            15,
            16,
            17,
            18,
            19,
            20,
            21,
            22,
            23,
            24,
            26,
            27,
            28,
            29,
            30,
            31,
            32,
            33,
            34,
            35,
            36,
            37,
            38,
            39,
            40,
            41,
            42
        ])
        var packet = SynchronizePacket()

        packet.decode(response)
        XCTAssertTrue(packet.failed)
    }

    func testResponseContainingSyncDataThenDataSaved() throws {
        let response = Data([
            47,
            3,
            3,
            1,
            0,
            0,
            32,
            238,
            13,
            128,
            5,
            0,
            128,
            0,
            0,
            6,
            25,
            0,
            14,
            0,
            84,
            163,
            173,
            17,
            17,
            64,
            0,
            152,
            14,
            248,
            137,
            173,
            17,
            240,
            11,
            90,
            26,
            0,
            14,
            0,
            187,
            31,
            0,
            0,
            140,
            14,
            200,
            242
        ])
        var packet = SynchronizePacket()

        packet.decode(response)
        XCTAssertFalse(packet.failed)

        let actual = packet.parseResponse()
        XCTAssertEqual(actual.state, .active)
        XCTAssertEqual(actual.basal?.type, .ABSOLUTE_TEMP)
        XCTAssertEqual(actual.basal!.rate, 0.85, accuracy: 0.01)
        XCTAssertEqual(actual.basal?.sequence, 25)
        XCTAssertEqual(actual.basal?.patchId, 14)
        XCTAssertEqual(actual.basal?.startTime, Date(timeIntervalSince1970: 1_685_126_612))
        XCTAssertEqual(actual.patchAge, 8123)
        XCTAssertEqual(actual.startTime, Date(timeIntervalSince1970: 1_685_120_120))
        XCTAssertTrue(actual.battery != nil)
        XCTAssertEqual(actual.battery!.voltageA, 5.96875, accuracy: 0.01)
        XCTAssertEqual(actual.battery!.voltageB, 2.8125, accuracy: 0.01)
    }
}
