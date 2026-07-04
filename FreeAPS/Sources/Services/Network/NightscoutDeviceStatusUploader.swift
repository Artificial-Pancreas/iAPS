import Foundation
import UIKit

actor NightscoutDeviceStatusUploader {
    private let apiProvider: @Sendable() async -> NightscoutAPI?
    private let isUploadEnabled: @Sendable() -> Bool

    private let suggestedOutbox: UploadOutbox<Suggestion, Date?>
    private let enactedOutbox: UploadOutbox<Suggestion, Date?>
    private let overridesOutbox: UploadOutbox<NigtscoutExercise, Date>

    private let iapsVersion: String

    /// for pump status push throttling
    private var lastUploadedPumpStatus: PumpDisplayStatus?

    init(
        apiProvider: @escaping @Sendable() async -> NightscoutAPI?,
        isUploadEnabled: @escaping @Sendable() -> Bool,
        storage: FileStorage
    ) {
        self.apiProvider = apiProvider
        self.isUploadEnabled = isUploadEnabled

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
                guard let nightscout = await apiProvider() else { throw DataSyncError.sinkUnavailable }
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
                guard let nightscout = await apiProvider() else { throw DataSyncError.sinkUnavailable }
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
                guard let nightscout = await apiProvider() else { throw DataSyncError.sinkUnavailable }
                try await nightscout.deleteOverride(at: override.createdAt)
                try await nightscout.uploadEcercises([override])
            }
        )
    }

    private func canUpload() async -> Bool {
        guard isUploadEnabled() else { return false }
        return (await apiProvider()) != nil
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
        guard await canUpload() else { return }
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

        guard await canUpload() else { return }
        await overridesOutbox.sendPending()
    }

    func uploadIOB(_ iob: [IOBEntry]) async {
        guard let iob = iob.first else { return }
        guard isUploadEnabled(), let nightscout = await apiProvider() else { return }

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
        guard isUploadEnabled(), let nightscout = await apiProvider() else { return }

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
