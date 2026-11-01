@testable import FreeAPS
import XCTest

final class TempTargetHBTTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(minutes: Double) -> Date {
        t0.addingTimeInterval(minutes * 60)
    }

    private func target(id: String, start: Double, duration: Decimal, low: Decimal = 120) -> TempTarget {
        TempTarget(
            id: id,
            name: TempTarget.custom,
            createdAt: at(minutes: start),
            targetTop: low,
            targetBottom: low,
            duration: duration,
            enteredBy: TempTarget.manual,
            reason: TempTarget.custom
        )
    }

    private func cancel(start: Double) -> TempTarget {
        TempTarget.cancel(at: at(minutes: start))
    }

    private func row(
        id: String?,
        active: Bool = true,
        start: Double,
        duration: Decimal,
        hbt: Double = 130
    ) -> TempTargetsSnapshot {
        TempTargetsSnapshot(
            id: id,
            date: at(minutes: start),
            startDate: at(minutes: start),
            active: active,
            duration: duration,
            hbt: hbt
        )
    }

    /// The whole decision, as dynamicVariables makes it: active target from the history, then its row.
    private func hbt(history: [TempTarget], row: TempTargetsSnapshot?, now: Double) -> Double? {
        let now = at(minutes: now)
        let active = TempTargetHBT.activeTarget(in: history, at: now)
        return TempTargetHBT.halfBasalTarget(row: row, activeTarget: active, at: now)
    }

    // MARK: - HBT row matching

    func testMatchingRowOfTheActiveTargetApplies() {
        let a = target(id: "A", start: 0, duration: 60)
        XCTAssertEqual(hbt(history: [a], row: row(id: "A", start: 0, duration: 60), now: 30), 130)
    }

    func testRowOfAReplacedTargetDoesNotApply() {
        // a % target A, replaced by B from the Watch or Nightscout (no row of its own)
        let a = target(id: "A", start: 0, duration: 60)
        let b = target(id: "B", start: 10, duration: 60)
        let history = [b, cancel(start: 10 - 1.0 / 60), a]
        XCTAssertEqual(TempTargetHBT.activeTarget(in: history, at: at(minutes: 20))?.id, "B")
        XCTAssertNil(hbt(history: history, row: row(id: "A", start: 0, duration: 60), now: 20))
    }

    func testExpiredRowDoesNotApply() {
        // the target still runs, its row's duration is over
        let a = target(id: "A", start: 0, duration: 120)
        XCTAssertNil(hbt(history: [a], row: row(id: "A", start: 0, duration: 60), now: 61))
        XCTAssertEqual(hbt(history: [a], row: row(id: "A", start: 0, duration: 60), now: 59), 130)
    }

    func testRowDoesNotApplyAfterItsTargetEnded() {
        let a = target(id: "A", start: 0, duration: 60)
        XCTAssertNil(hbt(history: [a], row: row(id: "A", start: 0, duration: 120), now: 61))
    }

    func testRowDoesNotApplyBeforeItsTargetStarts() {
        // a future dated % target: the row is written at enact, it applies once the target runs
        let a = target(id: "A", start: 30, duration: 60)
        let r = row(id: "A", start: 30, duration: 60)
        XCTAssertNil(hbt(history: [a], row: r, now: 10))
        XCTAssertEqual(hbt(history: [a], row: r, now: 40), 130)
    }

    func testInactiveRowDoesNotApply() {
        // a plain (non %) target writes an inactive row with its id
        let a = target(id: "A", start: 0, duration: 60)
        XCTAssertNil(hbt(history: [a], row: row(id: "A", active: false, start: 0, duration: 60), now: 30))
    }

    func testCancelledTargetDoesNotApply() {
        let a = target(id: "A", start: 0, duration: 60)
        let history = [cancel(start: 20), a]
        XCTAssertNil(TempTargetHBT.activeTarget(in: history, at: at(minutes: 30)))
        XCTAssertNil(hbt(history: history, row: row(id: "A", start: 0, duration: 60), now: 30))
        // the cancel's own row
        let cancelRow = row(id: history[0].id, active: false, start: 20, duration: 0)
        XCTAssertNil(hbt(history: history, row: cancelRow, now: 30))
    }

    func testNoRowDoesNotApply() {
        let a = target(id: "A", start: 0, duration: 60)
        XCTAssertNil(hbt(history: [a], row: nil, now: 30))
    }

    func testNoTargetDoesNotApply() {
        XCTAssertNil(hbt(history: [], row: row(id: "A", start: 0, duration: 60), now: 30))
    }

    func testRowsFromBeforeTheChangeDoNotApply() {
        // custom % targets wrote a random id, preset ones none
        let a = target(id: "A", start: 0, duration: 60)
        XCTAssertNil(hbt(history: [a], row: row(id: UUID().uuidString, start: 0, duration: 60), now: 30))
        XCTAssertNil(hbt(history: [a], row: row(id: nil, start: 0, duration: 60), now: 30))
    }

    // MARK: - active target (oref0 targets.js)

    func testFutureTargetIsSkipped() {
        let a = target(id: "A", start: 0, duration: 60)
        let b = target(id: "B", start: 30, duration: 60)
        XCTAssertEqual(TempTargetHBT.activeTarget(in: [b, a], at: at(minutes: 10))?.id, "A")
        XCTAssertEqual(TempTargetHBT.activeTarget(in: [b, a], at: at(minutes: 40))?.id, "B")
    }

    func testOlderRunningTargetAfterAnExpiredNewerOne() {
        let a = target(id: "A", start: 0, duration: 120)
        let b = target(id: "B", start: 10, duration: 20)
        XCTAssertEqual(TempTargetHBT.activeTarget(in: [b, a], at: at(minutes: 40))?.id, "A")
    }

    private func invalidTarget(id: String, start: Double, bottom: Decimal?, top: Decimal?) -> TempTarget {
        TempTarget(
            id: id,
            name: TempTarget.custom,
            createdAt: at(minutes: start),
            targetTop: top,
            targetBottom: bottom,
            duration: 60,
            enteredBy: TempTarget.manual,
            reason: TempTarget.custom
        )
    }

    func testInvalidRangeStopsTheWalk() {
        // a newer running target with nil or 0 bounds: oref falls back to the profile target, not to A
        let a = target(id: "A", start: 0, duration: 120)
        for (bottom, top) in [(nil, 120), (120, nil), (0, 120), (120, 0)] as [(Decimal?, Decimal?)] {
            let bad = invalidTarget(id: "X", start: 10, bottom: bottom, top: top)
            XCTAssertNil(
                TempTargetHBT.activeTarget(in: [bad, a], at: at(minutes: 20)),
                "\(String(describing: bottom))-\(String(describing: top))"
            )
        }
        XCTAssertNil(hbt(
            history: [invalidTarget(id: "X", start: 10, bottom: nil, top: nil), a],
            row: row(id: "A", start: 0, duration: 120),
            now: 20
        ))
    }

    func testFutureInvalidRangeStopsTheWalkToo() {
        // targets.js checks the range before the start time
        let a = target(id: "A", start: 0, duration: 120)
        let bad = invalidTarget(id: "X", start: 30, bottom: 0, top: 0)
        XCTAssertNil(TempTargetHBT.activeTarget(in: [bad, a], at: at(minutes: 10)))
        let badNil = invalidTarget(id: "Y", start: 30, bottom: nil, top: 120)
        XCTAssertNil(TempTargetHBT.activeTarget(in: [badNil, a], at: at(minutes: 10)))
    }

    func testHistoryOrderDoesNotMatter() {
        let a = target(id: "A", start: 0, duration: 60)
        let b = target(id: "B", start: 10, duration: 60)
        XCTAssertEqual(TempTargetHBT.activeTarget(in: [a, b], at: at(minutes: 20))?.id, "B")
    }

    // MARK: - end date (fractional minutes)

    func testEndDateKeepsFractionalMinutes() {
        let a = target(id: "A", start: 0, duration: 30.5)
        XCTAssertEqual(a.endDate, t0.addingTimeInterval(30 * 60 + 30))
    }

    func testFractionalTargetRunsItsLastHalfMinute() {
        let a = target(id: "A", start: 0, duration: 30.5)
        XCTAssertTrue(a.isActive(at: at(minutes: 30 + 20.0 / 60)))
        XCTAssertFalse(a.isActive(at: at(minutes: 30 + 40.0 / 60)))
        // the oref walk was fractional already, now through endDate
        XCTAssertEqual(TempTargetHBT.activeTarget(in: [a], at: at(minutes: 30 + 20.0 / 60))?.id, "A")
        XCTAssertNil(TempTargetHBT.activeTarget(in: [a], at: at(minutes: 30 + 40.0 / 60)))
    }

    func testHalfMinuteTargetIsActiveForItsThirtySeconds() {
        let a = target(id: "A", start: 0, duration: 0.5)
        XCTAssertTrue(a.isActive(at: t0))
        XCTAssertTrue(a.isActive(at: t0.addingTimeInterval(29)))
        XCTAssertFalse(a.isActive(at: t0.addingTimeInterval(30)))
        XCTAssertFalse(a.isActive(at: t0.addingTimeInterval(-1)))
    }

    // MARK: - identical (Home header, Data table)

    func testIdenticalSeesADurationEditThatEqualityDoesNot() {
        // Nightscout edit: same created_at, new duration
        let a = target(id: "A", start: 0, duration: 60)
        let edited = target(id: "A", start: 0, duration: 90)
        XCTAssertEqual(a, edited)
        XCTAssertFalse(a.isIdentical(to: edited))
        XCTAssertFalse(TempTarget.identical(a, edited))
        XCTAssertFalse(TempTarget.identical([a], [edited]))
        XCTAssertTrue(TempTarget.identical([a], [target(id: "A", start: 0, duration: 60)]))
        XCTAssertTrue(TempTarget.identical(nil as TempTarget?, nil))
        XCTAssertFalse(TempTarget.identical(a, nil))
    }
}

// MARK: - storage

/// BaseFileStorage under per-test file names, so the tests never touch the app's own files.
private struct IsolatedFileStorage: FileStorage {
    let base = BaseFileStorage()
    let prefix = "test-temptargets-\(UUID().uuidString)-"

    func file(_ name: String) -> String {
        prefix + name.replacingOccurrences(of: "/", with: "-")
    }

    func save<Value: Encodable & Sendable>(_ value: Value, as name: String) async {
        await base.save(value, as: file(name))
    }

    func save<Value: Decodable & Sendable>(raw: RawJSON, as name: String, decodingInto type: Value.Type) async throws {
        try await base.save(raw: raw, as: file(name), decodingInto: type)
    }

    func retrieve<Value: Decodable & Sendable>(_ name: String, as type: Value.Type) async -> Value? {
        await base.retrieve(file(name), as: type)
    }

    func retrieveRaw(_ name: String) async -> String? {
        await base.retrieveRaw(file(name))
    }

    func append<Value: JSON>(_ newValue: Value, to name: String) async -> [Value]? {
        await base.append(newValue, to: file(name))
    }

    func append<Value: JSON>(_ newValues: [Value], to name: String) async -> [Value]? {
        await base.append(newValues, to: file(name))
    }

    func append<Value: JSON, T: Equatable & Sendable>(
        _ newValue: Value,
        to name: String,
        uniqBy keyPath: KeyPath<Value, T> & Sendable
    ) async -> [Value]? {
        await base.append(newValue, to: file(name), uniqBy: keyPath)
    }

    func append<Value: JSON, T: Equatable & Sendable>(
        _ newValues: [Value],
        to name: String,
        uniqBy keyPath: KeyPath<Value, T> & Sendable
    ) async -> [Value]? {
        await base.append(newValues, to: file(name), uniqBy: keyPath)
    }

    func append<Value: JSON, T: Equatable & Sendable>(
        _ newValues: [Value],
        to name: String,
        uniqByProj proj: @Sendable(Value) -> T
    ) async -> [Value]? {
        await base.append(newValues, to: file(name), uniqByProj: proj)
    }

    func appendAndModify<Value: JSON, T: Equatable & Sendable>(
        _ newValues: [Value],
        to name: String,
        uniqBy keyPath: KeyPath<Value, T> & Sendable,
        _ modify: @Sendable([Value]) -> [Value]
    ) async -> [Value] {
        await base.appendAndModify(newValues, to: file(name), uniqBy: keyPath, modify)
    }

    func modify<Value: JSON>(file name: String, as type: Value.Type, _ modify: @Sendable([Value]) -> [Value]) async -> [Value] {
        await base.modify(file: file(name), as: type, modify)
    }

    func delete<Value: JSON>(
        file name: String,
        as type: Value.Type,
        where shouldDelete: @Sendable(Value) -> Bool
    ) async -> (kept: [Value], deleted: [Value]?) {
        await base.delete(file: file(name), as: type, where: shouldDelete)
    }

    func maybeModify<Value: JSON>(
        file name: String,
        as type: Value.Type,
        _ modify: @Sendable([Value]) -> [Value]?
    ) async -> (Bool, [Value]) {
        await base.maybeModify(file: file(name), as: type, modify)
    }

    func maybeModifyWithData<Value: JSON, Data: Sendable>(
        file name: String,
        as type: Value.Type,
        _ modify: @Sendable([Value]) -> ([Value], data: Data)?
    ) async -> (Bool, [Value], data: Data?) {
        await base.maybeModifyWithData(file: file(name), as: type, modify)
    }

    func remove(_ name: String) async {
        await base.remove(file(name))
    }

    func rename(_ name: String, to newName: String) async {
        await base.rename(file(name), to: file(newName))
    }

    func urlFor(file name: String) async -> URL? {
        await base.urlFor(file: file(name))
    }
}

final class TempTargetsStorageTests: XCTestCase {
    private let files = IsolatedFileStorage()
    private let appCoordinator = AppCoordinator()

    /// whole seconds: the file round trip keeps them exactly, so `uniqBy: \.createdAt` matches
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))

    override func tearDown() async throws {
        await files.remove(OpenAPS.Settings.tempTargets)
    }

    private func target(id: String, minutesAgo: Double, duration: Decimal) -> TempTarget {
        TempTarget(
            id: id,
            name: TempTarget.custom,
            createdAt: now.subtractingTimeInterval(.minutes(minutesAgo)),
            targetTop: 120,
            targetBottom: 120,
            duration: duration,
            enteredBy: "Nightscout",
            reason: TempTarget.custom
        )
    }

    private func makeStorage() -> BaseTempTargetsStorage {
        BaseTempTargetsStorage(storage: files, appCoordinator: appCoordinator)
    }

    func testRunningTargetStoredAgainAddsNoCancel() async {
        let storage = makeStorage()
        // the Nightscout poll stores the running target every minute
        let a = target(id: "A", minutesAgo: 10, duration: 60)
        await storage.storeTempTargets([a])
        await storage.storeTempTargets([a])
        let afterSecond = appCoordinator.tempTargets.value
        XCTAssertEqual(afterSecond.map(\.id), ["A"])
        await storage.storeTempTargets([a])
        XCTAssertTrue(TempTarget.identical(appCoordinator.tempTargets.value, afterSecond))
    }

    func testNewTargetCancelsTheRunningOne() async {
        let storage = makeStorage()
        let a = target(id: "A", minutesAgo: 10, duration: 60)
        let b = target(id: "B", minutesAgo: 1, duration: 60)
        await storage.storeTempTargets([a])
        await storage.storeTempTargets([b])
        let history = appCoordinator.tempTargets.value
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history.first?.id, "B")
        XCTAssertEqual(history[1].duration, 0)
        XCTAssertEqual(history[1].createdAt, b.createdAt.addingTimeInterval(-1))
        XCTAssertEqual(history.last?.id, "A")
    }

    func testEditedDurationReplacesTheRunningTarget() async {
        let storage = makeStorage()
        // an edit in Nightscout keeps created_at
        await storage.storeTempTargets([target(id: "A", minutesAgo: 10, duration: 60)])
        await storage.storeTempTargets([target(id: "A", minutesAgo: 10, duration: 90)])
        let history = appCoordinator.tempTargets.value
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.duration, 90)
        let current = await storage.current()
        XCTAssertEqual(current?.duration, 90)
    }
}
