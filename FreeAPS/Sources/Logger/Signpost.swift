import Foundation
import MetricKit
import os.signpost

enum Signpost {
    private static let poiSignposter = OSSignposter(
        logHandle: OSLog(subsystem: Bundle.main.bundleIdentifier ?? "iAPS", category: .pointsOfInterest)
    )

    private static let metricsSignposter = OSSignposter(
        logHandle: MXMetricManager.makeLogHandle(category: "Performance")
    )

    private static func signposter(poi: Bool) -> OSSignposter {
        poi ? poiSignposter : metricsSignposter
    }

    static func event(_ name: StaticString, poi: Bool = false, _ message: @autoclosure () -> String = "") {
        guard Config.withSignPosts else { return }
        let message = message()
        signposter(poi: poi).emitEvent(name, "\(message, privacy: .public)")
    }

    /// A begin/end interval; safe to carry across awaits and actors.
    /// `end()` must be called exactly once (extra calls are ignored by os_signpost as mismatches).
    struct Span: @unchecked Sendable {
        fileprivate let name: StaticString
        fileprivate let signposter: OSSignposter?
        fileprivate let state: OSSignpostIntervalState?

        func end(_ message: @autoclosure () -> String = "") {
            guard let signposter, let state else { return }
            let message = message()
            signposter.endInterval(name, state, "\(message, privacy: .public)")
        }
    }

    static func begin(_ name: StaticString, poi: Bool = false, _ message: @autoclosure () -> String = "") -> Span {
        guard Config.withSignPosts else { return Span(name: name, signposter: nil, state: nil) }
        let signposter = signposter(poi: poi)
        let message = message()
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID(), "\(message, privacy: .public)")
        return Span(name: name, signposter: signposter, state: state)
    }

    static func measure<T>(
        _ name: StaticString,
        poi: Bool = false,
        _ message: @autoclosure () -> String = "",
        _ body: () throws -> T
    ) rethrows -> T {
        let span = begin(name, poi: poi, message())
        defer { span.end() }
        return try body()
    }

    static func measure<T>(
        _ name: StaticString,
        poi: Bool = false,
        _ message: @autoclosure @Sendable() -> String = "",
        _ body: @Sendable() async throws -> T
    ) async rethrows -> T {
        let span = begin(name, poi: poi, message())
        defer { span.end() }
        return try await body()
    }
}
