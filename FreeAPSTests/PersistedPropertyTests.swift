@testable import FreeAPS
import XCTest

final class PersistedPropertyTests: XCTestCase {
    private var directory: URL!

    private var fileURL: URL { directory.appendingPathComponent("State.plist") }

    /// Stands in for the file between sets: still there after a set, the set did not write
    private let marker = Data("not written".utf8)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistedPropertyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeProperty(_ url: URL? = nil) -> PersistedProperty<[String: Any]> {
        PersistedProperty(key: "State", storageURL: url ?? fileURL)
    }

    private func state(
        date: Date = Date(timeIntervalSinceReferenceDate: 814_305_600.520_279),
        sequence: Int = 42,
        token: Data = Data([0x01, 0x02, 0x03])
    ) -> [String: Any] {
        [
            "lastSync": date,
            "sessionToken": token,
            "currentSequenceNumber": sequence,
            "reservoir": 43.85,
            "isOnboarded": true,
            "pumpSN": "AABBCC",
            "basalDose": ["value": 0.65, "startDate": date, "automatic": true] as [String: Any],
            "awaitingRecord": [["sequence": sequence, "units": 0.45] as [String: Any]],
            "skippedRecordSequences": [3, 5, 8]
        ]
    }

    private func putMarker() throws {
        try marker.write(to: fileURL)
    }

    private func fileHoldsMarker() throws -> Bool {
        try Data(contentsOf: fileURL) == marker
    }

    private func fileValue() throws -> [String: Any]? {
        try PropertyListSerialization.propertyList(from: Data(contentsOf: fileURL), options: [], format: nil) as? [String: Any]
    }

    func testTheSameValueIsNotWrittenAgain() throws {
        let property = makeProperty()
        property.wrappedValue = state()
        XCTAssertEqual(try fileValue().map { $0 as NSDictionary }, state() as NSDictionary)

        try putMarker()
        property.wrappedValue = state()
        XCTAssertTrue(try fileHoldsMarker())
    }

    func testAChangedValueIsWritten() throws {
        let property = makeProperty()

        func changing(_ change: (inout [String: Any]) -> Void) -> [String: Any] {
            var value = state()
            change(&value)
            return value
        }

        for changed in [
            changing { $0["currentSequenceNumber"] = 43 }, // a number
            changing { $0["skippedRecordSequences"] = [3, 5, 9] }, // an array element
            changing { $0["lastSync"] = Date(timeIntervalSinceReferenceDate: 814_305_600.521_279) }, // a date, by 1 ms
            changing { $0["sessionToken"] = Data([0x01, 0x02, 0x04]) }, // data
            changing { // a nested value
                var basalDose = $0["basalDose"] as! [String: Any]
                basalDose["value"] = 0.7
                $0["basalDose"] = basalDose
            }
        ] {
            property.wrappedValue = state()
            try putMarker()
            property.wrappedValue = changed
            XCTAssertFalse(try fileHoldsMarker())
            XCTAssertEqual(try fileValue().map { $0 as NSDictionary }, changed as NSDictionary)
        }
    }

    func testTheValueReadIsNotWrittenBack() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: state(), format: .binary, options: 0)
        try data.write(to: fileURL)

        let property = makeProperty()
        XCTAssertEqual(property.wrappedValue.map { $0 as NSDictionary }, state() as NSDictionary)

        try putMarker()
        property.wrappedValue = state()
        XCTAssertTrue(try fileHoldsMarker())
    }

    func testNilDeletesTheFileAndTheNextValueIsWritten() throws {
        let property = makeProperty()
        property.wrappedValue = state()

        property.wrappedValue = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        property.wrappedValue = state()
        XCTAssertEqual(try fileValue().map { $0 as NSDictionary }, state() as NSDictionary)
    }

    func testAFailedWriteIsNotTakenForWritten() throws {
        let missing = directory.appendingPathComponent("missing", isDirectory: true)
        let url = missing.appendingPathComponent("State.plist")
        let property = makeProperty(url)

        property.wrappedValue = state()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
        property.wrappedValue = state()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testAFailedWriteLeavesTheValueBeforeKnown() throws {
        let property = makeProperty()
        property.wrappedValue = state()

        // Not a plist value: nothing is written, the file keeps the one before
        var unwritable = state()
        unwritable["notAPlistValue"] = UUID()
        property.wrappedValue = unwritable
        XCTAssertEqual(try fileValue().map { $0 as NSDictionary }, state() as NSDictionary)

        try putMarker()
        property.wrappedValue = state()
        XCTAssertTrue(try fileHoldsMarker())
    }
}
