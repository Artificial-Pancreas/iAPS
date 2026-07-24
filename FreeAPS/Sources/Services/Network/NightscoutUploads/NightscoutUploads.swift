import Foundation

final class NightscoutUploads: AppService, Sendable {
    let overridesUploader: NightscoutOverridesUploader

    private let entities: [any AppService]

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

        func treatmentSink() -> NightscoutTreatmentSink {
            NightscoutTreatmentSink(apiProvider: { apiProvider.api })
        }

        let pumpHistory = NightscoutCollectionSync(
            name: "pumpHistory",
            group: .treatmentsAndLoops,
            sink: treatmentSink(),
            snapshotFile: OpenAPS.Nightscout.uploadedPumphistory,
            retention: .hours(24),
            deletionWindow: .hours(8),
            context: context,
            source: \.pumpHistory,
            records: { NightscoutConversions.treatments(fromPumpHistory: $0) }
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
            records: { NightscoutConversions.treatments(fromCarbHistory: $0) }
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
            records: { NightscoutConversions.treatments(fromTempTargets: $0) }
        )

        let podAge = NightscoutCollectionSync(
            name: "podAge",
            group: .deviceStatus,
            sink: treatmentSink(),
            snapshotFile: OpenAPS.Nightscout.uploadedPodAge,
            retention: .days(15),
            deletionWindow: 0, // append-only
            context: context,
            source: \.pumpInfo,
            records: { pumpInfo in
                pumpInfo?.podActivatedAt.map { [NightscoutConversions.podSiteTreatment(podActivatedAt: $0)] } ?? []
            }
        )

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
            podAge,
            cgmState,
            NightscoutLoopStatusUploader(context: context),
            overrides,
            NightscoutPumpStatusUploader(context: context),
            NightscoutIOBUploader(context: context)
        ]
    }

    func start() async throws {
        for entity in entities {
            try await entity.start()
        }
    }
}
