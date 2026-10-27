@testable import FreeAPS
import XCTest

final class LiveActivityUpdateGateTests: XCTestCase {
    private typealias Gate = LiveActivityUpdateGate<Int>

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    private func pushed(_ state: Int, at seconds: TimeInterval) -> Gate {
        var gate = Gate()
        gate.didPush(state, at: at(seconds))
        return gate
    }

    func testFirstUpdatePushesForEitherTrigger() {
        var gate = Gate()
        XCTAssertEqual(gate.decide(1, trigger: .iob, now: t0), .push)
        XCTAssertEqual(gate.decide(1, trigger: .immediate, now: t0), .push)
    }

    func testEqualContentIsSkippedForEitherTrigger() {
        var gate = pushed(1, at: 0)
        XCTAssertEqual(gate.decide(1, trigger: .immediate, now: at(1)), .skip)
        XCTAssertEqual(gate.decide(1, trigger: .iob, now: at(600)), .skip)
    }

    func testImmediateIsNotThrottled() {
        var gate = pushed(1, at: 0)
        XCTAssertEqual(gate.decide(2, trigger: .immediate, now: at(1)), .push)
    }

    func testIOBWithinIntervalIsDeferredToTheIntervalEnd() {
        var gate = pushed(1, at: 0)
        XCTAssertEqual(gate.decide(2, trigger: .iob, now: at(10)), .deferred(until: at(Gate.iobInterval)))
    }

    func testIOBAfterIntervalIsDebounced() {
        var gate = pushed(1, at: 0)
        let now = Gate.iobInterval + 100
        XCTAssertEqual(gate.decide(2, trigger: .iob, now: at(now)), .deferred(until: at(now + Gate.iobDebounce)))
    }

    func testPendingDeadlineIsSharedByLaterTicks() {
        var gate = pushed(1, at: 0)
        let first = Gate.iobInterval + 100
        let deadline = at(first + Gate.iobDebounce)
        XCTAssertEqual(gate.decide(2, trigger: .iob, now: at(first)), .deferred(until: deadline))
        XCTAssertEqual(gate.decide(3, trigger: .iob, now: at(first + Gate.iobDebounce - 1)), .deferred(until: deadline))
        // overdue (the trailing update didn't run): push
        XCTAssertEqual(gate.decide(3, trigger: .iob, now: at(first + Gate.iobDebounce)), .push)
    }

    func testPushClearsTheDeferral() {
        var gate = pushed(1, at: 0)
        _ = gate.decide(2, trigger: .iob, now: at(10))
        gate.didPush(3, at: at(20))
        XCTAssertEqual(gate.decide(4, trigger: .iob, now: at(200)), .deferred(until: at(200 + Gate.iobDebounce)))
    }

    func testImmediateSkipClearsTheDeferral() {
        var gate = pushed(1, at: 0)
        XCTAssertEqual(gate.decide(2, trigger: .iob, now: at(10)), .deferred(until: at(Gate.iobInterval)))
        // the trailing update finds nothing new
        XCTAssertEqual(gate.decide(1, trigger: .immediate, now: at(Gate.iobInterval)), .skip)
        // a later tick is deferred afresh, not pushed against the old, passed deadline
        XCTAssertEqual(gate.decide(2, trigger: .iob, now: at(300)), .deferred(until: at(300 + Gate.iobDebounce)))
    }

    func testResetForgetsContentAndInterval() {
        var gate = pushed(1, at: 0)
        gate.reset()
        XCTAssertEqual(gate.decide(1, trigger: .iob, now: at(1)), .push)
    }
}
