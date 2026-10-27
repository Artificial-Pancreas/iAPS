import Foundation
import UIKit

final class NightscoutUploadContext: Sendable {
    let apiProvider: NightscoutAPIProvider
    let appCoordinator: AppCoordinator
    let reachabilityManager: ReachabilityManager
    let storage: FileStorage
    let burst = NightscoutUploadBurst()

    init(
        apiProvider: NightscoutAPIProvider,
        appCoordinator: AppCoordinator,
        reachabilityManager: ReachabilityManager,
        storage: FileStorage
    ) {
        self.apiProvider = apiProvider
        self.appCoordinator = appCoordinator
        self.reachabilityManager = reachabilityManager
        self.storage = storage
    }

    func canUpload() -> Bool {
        guard appCoordinator.settings.value.isUploadEnabled,
              !NightscoutUploadPause.isPaused,
              reachabilityManager.isReachable
        else { return false }
        return apiProvider.api != nil
    }

    func makeGate(name: String, group: UploadScheduleGroup) -> UploadScheduleGate {
        UploadScheduleGate(
            name: name,
            group: group,
            appCoordinator: appCoordinator,
            reachabilityManager: reachabilityManager
        )
    }
}

enum NightscoutUploadPause {
    private static let pausedUntilKey = "nightscoutUpload.pausedUntil"

    static var pausedUntil: Date? {
        get { UserDefaults.standard.object(forKey: pausedUntilKey) as? Date }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: pausedUntilKey)
                return
            }
            UserDefaults.standard.set(newValue, forKey: pausedUntilKey)
        }
    }

    static var isPaused: Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > Date()
    }
}

final class UploadScheduleGate: Sendable {
    private let name: String
    private let group: UploadScheduleGroup
    private let appCoordinator: AppCoordinator
    private let reachabilityManager: ReachabilityManager

    init(
        name: String,
        group: UploadScheduleGroup,
        appCoordinator: AppCoordinator,
        reachabilityManager: ReachabilityManager
    ) {
        self.name = name
        self.group = group
        self.appCoordinator = appCoordinator
        self.reachabilityManager = reachabilityManager
    }

    /// about one loop interval: uploaders whose anchors drifted apart still go out in the same burst
    static let slack: TimeInterval = .minutes(5)

    func allows() async -> Bool {
        guard let network = currentNetworkSchedule() else {
            return true
        }
        switch network.interval {
        case .always:
            return true
        case .every12Hours,
             .everyHour,
             .never:
            if network.alwaysWhileCharging, await isCharging() {
                return true
            }
            guard let interval = network.interval.timeInterval else { return false }
            return Self.isDue(lastUpload: lastUpload, interval: interval, now: Date.now)
        }
    }

    static func isDue(lastUpload: Date?, interval: TimeInterval, now: Date) -> Bool {
        now.timeIntervalSince(lastUpload ?? .distantPast) >= interval - slack
    }

    var lastUpload: Date? {
        Self.lastUpload(named: name)
    }

    /// - Parameter date: the burst's start: the entities of one burst share the anchor, so hourly ones stay together
    func recordUpload(at date: Date) {
        UserDefaults.standard.set(date, forKey: Self.lastUploadKey(name))
    }

    static func lastUpload(named name: String) -> Date? {
        UserDefaults.standard.object(forKey: lastUploadKey(name)) as? Date
    }

    private static func lastUploadKey(_ name: String) -> String {
        "nightscoutUpload.lastUpload.\(name)"
    }

    private func currentNetworkSchedule() -> UploadNetworkSchedule? {
        let schedule = appCoordinator.settings.value[keyPath: group.scheduleKeyPath]
        switch reachabilityManager.status {
        case .reachable(.ethernetOrWiFi): return schedule.onWifi
        case .reachable(.cellular): return schedule.onCellular
        case .notReachable,
             .unknown: return nil
        }
    }

    private func isCharging() async -> Bool {
        let batteryState = await MainActor.run { UIDevice.current.batteryState }
        return batteryState == .charging || batteryState == .full
    }
}

/// An upload entity: changes only mark its work pending, `NightscoutUploadBurst` sends it.
protocol NightscoutUploadEntity: AppService {
    /// uploads the pending work, when the entity's schedule allows
    /// - Parameter startedAt: when the burst started; recorded as the upload time
    func flush(startedAt: Date) async
}

/// Sends all Nightscout uploads together - one burst per loop instead of one request per change,
/// so the radio wakes up once per loop.
/// Bursts may overlap (a slow one never holds up the next): each entity serializes its own flushes.
actor NightscoutUploadBurst: LifetimeOwner {
    let lifetime = Lifetime()

    private typealias Schedule = NightscoutUploadBurstSchedule

    private var entities: [any NightscoutUploadEntity] = []
    // monotonic: a wall clock change can't hold bursts back
    private let clock = ContinuousClock()
    private var schedule = NightscoutUploadBurstSchedule(now: ContinuousClock.now)
    /// sleeps until the pending burst is due; nil once it fired
    private var timer: Task<Void, Never>?

    func start(entities: [any NightscoutUploadEntity]) {
        self.entities = entities
        schedule = Schedule(now: clock.now)

        // Independent of the loop and of the burst timer: covers no CGM, skipped loops, and a timer that
        // didn't run (suspended app). A sleep that ends while suspended runs as soon as the app wakes up.
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Schedule.watchdogCheckInterval)
                guard let self else { return }
                await self.watchdogTick()
            }
        }.store(in: lifetime)

        // work left pending by the previous run
        request(.immediate)
    }

    /// a loop completed, its outcome is queued
    func loopCompleted() {
        request(.routine)
    }

    /// a change followers should see now (user entries, a manual bolus, pump suspend/resume); everything rides along
    func requestImmediate() {
        request(.immediate)
    }

    private func request(_ kind: Schedule.Kind) {
        guard let fireAt = schedule.request(kind, now: clock.now) else { return }
        timer?.cancel()
        let keepAwake = clock.now.duration(to: fireAt) <= Schedule.maxDelay
        timer = Task { [weak self, clock] in
            if !keepAwake {
                // a deferred loop: not worth keeping the app awake for; a suspended app fires it on wake-up
                try? await Task.sleep(until: fireAt, clock: clock)
                guard !Task.isCancelled else { return }
            }
            await withBackgroundTask("nightscout upload burst") {
                try? await Task.sleep(until: fireAt, clock: clock)
                guard !Task.isCancelled else { return }
                // waits for the burst: keeps the app awake until the burst's own background task is running
                await self?.fireIfDue()?.value
            }
        }
    }

    private func watchdogTick() {
        if schedule.isWatchdogDue(now: clock.now) {
            debug(.nightscout, "upload burst: watchdog")
            request(.watchdog)
        }
        // also fires a pending burst whose timer didn't run; never waits for it
        fireIfDue()
    }

    /// - Returns: the burst started, if one was due
    @discardableResult private func fireIfDue() -> Task<Void, Never>? {
        guard let kind = schedule.fire(now: clock.now) else { return nil }
        // the burst runs in its own task: re-arming the timer for the next request must not cancel it
        timer = nil
        let entities = entities
        let startedAt = Date.now
        return Task {
            await withBackgroundTask("nightscout upload burst") {
                debug(.nightscout, "upload burst: \(kind)")
                await withTaskGroup(of: Void.self) { group in
                    for entity in entities {
                        group.addTask { await entity.flush(startedAt: startedAt) }
                    }
                }
            }
        }
    }
}

/// When the upload bursts run - the decisions of `NightscoutUploadBurst`, with the (monotonic) clock passed in.
struct NightscoutUploadBurstSchedule: Sendable {
    typealias Instant = ContinuousClock.Instant

    enum Kind: Equatable, Sendable {
        /// a loop completed
        case routine
        /// a change followers should see now
        case immediate
        /// no burst for a while
        case watchdog
    }

    /// lets the loop's stragglers (the pump events of its temp basal, its IOB tick) ride along
    static let routineDelay: Duration = .seconds(2)
    /// gathers the events of the change (a bolus: pump history, pump status, IOB)
    static let immediateDelay: Duration = .seconds(3)
    /// later requests postpone a pending burst, up to this long after the first one
    static let maxDelay: Duration = .seconds(10)
    /// 1-minute loops: a loop this soon after the last routine burst is deferred to the end of the interval
    /// (a 5-minute loop that ends a little early only waits the difference)
    static let routineMinInterval: Duration = .seconds(5 * 60)
    static let watchdogInterval: Duration = .seconds(10 * 60)
    static let watchdogCheckInterval: Duration = .seconds(60)
    /// no burst is ever scheduled further ahead; one that is (an instant from a clock that went back) is due
    static let maxLead: Duration = routineMinInterval + maxDelay

    private struct Pending: Sendable {
        var kind: Kind
        let requestedAt: Instant
        var fireAt: Instant
        /// a routine request held back by the minimum interval
        let deferred: Bool
    }

    private var pending: Pending?
    private var lastBurst: Instant
    private var lastRoutineBurst: Instant?

    init(now: Instant) {
        // the watchdog counts from the start
        lastBurst = now
    }

    /// - Returns: when the pending burst fires, if that's new; nil when there's nothing to (re)schedule
    mutating func request(_ kind: Kind, now: Instant) -> Instant? {
        if kind == .routine, let deferredTo = routineDeferral(now: now) {
            return deferRoutine(to: max(deferredTo, now + Self.routineDelay), now: now)
        }
        let fireAt = now + Self.delay(kind)
        guard var pending, !pending.deferred else {
            // a deferred routine burst rides along with this earlier one
            self.pending = Pending(kind: kind, requestedAt: now, fireAt: fireAt, deferred: false)
            return fireAt
        }
        pending.kind = Self.merged(pending.kind, kind)
        let newFireAt = min(max(pending.fireAt, fireAt), pending.requestedAt + Self.maxDelay)
        let changed = newFireAt != pending.fireAt
        pending.fireAt = newFireAt
        self.pending = pending
        return changed ? newFireAt : nil
    }

    /// - Returns: the kind of the burst to run now; nil when none is due
    mutating func fire(now: Instant) -> Kind? {
        guard let pending, now >= pending.fireAt || pending.fireAt - now > Self.maxLead else { return nil }
        self.pending = nil
        lastBurst = now
        if pending.kind == .routine {
            lastRoutineBurst = now
        }
        return pending.kind
    }

    func isWatchdogDue(now: Instant) -> Bool {
        // (a last burst "in the future" counts as long ago)
        now - lastBurst >= Self.watchdogInterval || lastBurst > now
    }

    /// the end of the minimum interval, when a routine burst now would come too soon
    private func routineDeferral(now: Instant) -> Instant? {
        guard let lastRoutineBurst, lastRoutineBurst <= now else { return nil }
        let due = lastRoutineBurst + Self.routineMinInterval
        return now < due ? due : nil
    }

    private mutating func deferRoutine(to fireAt: Instant, now: Instant) -> Instant? {
        guard let pending else {
            self.pending = Pending(kind: .routine, requestedAt: now, fireAt: fireAt, deferred: true)
            return fireAt
        }
        // an earlier burst carries the loop's work
        guard pending.deferred, fireAt > pending.fireAt else { return nil }
        self.pending?.fireAt = fireAt
        return fireAt
    }

    private static func delay(_ kind: Kind) -> Duration {
        switch kind {
        case .routine: return routineDelay
        case .immediate: return immediateDelay
        case .watchdog: return .zero
        }
    }

    /// a merged routine request still counts as the loop's burst
    private static func merged(_ lhs: Kind, _ rhs: Kind) -> Kind {
        if lhs == .routine || rhs == .routine { return .routine }
        if lhs == .immediate || rhs == .immediate { return .immediate }
        return .watchdog
    }
}
