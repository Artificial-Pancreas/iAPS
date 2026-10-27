import Foundation
import UIKit

/// One devicestatus per burst: the loop's outcome (`openaps.enacted|suggested`), with the current pump status,
/// phone battery and IOB on it. Each part behind its own schedule gate.
final actor NightscoutDeviceStatusUploader: LifetimeOwner, NightscoutUploadEntity {
    let lifetime = Lifetime()

    private let context: NightscoutUploadContext
    /// `openaps.enacted|suggested`
    private let loopGate: UploadScheduleGate
    /// `pump`, `uploader`, `openaps.iob`
    private let pumpGate: UploadScheduleGate
    private let version: String
    private let suggestedOutbox: UploadOutbox<Suggestion, Date?>
    private let enactedOutbox: UploadOutbox<Suggestion, Date?>
    /// bursts can overlap: one flush at a time, so the current values aren't posted twice at once
    private let flushSerializer = TaskSerializer()

    /// the last pump state seen: a change is posted right away, not with the next loop
    private var lastPumpState: PumpState?

    /// NS windows devicestatus by `created_at`: the current values ride on a queued loop doc only while it's this recent
    private static let attachWindow: TimeInterval = .minutes(10)

    private struct PumpState: Equatable {
        // not `isBolusing`: a bolus start/end alone isn't worth a post
        let isSuspended: Bool
        let statusHighlight: String?
    }

    private struct CurrentValues: Sendable {
        let pump: NSPumpStatus?
        let uploader: Uploader
        let iob: IOBEntry?
    }

    init(context: NightscoutUploadContext) {
        self.context = context
        loopGate = context.makeGate(name: "loopStatus", group: .treatmentsAndLoops)
        pumpGate = context.makeGate(name: "pumpStatus", group: .deviceStatus)

        let apiProvider = context.apiProvider
        let version = Bundle.main.releaseVersionNumber ?? "Unknown"
        self.version = version

        suggestedOutbox = UploadOutbox(
            file: OpenAPS.Upload.recentSuggested,
            retention: .hours(30),
            uniqueBy: \.timestamp,
            dateBy: \.timestamp,
            storage: context.storage,
            category: .nightscout,
            send: { suggested in
                try await Self.post(suggested: suggested, current: nil, version: version, apiProvider: apiProvider)
            }
        )
        enactedOutbox = UploadOutbox(
            file: OpenAPS.Upload.recentEnacted,
            retention: .hours(30),
            uniqueBy: \.timestamp,
            dateBy: \.timestamp,
            storage: context.storage,
            category: .nightscout,
            send: { enacted in
                try await Self.post(enacted: enacted, current: nil, version: version, apiProvider: apiProvider)
            }
        )
    }

    func start() async {
        observe(context.appCoordinator.loopCompleted) { me, outcome in
            await withBackgroundTask("nightscout upload - loop status") {
                await me.loopCompleted(outcome)
            }
        }

        observe(context.appCoordinator.pumpStatus) { me, pumpStatus in
            await me.pumpStatusUpdated(pumpStatus)
        }
    }

    private func loopCompleted(_ outcome: LoopOutcome) async {
        switch outcome {
        case let .enacted(suggestion, _):
            await enactedOutbox.enqueue([suggestion])
        case .enactFailed(var suggestion, let error, _):
            suggestion.reason = suggestion.reason + "\n\(error)"
            await enactedOutbox.enqueue([suggestion])
        case let .suggested(suggestion, _):
            await suggestedOutbox.enqueue([suggestion])
        case .failed:
            break
        }
        // queued first: the burst posts it
        await context.burst.loopCompleted()
    }

    private func pumpStatusUpdated(_ pumpStatus: PumpDisplayStatus?) async {
        guard let pumpStatus else { return }
        let state = PumpState(isSuspended: pumpStatus.isSuspended, statusHighlight: pumpStatus.statusHighlight)
        let previous = lastPumpState
        lastPumpState = state
        guard let previous, previous != state else { return }
        await context.burst.requestImmediate()
    }

    func flush(startedAt: Date) async {
        await flushSerializer.run {
            await self.performFlush(startedAt: startedAt)
        }
    }

    private func performFlush(startedAt: Date) async {
        guard context.canUpload() else { return }
        let current = await pumpGate.allows() ? await currentValues() : nil

        var loopSent = 0
        var currentSent = false
        // no response (the network is down): the rest would only time out. A rejected doc doesn't hold up the rest.
        var unreachable = false
        let stopWhen: @Sendable(Error) -> Bool = { error in
            if case NetworkError.badStatusCode = error { return false }
            return true
        }
        // the current values ride on the newest queued loop doc, when it's recent
        var attachTo: Date?

        if await loopGate.allows() {
            let queued = await suggestedOutbox.pending() + enactedOutbox.pending()
            if current != nil, let newest = queued.compactMap(\.timestamp).max(),
               Date.now.timeIntervalSince(newest) <= Self.attachWindow
            {
                attachTo = newest
            }

            let apiProvider = context.apiProvider
            let version = self.version
            let attachment = attachTo.flatMap { date in current.map { (date: date, values: $0) } }
            // oldest first, as queued
            let suggested = await suggestedOutbox.sendPending(using: { suggested in
                let values = attachment.flatMap { $0.date == suggested.timestamp ? $0.values : nil }
                try await Self.post(suggested: suggested, current: values, version: version, apiProvider: apiProvider)
            }, stopWhen: stopWhen)
            unreachable = suggested.stopped
            if !unreachable {
                let enacted = await enactedOutbox.sendPending(using: { enacted in
                    let values = attachment.flatMap { $0.date == enacted.timestamp ? $0.values : nil }
                    try await Self.post(enacted: enacted, current: values, version: version, apiProvider: apiProvider)
                }, stopWhen: stopWhen)
                unreachable = enacted.stopped
                loopSent += enacted.sent
            }
            loopSent += suggested.sent

            if let attachTo {
                // sent: no longer queued
                let stillQueued = await suggestedOutbox.pending() + enactedOutbox.pending()
                currentSent = !stillQueued.contains { $0.timestamp == attachTo }
            }
        }

        if let current, attachTo == nil, !unreachable {
            // no loop doc to ride on
            do {
                try await Self.post(current: current, version: version, apiProvider: context.apiProvider)
                currentSent = true
            } catch {
                debug(.nightscout, "failed to upload pump status: \(error.localizedDescription)")
            }
        }

        if loopSent > 0 {
            loopGate.recordUpload(at: startedAt)
        }
        if currentSent {
            pumpGate.recordUpload(at: startedAt)
            debug(.nightscout, "pump status uploaded")
        }
    }

    private func currentValues() async -> CurrentValues? {
        let pumpStatus = context.appCoordinator.pumpStatus.value
        let iob = context.appCoordinator.iobTicks.value?.first
        guard pumpStatus != nil || iob != nil else { return nil }

        let pump = pumpStatus.map { pumpStatus in
            NSPumpStatus(
                clock: pumpStatus.timestamp,
                battery: pumpStatus.battery,
                reservoir: pumpStatus.reservoir?.knownValue,
                status: NSPumpStatusDetails(
                    status: NSStatusType(rawValue: pumpStatus.status.rawValue) ?? .normal,
                    bolusing: pumpStatus.isBolusing,
                    suspended: pumpStatus.isSuspended,
                    timestamp: pumpStatus.timestamp
                )
            )
        }
        let batteryLevel = await MainActor.run { UIDevice.current.batteryLevel }
        return CurrentValues(
            pump: pump,
            uploader: Uploader(batteryVoltage: nil, battery: Int(batteryLevel * 100)),
            iob: iob
        )
    }

    private static func post(
        suggested: Suggestion,
        current: CurrentValues?,
        version: String,
        apiProvider: NightscoutAPIProvider
    ) async throws {
        guard let timestamp = suggested.timestamp else { return }
        try await post(
            NightscoutStatus(
                device: NigtscoutTreatment.local,
                openaps: OpenAPSStatus(iob: current?.iob, suggested: suggested, enacted: nil, version: version),
                pump: current?.pump,
                uploader: current?.uploader,
                createdAt: timestamp
            ),
            apiProvider: apiProvider
        )
    }

    private static func post(
        enacted: Suggestion,
        current: CurrentValues?,
        version: String,
        apiProvider: NightscoutAPIProvider
    ) async throws {
        guard let timestamp = enacted.timestamp else { return }
        // NS reports (Day to Day, Loopalyzer) read the predictions from `openaps.suggested` only
        try await post(
            NightscoutStatus(
                device: NigtscoutTreatment.local,
                openaps: OpenAPSStatus(iob: current?.iob, suggested: enacted, enacted: enacted, version: version),
                pump: current?.pump,
                uploader: current?.uploader,
                createdAt: timestamp
            ),
            apiProvider: apiProvider
        )
    }

    private static func post(current: CurrentValues, version: String, apiProvider: NightscoutAPIProvider) async throws {
        try await post(
            NightscoutStatus(
                device: NigtscoutTreatment.local,
                openaps: current.iob.map { OpenAPSStatus(iob: $0, suggested: nil, enacted: nil, version: version) },
                pump: current.pump,
                uploader: current.uploader,
                createdAt: Date.now
            ),
            apiProvider: apiProvider
        )
    }

    private static func post(_ status: NightscoutStatus, apiProvider: NightscoutAPIProvider) async throws {
        guard let nightscout = apiProvider.api else { throw DataSyncError.sinkUnavailable }
        try await nightscout.uploadStatus(status)
    }
}

final actor NightscoutOverridesUploader: NightscoutUploadEntity {
    private let context: NightscoutUploadContext
    private let gate: UploadScheduleGate
    private let outbox: UploadOutbox<NigtscoutExercise, Date>
    private let deletions: UploadOutbox<NightscoutOverrideDeletion, Date>
    private let flushSerializer = TaskSerializer()

    init(context: NightscoutUploadContext) {
        self.context = context
        gate = context.makeGate(name: "overrides", group: .treatmentsAndLoops)

        let apiProvider = context.apiProvider
        deletions = UploadOutbox(
            file: OpenAPS.Nightscout.notUploadedOverrideDeletions,
            retention: .days(2),
            uniqueBy: \.createdAt,
            dateBy: \.createdAt,
            storage: context.storage,
            category: .nightscout,
            send: { deletion in
                guard let nightscout = apiProvider.api else { throw DataSyncError.sinkUnavailable }
                try await nightscout.deleteOverride(at: deletion.createdAt)
            }
        )
        outbox = UploadOutbox(
            file: OpenAPS.Nightscout.notUploadedOverrides,
            retention: .days(2),
            uniqueBy: \.createdAt,
            dateBy: \.createdAt,
            storage: context.storage,
            category: .nightscout,
            send: { override in
                guard let nightscout = apiProvider.api else { throw DataSyncError.sinkUnavailable }
                // NS upserts treatments on created_at + eventType: this replaces an earlier upload of the same override
                try await nightscout.uploadEcercises([override])
            }
        )
    }

    func start() async {}

    func uploadOverride(_ profile: String, _ duration: Double, _ date: Date) async {
        // 0 = indefinite; a cancelled override's fractional duration is rounded up (never to 0)
        let duration = duration == 0 ? 2880 : max(1, Int(duration.rounded(.up)))

        let exercise = NigtscoutExercise(
            duration: duration,
            eventType: EventType.nsExercise,
            createdAt: date.truncatedToSecond,
            enteredBy: NigtscoutTreatment.local,
            notes: profile
        )

        // its upload replaces whatever is in NS at this second: a pending deletion there would delete it afterwards
        await deletions.discard([exercise.createdAt])
        await outbox.enqueue([exercise])
        await context.burst.requestImmediate()
    }

    /// Removes an override entry that was uploaded ahead of time (a scheduled successor that won't run as projected).
    func deleteOverride(at date: Date) async {
        let date = date.truncatedToSecond
        // not uploaded yet - nothing to delete in NS
        await outbox.discard([date])
        await deletions.enqueue([NightscoutOverrideDeletion(createdAt: date)])
        await context.burst.requestImmediate()
    }

    func flush(startedAt: Date) async {
        await flushSerializer.run {
            await self.performFlush(startedAt: startedAt)
        }
    }

    private func performFlush(startedAt: Date) async {
        guard context.canUpload(), await gate.allows() else { return }
        // A deletion only targets an entry uploaded earlier: a still-queued one is discarded instead, and a newer
        // upload at the same second discards the deletion - so a pending deletion and upload never share a date.
        let deleted = await deletions.sendPending()
        let uploaded = await outbox.sendPending()
        if uploaded.sent > 0 || deleted.sent > 0 {
            gate.recordUpload(at: startedAt)
        }
    }
}

struct NightscoutOverrideDeletion: JSON {
    let createdAt: Date
}
