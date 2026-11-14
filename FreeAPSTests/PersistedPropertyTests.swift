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

final class KnownPluginsDanaDetectionTests: XCTestCase {
    func testNoPumpIsNotADanaPump() {
        XCTAssertFalse(KnownPlugins.isDanaPump(pluginIdentifier: nil))
    }

    func testDanaIsDetectedByPluginIdentifier() {
        // DanaKitPumpManager.pluginIdentifier, as stored with the pump manager's raw state
        XCTAssertTrue(KnownPlugins.isDanaPump(pluginIdentifier: "Dana"))
    }

    func testOtherPumpsAndPumpNamesAreNotDana() {
        XCTAssertFalse(KnownPlugins.isDanaPump(pluginIdentifier: "Omnipod-Dash"))
        XCTAssertFalse(KnownPlugins.isDanaPump(pluginIdentifier: "Medtrum"))
        // a display name is not an identifier
        XCTAssertFalse(KnownPlugins.isDanaPump(pluginIdentifier: "Dana-i/RS"))
        XCTAssertFalse(KnownPlugins.isDanaPump(pluginIdentifier: ""))
    }
}

/// `DataMigrations`' registry and records: what runs at a start, what is recorded, and the downgrade paths (a newer
/// build's records: the warning that waits for the user, or the blocked start).
final class DataMigrationsRegistryTests: XCTestCase {
    private final class Runs: @unchecked Sendable {
        private let lock = NSLock()
        private var ids: [String] = []

        func add(_ id: String) {
            lock.lock()
            ids.append(id)
            lock.unlock()
        }

        var all: [String] {
            lock.lock()
            defer { lock.unlock() }
            return ids
        }
    }

    private struct Failure: Error {}

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var runs: Runs!

    private var store: DataMigrationRecordStore { DataMigrationRecordStore(defaults: defaults) }

    override func setUpWithError() throws {
        suiteName = "DataMigrationsRegistryTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        runs = Runs()
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func migration(_ id: String, downgradable: Bool = true, fails: Bool = false) -> DataMigration {
        let runs = runs!
        return DataMigration(
            id: id,
            description: "description of \(id)",
            downgradeInfo: "check \(id)",
            downgradable: downgradable
        ) {
            if fails { throw Failure() }
            runs.add(id)
        }
    }

    private func record(_ id: String, downgradable: Bool = true) -> DataMigrationRecord {
        DataMigrationRecord(
            id: id,
            description: "description of \(id)",
            downgradeInfo: nil,
            downgradable: downgradable,
            appliedAt: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "9.9 (1)"
        )
    }

    @MainActor private func migrations(_ registry: [DataMigration]) -> DataMigrations {
        DataMigrations(defaults: defaults, registry: registry, appVersion: "1.2 (3)")
    }

    /// Starts `migrations` and returns once it waits on the downgrade warning.
    @MainActor private func startUntilWarning(_ migrations: DataMigrations) async throws -> Task<Void, Error> {
        let start = Task { try await migrations.runMigrations() }
        for _ in 0 ..< 2000 where migrations.downgradeWarning == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNotNil(migrations.downgradeWarning)
        return start
    }

    // MARK: - the plan

    func testPlanRunsTheMigrationsWithoutARecordInRegistryOrder() {
        let registry = [migration("a"), migration("b"), migration("c")]
        guard case let .run(pending) = DataMigrations.plan(records: [record("b")], registry: registry) else {
            return XCTFail("expected .run")
        }
        XCTAssertEqual(pending.map(\.id), ["a", "c"])
    }

    func testPlanWarnsAboutUnknownDowngradableRecords() {
        let records = [record("a"), record("future-1"), record("future-2")]
        guard case let .downgradeWarning(unknown) = DataMigrations.plan(records: records, registry: [migration("a")])
        else {
            return XCTFail("expected .downgradeWarning")
        }
        XCTAssertEqual(unknown.map(\.id), ["future-1", "future-2"])
    }

    func testPlanIsBlockedByAnUnknownNonDowngradableRecord() {
        let records = [record("future-1"), record("future-2", downgradable: false)]
        guard case let .blocked(blocking) = DataMigrations.plan(records: records, registry: [migration("a")]) else {
            return XCTFail("expected .blocked")
        }
        XCTAssertEqual(blocking.map(\.id), ["future-2"])
    }

    func testAKnownNonDowngradableRecordDoesNotBlock() {
        let registry = [migration("a", downgradable: false)]
        guard case let .run(pending) = DataMigrations.plan(records: [record("a", downgradable: false)], registry: registry)
        else {
            return XCTFail("expected .run")
        }
        XCTAssertTrue(pending.isEmpty)
    }

    // MARK: - starts

    @MainActor func testFreshInstallRunsAllAndRecordsThem() async throws {
        try await migrations([migration("a"), migration("b", downgradable: false)]).runMigrations()

        XCTAssertEqual(runs.all, ["a", "b"])
        let records = try store.load()
        XCTAssertEqual(records.map(\.id), ["a", "b"])
        XCTAssertEqual(records.map(\.description), ["description of a", "description of b"])
        XCTAssertEqual(records.map(\.downgradeInfo), ["check a", "check b"])
        XCTAssertEqual(records.map(\.downgradable), [true, false])
        XCTAssertEqual(records.map(\.appVersion), ["1.2 (3)", "1.2 (3)"])
        XCTAssertLessThan(abs(try XCTUnwrap(records.first).appliedAt.timeIntervalSinceNow), 60)
    }

    @MainActor func testSecondStartRunsNothing() async throws {
        let registry = [migration("a"), migration("b")]
        try await migrations(registry).runMigrations()
        let recorded = try store.load()

        try await migrations(registry).runMigrations()

        XCTAssertEqual(runs.all, ["a", "b"])
        XCTAssertEqual(try store.load(), recorded)
    }

    @MainActor func testANewMigrationRunsAlone() async throws {
        try await migrations([migration("a")]).runMigrations()
        try await migrations([migration("a"), migration("b")]).runMigrations()

        XCTAssertEqual(runs.all, ["a", "b"])
        XCTAssertEqual(try store.load().map(\.id), ["a", "b"])
    }

    @MainActor func testAFailingMigrationIsNotRecordedAndStopsTheStart() async throws {
        let registry = [migration("a"), migration("b", fails: true), migration("c")]
        do {
            try await migrations(registry).runMigrations()
            XCTFail("expected the start to fail")
        } catch let DataMigrationsError.migrationFailed(id, description, error) {
            XCTAssertEqual(id, "b")
            XCTAssertEqual(description, "description of b")
            XCTAssertTrue(error is Failure)
        }

        XCTAssertEqual(runs.all, ["a"])
        XCTAssertEqual(try store.load().map(\.id), ["a"])
    }

    @MainActor func testTheOldDataVersionIsIgnoredAndRemoved() async throws {
        defaults.set(5, forKey: DataMigrations.legacyDataVersionKey)

        try await migrations([migration("a")]).runMigrations()

        XCTAssertEqual(runs.all, ["a"])
        XCTAssertNil(defaults.object(forKey: DataMigrations.legacyDataVersionKey))
    }

    // MARK: - downgrade

    @MainActor func testUnknownDowngradableRecordWarnsAndNothingRunsBeforeTheAcknowledgement() async throws {
        let stored = [record("a"), record("future")]
        try store.save(stored)
        defaults.set(1, forKey: DataMigrations.legacyDataVersionKey)
        let migrations = migrations([migration("a"), migration("b")])

        let start = try await startUntilWarning(migrations)

        XCTAssertEqual(migrations.downgradeWarning, [record("future")])
        XCTAssertTrue(runs.all.isEmpty)
        XCTAssertEqual(try store.load(), stored)
        XCTAssertNotNil(defaults.object(forKey: DataMigrations.legacyDataVersionKey))

        migrations.acknowledgeDowngrade()
        try await start.value
    }

    @MainActor func testAcknowledgementRemovesTheUnknownRecordsKeepsTheKnownAndRunsThePending() async throws {
        try store.save([record("future-1"), record("a"), record("future-2")])
        let migrations = migrations([migration("a"), migration("b")])

        let start = try await startUntilWarning(migrations)
        migrations.acknowledgeDowngrade()
        migrations.acknowledgeDowngrade() // a second tap does nothing
        try await start.value

        XCTAssertNil(migrations.downgradeWarning)
        XCTAssertEqual(runs.all, ["b"])
        let records = try store.load()
        XCTAssertEqual(records.map(\.id), ["a", "b"])
        XCTAssertEqual(records.first, record("a"))
    }

    @MainActor func testUnknownNonDowngradableRecordBlocksAndCannotBeAcknowledged() async throws {
        let stored = [record("a"), record("future-1"), record("future-2", downgradable: false)]
        try store.save(stored)
        let migrations = migrations([migration("a"), migration("b")])

        do {
            try await migrations.runMigrations()
            XCTFail("expected the start to be blocked")
        } catch let DataMigrationsError.dataIsNewer(blocking) {
            XCTAssertEqual(blocking, [record("future-2", downgradable: false)])
        }

        XCTAssertNil(migrations.downgradeWarning)
        migrations.acknowledgeDowngrade()
        XCTAssertTrue(runs.all.isEmpty)
        XCTAssertEqual(try store.load(), stored)
    }

    @MainActor func testUpgradingAgainAfterAnAcknowledgedDowngradeRunsTheMigrationAgain() async throws {
        let newer = [migration("a"), migration("b")]
        try await migrations(newer).runMigrations()

        // the older build: no "b"
        let older = migrations([migration("a")])
        let start = try await startUntilWarning(older)
        XCTAssertEqual(older.downgradeWarning?.map(\.id), ["b"])
        older.acknowledgeDowngrade()
        try await start.value
        XCTAssertEqual(try store.load().map(\.id), ["a"])

        try await migrations(newer).runMigrations()

        XCTAssertEqual(runs.all, ["a", "b", "b"])
        XCTAssertEqual(try store.load().map(\.id), ["a", "b"])
    }

    // MARK: - the records

    func testRecordsRoundTripThroughUserDefaults() throws {
        XCTAssertEqual(try store.load(), [])

        let records = [
            record("a"),
            DataMigrationRecord(
                id: "b",
                description: "Préférences › \"b\"",
                downgradeInfo: "check b",
                downgradable: false,
                appliedAt: Date(timeIntervalSince1970: 1_700_000_123.456),
                appVersion: "5.7.1 (42)"
            )
        ]
        try store.save(records)

        let reopened = DataMigrationRecordStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        XCTAssertEqual(try reopened.load(), records)
    }

    func testARecordWithFieldsOfANewerBuildStillDecodes() throws {
        let json =
            #"[{"id":"future","description":"d","downgradable":true,"appliedAt":700000000,"appVersion":"9 (1)","somethingNew":[1,2]}]"#
        defaults.set(Data(json.utf8), forKey: DataMigrationRecordStore.key)

        let records = try store.load()
        XCTAssertEqual(records.map(\.id), ["future"])
        XCTAssertNil(records.first?.downgradeInfo)
    }

    @MainActor func testUnreadableRecordsStopTheStartAndNothingRuns() async throws {
        defaults.set(Data("not json".utf8), forKey: DataMigrationRecordStore.key)

        do {
            try await migrations([migration("a")]).runMigrations()
            XCTFail("expected the start to fail")
        } catch DataMigrationsError.recordsUnreadable {}

        XCTAssertTrue(runs.all.isEmpty)
        XCTAssertEqual(defaults.data(forKey: DataMigrationRecordStore.key), Data("not json".utf8))
    }

    // MARK: - this build's registry

    @MainActor func testBuiltInRegistryIDsAreUniqueAndStartWithThePreferencesKey() {
        let registry = DataMigrations(defaults: defaults).builtInRegistry
        XCTAssertEqual(registry.first?.id, "preferences-resistance-key")
        XCTAssertEqual(Set(registry.map(\.id)).count, registry.count)
        XCTAssertTrue(registry.allSatisfy { !$0.description.isEmpty })
    }
}
