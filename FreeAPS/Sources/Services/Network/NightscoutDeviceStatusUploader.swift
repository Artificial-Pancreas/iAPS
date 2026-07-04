import Foundation
import UIKit

actor NightscoutDeviceStatusUploader: LifetimeOwner, AppService {
    private let apiProvider: NightscoutAPIProvider
    private let appCoordinator: AppCoordinator

    let lifetime = Lifetime()

    private let suggestedOutbox: UploadOutbox<Suggestion, Date?>
    private let enactedOutbox: UploadOutbox<Suggestion, Date?>
    private let overridesOutbox: UploadOutbox<NigtscoutExercise, Date>

    private let iapsVersion: String

    /// for pump status push throttling
    private var lastUploadedPumpStatus: PumpDisplayStatus?

    init(
        apiProvider: NightscoutAPIProvider,
        appCoordinator: AppCoordinator,
        storage: FileStorage
    ) {
        self.apiProvider = apiProvider
        self.appCoordinator = appCoordinator

        let version = Bundle.main.releaseVersionNumber ?? "Unknown"
        iapsVersion = version

        suggestedOutbox = UploadOutbox(
            file: OpenAPS.Upload.recentSuggested,
            retention: .hours(30),
            uniqueBy: \.timestamp,
            dateBy: \.timestamp,
            storage: storage,
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
            storage: storage,
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
        overridesOutbox = UploadOutbox(
            file: OpenAPS.Nightscout.notUploadedOverrides,
            retention: .days(2),
            uniqueBy: \.createdAt,
            dateBy: \.createdAt,
            storage: storage,
            category: .nightscout,
            send: { override in
                guard let nightscout = apiProvider.api else { throw DataSyncError.sinkUnavailable }
                try await nightscout.deleteOverride(at: override.createdAt)
                try await nightscout.uploadEcercises([override])
            }
        )
    }

    func start() async {
        observe(appCoordinator.loopCompleted) { me, outcome in
            await withBackgroundTask("nightscout upload - device status") {
                await me.loopCompleted(outcome)
            }
        }

        observe(appCoordinator.pumpStatus) { me, pumpStatus in
            if let pumpStatus {
                await withBackgroundTask("nightscout upload - pump status") {
                    await me.pumpStatusUpdated(pumpStatus)
                }
            }
        }

        observe(appCoordinator.iobTicks.dropFirst()) { me, iobTicks in
            if let iobTicks {
                await withBackgroundTask("nightscout upload - iob") {
                    await me.uploadIOB(iobTicks)
                }
            }
        }
    }

    private var isUploadEnabled: Bool {
        appCoordinator.settings.value.isUploadEnabled
    }

    private func canUpload() -> Bool {
        guard isUploadEnabled else { return false }
        return apiProvider.api != nil
    }

    func loopCompleted(_ outcome: LoopOutcome) async {
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

        await sendAllPending()
    }

    func sendAllPending() async {
        guard canUpload() else { return }
        await suggestedOutbox.sendPending()
        await enactedOutbox.sendPending()
        await overridesOutbox.sendPending()
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

        await overridesOutbox.enqueue([exercise])

        guard canUpload() else { return }
        await overridesOutbox.sendPending()
    }

    func uploadIOB(_ iob: [IOBEntry]) async {
        guard let iob = iob.first else { return }
        guard isUploadEnabled, let nightscout = apiProvider.api else { return }

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
            debug(.nightscout, "iob uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
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

    func pumpStatusUpdated(_ pumpStatus: PumpDisplayStatus) async {
        // do not flood nightscout
        guard shouldUploadPumpStatusNow(pumpStatus) else { return }
        guard isUploadEnabled, let nightscout = apiProvider.api else { return }

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
            debug(.nightscout, "pump status uploaded")
        } catch {
            debug(.nightscout, "failed to upload pump status: \(error.localizedDescription)")
        }
    }
}
