import Foundation
import UIKit

final actor NightscoutLoopStatusUploader: LifetimeOwner, AppService {
    let lifetime = Lifetime()

    private let context: NightscoutUploadContext
    private let gate: UploadScheduleGate
    private let suggestedOutbox: UploadOutbox<Suggestion, Date?>
    private let enactedOutbox: UploadOutbox<Suggestion, Date?>

    init(context: NightscoutUploadContext) {
        self.context = context
        gate = context.makeGate(name: "loopStatus", group: .treatmentsAndLoops)

        let apiProvider = context.apiProvider
        let version = Bundle.main.releaseVersionNumber ?? "Unknown"

        suggestedOutbox = UploadOutbox(
            file: OpenAPS.Upload.recentSuggested,
            retention: .hours(30),
            uniqueBy: \.timestamp,
            dateBy: \.timestamp,
            storage: context.storage,
            category: .nightscout,
            send: { suggested in
                guard let timestamp = suggested.timestamp else { return }
                guard let nightscout = apiProvider.api else { throw DataSyncError.sinkUnavailable }
                try await nightscout.uploadStatus(NightscoutStatus(
                    device: NigtscoutTreatment.local,
                    openaps: OpenAPSStatus(iob: nil, suggested: suggested, enacted: nil, version: version),
                    pump: nil,
                    uploader: nil,
                    createdAt: timestamp
                ))
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
                guard let timestamp = enacted.timestamp else { return }
                guard let nightscout = apiProvider.api else { throw DataSyncError.sinkUnavailable }
                // NS needs both suggested + enacted set to show predictions on the graph.
                try await nightscout.uploadStatus(NightscoutStatus(
                    device: NigtscoutTreatment.local,
                    openaps: OpenAPSStatus(iob: nil, suggested: enacted, enacted: enacted, version: version),
                    pump: nil,
                    uploader: nil,
                    createdAt: timestamp
                ))
            }
        )
    }

    func start() async {
        observe(context.appCoordinator.loopCompleted) { me, outcome in
            await withBackgroundTask("nightscout upload - loop status") {
                await me.loopCompleted(outcome)
            }
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

        guard context.canUpload(), await gate.allows() else { return }
        let suggested = await suggestedOutbox.sendPending()
        let enacted = await enactedOutbox.sendPending()
        if suggested.sent + enacted.sent > 0 {
            gate.recordUpload()
        }
    }
}

final actor NightscoutOverridesUploader: LifetimeOwner, AppService {
    let lifetime = Lifetime()

    private let context: NightscoutUploadContext
    private let gate: UploadScheduleGate
    private let outbox: UploadOutbox<NigtscoutExercise, Date>

    init(context: NightscoutUploadContext) {
        self.context = context
        gate = context.makeGate(name: "overrides", group: .treatmentsAndLoops)

        let apiProvider = context.apiProvider
        outbox = UploadOutbox(
            file: OpenAPS.Nightscout.notUploadedOverrides,
            retention: .days(2),
            uniqueBy: \.createdAt,
            dateBy: \.createdAt,
            storage: context.storage,
            category: .nightscout,
            send: { override in
                guard let nightscout = apiProvider.api else { throw DataSyncError.sinkUnavailable }
                try await nightscout.deleteOverride(at: override.createdAt)
                try await nightscout.uploadEcercises([override])
            }
        )
    }

    func start() async {
        observe(context.appCoordinator.loopCompleted) { me, _ in
            await withBackgroundTask("nightscout upload - overrides") {
                await me.flushPending()
            }
        }
    }

    func uploadOverride(_ profile: String, _ duration: Double, _ date: Date) async {
        let duration = Int(duration == 0 ? 2880 : duration)

        let exercise = NigtscoutExercise(
            duration: duration,
            eventType: EventType.nsExercise,
            createdAt: date.truncatedToSecond,
            enteredBy: NigtscoutTreatment.local,
            notes: profile
        )

        await outbox.enqueue([exercise])
        await flushPending()
    }

    private func flushPending() async {
        guard context.canUpload(), await gate.allows() else { return }
        let result = await outbox.sendPending()
        if result.sent > 0 {
            gate.recordUpload()
        }
    }
}

final actor NightscoutPumpStatusUploader: LifetimeOwner, AppService {
    let lifetime = Lifetime()

    private let context: NightscoutUploadContext
    private let gate: UploadScheduleGate

    /// for pump status push throttling
    private var lastUploadedPumpStatus: PumpDisplayStatus?

    init(context: NightscoutUploadContext) {
        self.context = context
        gate = context.makeGate(name: "pumpStatus", group: .deviceStatus)
    }

    func start() async {
        observe(context.appCoordinator.pumpStatus) { me, pumpStatus in
            if let pumpStatus {
                await withBackgroundTask("nightscout upload - pump status") {
                    await me.pumpStatusUpdated(pumpStatus)
                }
            }
        }
    }

    private func shouldUploadPumpStatusNow(_ pumpStatus: PumpDisplayStatus) -> Bool {
        guard let lastUploadedPumpStatus else { return true }
        if Date.now.timeIntervalSince(lastUploadedPumpStatus.timestamp) >= .minutes(5) {
            return true
        }
        return lastUploadedPumpStatus.isSuspended != pumpStatus.isSuspended ||
            lastUploadedPumpStatus.isBolusing != pumpStatus.isBolusing ||
            lastUploadedPumpStatus.status != pumpStatus.status ||
            lastUploadedPumpStatus.statusHighlight != pumpStatus.statusHighlight
    }

    private func pumpStatusUpdated(_ pumpStatus: PumpDisplayStatus) async {
        guard shouldUploadPumpStatusNow(pumpStatus) else { return }
        guard context.canUpload(), let nightscout = context.api else { return }
        guard await gate.allows() else { return }

        let nsPumpStatus = NSPumpStatusDetails(
            status: NSStatusType(rawValue: pumpStatus.status.rawValue) ?? .normal,
            bolusing: pumpStatus.isBolusing,
            suspended: pumpStatus.isSuspended,
            timestamp: pumpStatus.timestamp
        )

        let pump = NSPumpStatus(
            clock: pumpStatus.timestamp,
            battery: pumpStatus.battery,
            reservoir: pumpStatus.reservoir?.knownValue,
            status: nsPumpStatus
        )

        let device = await UIDevice.current
        let batteryLevel = await device.batteryLevel
        let uploader = Uploader(batteryVoltage: nil, battery: Int(batteryLevel * 100))

        let status = NightscoutStatus(
            device: NigtscoutTreatment.local,
            openaps: nil,
            pump: pump,
            uploader: uploader,
            createdAt: pumpStatus.timestamp
        )

        do {
            try await nightscout.uploadStatus(status)
            lastUploadedPumpStatus = pumpStatus
            gate.recordUpload()
            debug(.nightscout, "pump status uploaded")
        } catch {
            debug(.nightscout, "failed to upload pump status: \(error.localizedDescription)")
        }
    }
}

final actor NightscoutIOBUploader: LifetimeOwner, AppService {
    let lifetime = Lifetime()

    private let context: NightscoutUploadContext
    private let gate: UploadScheduleGate
    private let iapsVersion: String

    init(context: NightscoutUploadContext) {
        self.context = context
        gate = context.makeGate(name: "iob", group: .deviceStatus)
        iapsVersion = Bundle.main.releaseVersionNumber ?? "Unknown"
    }

    func start() async {
        observe(context.appCoordinator.iobTicks.dropFirst()) { me, iobTicks in
            if let iobTicks {
                await withBackgroundTask("nightscout upload - iob") {
                    await me.uploadIOB(iobTicks)
                }
            }
        }
    }

    private func uploadIOB(_ iob: [IOBEntry]) async {
        guard let iob = iob.first else { return }
        guard context.canUpload(), let nightscout = context.api else { return }
        guard await gate.allows() else { return }

        let status = NightscoutStatus(
            device: NigtscoutTreatment.local,
            openaps: OpenAPSStatus(
                iob: iob,
                suggested: nil,
                enacted: nil,
                version: iapsVersion
            ),
            pump: nil,
            uploader: nil,
            createdAt: iob.time ?? Date.now
        )

        do {
            try await nightscout.uploadStatus(status)
            gate.recordUpload()
            debug(.nightscout, "iob uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }
}
