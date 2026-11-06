import Foundation

final class NightscoutUploads: AppService, Sendable {
    let overridesUploader: NightscoutOverridesUploader

    private let burst: NightscoutUploadBurst
    private let entities: [any NightscoutUploadEntity]
    private let pumpChangeRecorder: PumpChangeRecorder

    init(
        apiProvider: NightscoutAPIProvider,
        appCoordinator: AppCoordinator,
        reachabilityManager: ReachabilityManager,
        storage: FileStorage
    ) {
        let context = NightscoutUploadContext(
            apiProvider: apiProvider,
            appCoordinator: appCoordinator,
            reachabilityManager: reachabilityManager,
            storage: storage
        )
        burst = context.burst

        func treatmentSink() -> NightscoutTreatmentSink {
            NightscoutTreatmentSink(apiProvider: { apiProvider.api })
        }

        let pumpHistory = NightscoutCollectionSync(
            name: "pumpHistory",
            group: .treatmentsAndLoops,
            // the primes' Site Changes stay in Nightscout (`pumpHistoryKeeps`: the transition's first reconcile)
            sink: KeepingSink(base: treatmentSink(), keeps: Self.pumpHistoryKeeps),
            snapshotFile: OpenAPS.Nightscout.uploadedPumphistory,
            retention: .hours(24),
            deletionWindow: .hours(8),
            context: context,
            source: \.pumpHistory,
            records: { NightscoutConversions.treatments(fromPumpHistory: $0) },
            // a manual bolus (it runs no loop), a suspend/resume
            isUrgent: { previous, current in
                let known = Set(previous.filter(\.isUrgentUpload).map(\.identity))
                return current.contains { $0.isUrgentUpload && !known.contains($0.identity) }
            }
        )

        let glucose = NightscoutCollectionSync(
            name: "glucose",
            group: .glucose,
            sink: NightscoutGlucoseSink(apiProvider: { apiProvider.api }),
            snapshotFile: OpenAPS.Nightscout.uploadedGlucose,
            retention: .hours(24),
            deletionWindow: .hours(8),
            context: context,
            source: \.glucoseRaw,
            isEnabled: { $0.cgmStatus.value?.shouldUploadGlucose == true },
            records: { $0 }
        )

        let carbs = NightscoutCollectionSync(
            name: "carbs",
            group: .treatmentsAndLoops,
            sink: treatmentSink(),
            snapshotFile: OpenAPS.Nightscout.uploadedCarbs,
            retention: .hours(24),
            deletionWindow: .hours(8),
            context: context,
            source: \.carbHistory,
            records: { NightscoutConversions.treatments(fromCarbHistory: $0) },
            // by the records: the 1-minute NS fetch re-publishes the history unchanged
            isUrgent: {
                NightscoutConversions.treatments(fromCarbHistory: $0).syncState !=
                    NightscoutConversions.treatments(fromCarbHistory: $1).syncState
            }
        )

        let tempTargets = NightscoutCollectionSync(
            name: "tempTargets",
            group: .treatmentsAndLoops,
            sink: treatmentSink(),
            snapshotFile: OpenAPS.Nightscout.uploadedTempTargets,
            retention: .hours(24),
            deletionWindow: 0, // append-only
            context: context,
            source: \.tempTargets,
            records: { NightscoutConversions.treatments(fromTempTargets: $0) },
            isUrgent: {
                NightscoutConversions.treatments(fromTempTargets: $0).syncState !=
                    NightscoutConversions.treatments(fromTempTargets: $1).syncState
            }
        )

        let pumpChangeRecorder = PumpChangeRecorder(storage: storage)
        self.pumpChangeRecorder = pumpChangeRecorder
        let siteChanges = Self.siteChangeSync(sink: treatmentSink(), recorder: pumpChangeRecorder, context: context)

        let cgmStateRecorder = CgmStateRecorder(storage: storage)
        let cgmState = NightscoutCollectionSync(
            name: "cgmState",
            group: .deviceStatus,
            sink: treatmentSink(),
            snapshotFile: OpenAPS.Nightscout.uploadedCGMState,
            retention: .days(40),
            deletionWindow: 0, // append-only
            context: context,
            source: \.cgmStatus,
            isEnabled: { $0.cgmStatus.value?.shouldUploadGlucose == true },
            prepare: { await cgmStateRecorder.noteStatus($0) },
            records: { _ in await cgmStateRecorder.currentRecords() }
        )

        let overrides = NightscoutOverridesUploader(context: context)
        overridesUploader = overrides

        entities = [
            pumpHistory,
            glucose,
            carbs,
            tempTargets,
            siteChanges,
            cgmState,
            NightscoutDeviceStatusUploader(context: context),
            overrides
        ]
    }

    func start() async throws {
        // before the change events can come: the Site Changes' log starts at the first launch with it
        await pumpChangeRecorder.start()
        await burst.start(entities: entities)
        for entity in entities {
            try await entity.start()
        }
    }
}

extension NightscoutUploads {
    /// The pump history's deletes keep the primes' Site Changes, uploaded until the Site Changes came from the change
    /// events: for the 24 h after the update (the snapshot's retention), then nothing is left to keep. It can go a
    /// release later. The first reconcile after the update drops them from the snapshot without a request, and so
    /// can record a `.synced` gate time without one: once, harmless.
    static let pumpHistoryKeeps: @Sendable(NigtscoutTreatment) -> Bool = { $0.eventType == .nsSiteChange }

    /// One Site Change per pod, patch or infusion set, from the pump's change events (`PumpChangeRecorder`, as Loop and
    /// Trio upload them). It took over the retired pod-age sync's place: its name (the Last Uploads row's history), its
    /// group (device status, beside `cgmState`) and its snapshot (one Site Change per `podActivatedAt`, which stay in
    /// Nightscout).
    ///
    /// Append-only: no delete is ever sent (`KeepingSink` keeps all, and the deletion window is 0). An update (a record
    /// of the same type and second as one uploaded, its fields different) deletes and re-POSTs that key: harmless.
    static func siteChangeSync<Sink: SyncSink>(
        sink: Sink,
        recorder: PumpChangeRecorder,
        context: NightscoutUploadContext
    ) -> NightscoutCollectionSync<[PumpLifecycleEvent], NigtscoutTreatment, KeepingSink<Sink>>
        where Sink.Record == NigtscoutTreatment
    {
        NightscoutCollectionSync(
            name: SiteChangeSync.name,
            group: SiteChangeSync.group,
            sink: KeepingSink(base: sink, keeps: SiteChangeSync.keeps),
            snapshotFile: SiteChangeSync.snapshotFile,
            retention: SiteChangeSync.retention,
            deletionWindow: SiteChangeSync.deletionWindow,
            context: context,
            events: \.pumpLifecycleEvents,
            record: { await recorder.note($0) },
            records: { await recorder.currentRecords() }
        )
    }

    /// `siteChangeSync`'s configuration
    enum SiteChangeSync {
        /// the pod-age sync's: its `lastUpload` key, `nightscoutUpload.lastUpload.podAge`
        static let name = "podAge"
        /// the pod-age sync's
        static let group: UploadScheduleGroup = .deviceStatus
        static let snapshotFile = OpenAPS.Nightscout.uploadedSiteChanges
        static let retention = PumpChangeRecorder.retention
        static let deletionWindow: TimeInterval = 0
        static let keeps: @Sendable(NigtscoutTreatment) -> Bool = { _ in true }
    }
}

private extension PumpHistoryEvent {
    var isUrgentUpload: Bool {
        switch type {
        case .bolus: return isSMB != true
        case .pumpResume,
             .pumpSuspend: return true
        default: return false
        }
    }
}
