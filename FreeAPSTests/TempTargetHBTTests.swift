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
}
