import Foundation

actor NightscoutDataSync: LifetimeOwner, AppService {
    private let apiProvider: NightscoutAPIProvider
    private let appCoordinator: AppCoordinator
    private let reachabilityManager: ReachabilityManager
    private let storage: FileStorage

    let lifetime = Lifetime()

    private let pumpHistorySync: DataSynchronizer<NigtscoutTreatment, NightscoutTreatmentSink>
    private let glucoseSync: DataSynchronizer<BloodGlucose, NightscoutGlucoseSink>
    private let carbsSync: DataSynchronizer<NigtscoutTreatment, NightscoutTreatmentSink>
    private let tempTargetsSync: DataSynchronizer<NigtscoutTreatment, NightscoutTreatmentSink>
    private let podAgeSync: DataSynchronizer<NigtscoutTreatment, NightscoutTreatmentSink>
    private let cgmStateSync: DataSynchronizer<NigtscoutTreatment, NightscoutTreatmentSink>

    private var lastSeenCgmStart: Date?

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

        func treatmentSync(
            name: String,
            snapshotFile: String,
            retention: TimeInterval,
            deletionWindow: TimeInterval
        ) -> DataSynchronizer<NigtscoutTreatment, NightscoutTreatmentSink> {
            DataSynchronizer(
                name: name,
                sink: NightscoutTreatmentSink(apiProvider: { apiProvider.api }),
                storage: storage,
                snapshotFile: snapshotFile,
                retention: retention,
                deletionWindow: deletionWindow,
                category: .nightscout
            )
        }

        pumpHistorySync = treatmentSync(
            name: "ns.treatments",
            snapshotFile: OpenAPS.Nightscout.uploadedPumphistory,
            retention: .hours(24),
            deletionWindow: .hours(8)
        )

        glucoseSync = DataSynchronizer(
            name: "ns.glucose",
            sink: NightscoutGlucoseSink(apiProvider: { apiProvider.api }),
            storage: storage,
            snapshotFile: OpenAPS.Nightscout.uploadedGlucose,
            retention: .hours(24),
            deletionWindow: .hours(8),
            category: .nightscout
        )

        carbsSync = treatmentSync(
            name: "ns.carbs",
            snapshotFile: OpenAPS.Nightscout.uploadedCarbs,
            retention: .hours(24),
            deletionWindow: .hours(8)
        )

        tempTargetsSync = treatmentSync(
            name: "ns.tempTargets",
            snapshotFile: OpenAPS.Nightscout.uploadedTempTargets,
            retention: .hours(24),
            deletionWindow: 0 // append-only
        )

        podAgeSync = treatmentSync(
            name: "ns.podAge",
            snapshotFile: OpenAPS.Nightscout.uploadedPodAge,
            retention: .days(15),
            deletionWindow: 0 // append-only
        )

        cgmStateSync = treatmentSync(
            name: "ns.cgmState",
            snapshotFile: OpenAPS.Nightscout.uploadedCGMState,
            retention: .days(40),
            deletionWindow: 0 // append-only
        )
    }

    func start() async {
        observe(appCoordinator.pumpHistory) { me, pumpHistory in
            await withBackgroundTask("nightscout upload - pump history") {
                await me.pumpHistoryUpdated(pumpHistory)
            }
        }

        observe(appCoordinator.glucoseHistory) { me, bloodGlucose in
            await withBackgroundTask("nightscout upload - blood glucose") {
                await me.glucoseHistoryUpdated(bloodGlucose)
            }
        }

        observe(appCoordinator.carbHistory) { me, carbHistory in
            await withBackgroundTask("nightscout upload - carb history") {
                await me.carbHistoryUpdated(carbHistory)
            }
        }

        observe(appCoordinator.tempTargets) { me, tempTargets in
            await withBackgroundTask("nightscout upload - temp targets") {
                await me.tempTargetsUpdated(tempTargets)
            }
        }

        observe(appCoordinator.cgmStatus) { me, cgmStatus in
            if let cgmStatus {
                await withBackgroundTask("nightscout upload - cgm status") {
                    await me.cgmStatusUpdated(cgmStatus)
                }
            }
        }

        observe(appCoordinator.pumpInfo.map(\.?.podActivatedAt)) { me, podActivatedAt in
            if let podActivatedAt {
                await withBackgroundTask("nightscout upload - pod activation") {
                    await me.uploadPodAge(podActivatedAt: podActivatedAt)
                }
            }
        }

        observe(appCoordinator.loopCompleted) { me, _ in
            await withBackgroundTask("nightscout upload - pod age retry") {
                await me.retryPodAgeIfNeeded()
            }
        }
    }

    private var isNetworkReachable: Bool {
        reachabilityManager.isReachable
    }

    private func canUpload() -> Bool {
        guard appCoordinator.settings.value.isUploadEnabled, isNetworkReachable else { return false }
        return apiProvider.api != nil
    }

    func pumpHistoryUpdated(_ pumpHistory: [PumpHistoryEvent]) async {
        guard canUpload() else { return }
        let treatments = convertPumpHistoryToNightscout(events: pumpHistory)
        await pumpHistorySync.reconcile { treatments }
    }

    func glucoseHistoryUpdated(_ bloodGlucose: [BloodGlucose]) async {
        guard canUpload(), appCoordinator.cgmStatus.value?.shouldUploadGlucose == true else { return }
        await glucoseSync.reconcile { bloodGlucose }
    }

    func carbHistoryUpdated(_ carbHistory: [CarbsEntry]) async {
        guard canUpload() else { return }
        let treatments = convertCarbHistoryToNightscout(events: carbHistory)
        await carbsSync.reconcile { treatments }
    }

    func tempTargetsUpdated(_ tempTargets: [TempTarget]) async {
        guard canUpload() else { return }
        let treatments = convertTempTargetsToNightscout(events: tempTargets)
        await tempTargetsSync.reconcile { treatments }
    }

    func uploadPodAge(podActivatedAt: Date) async {
        guard canUpload() else {
            await podAgeSync.markPending()
            return
        }
        let siteTreatment = podSiteTreatment(podActivatedAt: podActivatedAt)
        await podAgeSync.reconcile { [siteTreatment] }
    }

    func retryPodAgeIfNeeded() async {
        guard canUpload(),
              let podActivatedAt = appCoordinator.pumpInfo.value?.podActivatedAt
        else {
            return
        }
        let siteTreatment = podSiteTreatment(podActivatedAt: podActivatedAt)
        await podAgeSync.reconcile(trigger: .retry) { [siteTreatment] }
    }

    func cgmStatusUpdated(_ cgmStatus: CgmDisplayStatus) async {
        // sensor-change log
        var recorded: [NigtscoutTreatment]?
        if let sessionStartDate = cgmStatus.sessionStartDate,
           abs(sessionStartDate.timeIntervalSince(lastSeenCgmStart ?? .distantPast)) > 60
        {
            lastSeenCgmStart = sessionStartDate
            recorded = await recordSensorStartIfNeeded(sessionStartDate)
        }

        guard canUpload(), cgmStatus.shouldUploadGlucose else {
            if recorded != nil {
                await cgmStateSync.markPending()
            }
            return
        }

        if let recorded {
            await cgmStateSync.reconcile { recorded }
        } else {
            // retry previous uploads if needed
            await cgmStateSync.reconcile(trigger: .retry) { [self] in await readCgmState() }
        }
    }

    private func podSiteTreatment(podActivatedAt: Date) -> NigtscoutTreatment {
        NigtscoutTreatment(
            duration: nil,
            rawDuration: nil,
            rawRate: nil,
            absolute: nil,
            rate: nil,
            eventType: .nsSiteChange,
            createdAt: podActivatedAt,
            enteredBy: NigtscoutTreatment.local,
            bolus: nil,
            insulin: nil,
            notes: nil,
            carbs: nil,
            fat: nil,
            protein: nil,
            targetTop: nil,
            targetBottom: nil
        )
    }

    private func recordSensorStartIfNeeded(_ sessionStartDate: Date) async -> [NigtscoutTreatment]? {
        let (didModify, modifiedCgmState) = await storage
            .maybeModify(file: OpenAPS.Monitor.cgmState, as: NigtscoutTreatment.self) { inStorage in
                // For Dexcom, each glucose event contains the sessionStartDate (which contains the correct timestamp of the latest sensor start)
                // We only need to send the "Sensor Start" event once per change.
                // This guard ensures we send a new "Sensor Start" event to NS only if the previously sent event happened more than 60 seconds before this one.
                //
                // As a side effect, if there is jitter in the sessionStartDate (+/- few milliseconds each time), we will flood NS with the duplicated Session Start events over time.
                // See: https://github.com/Artificial-Pancreas/iAPS/issues/1806
                if inStorage.contains(where: { abs($0.createdAt.timeIntervalSince(sessionStartDate)) < 60 }) {
                    return nil // do not modify
                }

                debug(.deviceManager, "CGM sensor change \(sessionStartDate)")

                let treatment = NigtscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsSensorChange,
                    createdAt: sessionStartDate,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: nil,
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )

                var treatments = inStorage
                treatments.append(treatment)

                // We have to keep quite a bit of history as sensors start only every 10 days.
                let daysAgo30 = Date.now.removingTimeInterval(.days(30))
                return treatments
                    .filter { $0.createdAt >= daysAgo30 }
                    .sorted { $0.createdAt > $1.createdAt }
            }
        if didModify {
            return modifiedCgmState
        }
        return nil
    }

    private func readCgmState() async -> [NigtscoutTreatment] {
        let (_, cgmState) = await storage
            .maybeModify(file: OpenAPS.Monitor.cgmState, as: NigtscoutTreatment.self) { cgmState in
                // filter older cgm entries on read
                let daysAgo30 = Date.now.removingTimeInterval(.days(30))
                let last30days = cgmState.filter { $0.createdAt >= daysAgo30 }
                if last30days.count == cgmState.count {
                    return nil // do not modify
                }
                return last30days // save with older-than-30-days entries removed
            }

        return cgmState
    }
}

extension NightscoutDataSync {
    /// returns events converted to nightscout format, oldest -> newest
    private func convertPumpHistoryToNightscout(events: [PumpHistoryEvent]) -> [NigtscoutTreatment] {
        guard !events.isEmpty else { return [] }

        let temps: [NigtscoutTreatment] = events.reduce([]) { result, event in
            var result = result
            switch event.type {
            case .tempBasal:
                result.append(NigtscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: event,
                    absolute: event.rate,
                    rate: event.rate,
                    eventType: .nsTempBasal,
                    createdAt: event.timestamp.truncatedToSecond,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: nil,
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                ))
            case .tempBasalDuration:
                guard var last = result.popLast() else { break }
                if last.eventType == .nsTempBasal,
                   last.createdAt == event.timestamp.truncatedToSecond
                {
                    last.duration = event.durationMin
                    last.rawDuration = event
                }
                result.append(last)
            default: break
            }
            return result
        }

        let bolusesAndCarbs = events.compactMap { event -> NigtscoutTreatment? in
            switch event.type {
            case .bolus:
                let eventType = determineBolusEventType(for: event)
                return NigtscoutTreatment(
                    duration: event.duration,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: eventType,
                    createdAt: event.timestamp.truncatedToSecond,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: event,
                    insulin: event.amount,
                    notes: nil,
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )
            case .journalCarbs:
                return NigtscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsCarbCorrection,
                    createdAt: event.timestamp.truncatedToSecond,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: nil,
                    carbs: Decimal(event.carbInput ?? 0),
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil,
                    creation_date: event.timestamp
                )
            default: return nil
            }
        }

        let misc = events.compactMap { event -> NigtscoutTreatment? in
            switch event.type {
            case .prime:
                return NigtscoutTreatment(
                    duration: event.duration,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsSiteChange,
                    createdAt: event.timestamp.truncatedToSecond,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: event,
                    insulin: nil,
                    notes: nil,
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )
            case .rewind:
                return NigtscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsInsulinChange,
                    createdAt: event.timestamp.truncatedToSecond,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: nil,
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )
            case .pumpAlarm:
                return NigtscoutTreatment(
                    duration: 30, // minutes
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsAnnouncement,
                    createdAt: event.timestamp.truncatedToSecond,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: "Alarm \(String(describing: event.note)) \(event.type)",
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )
            default: return nil
            }
        }

        return (
            bolusesAndCarbs +
                temps.filter { $0.duration != nil } +
                misc
        ).sorted { $0.createdAt > $1.createdAt }
    }

    private func determineBolusEventType(for event: PumpHistoryEvent) -> EventType {
        if event.isSMB ?? false {
            return .smb
        }
        if event.isExternal ?? false {
            return .isExternal
        }
        return event.type
    }
}

extension NightscoutDataSync {
    /// returns events converted to nightscout format, newest -> oldest
    private func convertCarbHistoryToNightscout(events: [CarbsEntry]) -> [NigtscoutTreatment] {
        let eventsManual = events
            .filter {
                ($0.enteredBy == CarbsEntry.manual || $0.enteredBy == CarbsEntry.remote || $0.enteredBy == CarbsEntry.shortcut) &&
                    $0.carbs > 0 && $0.isFPU != true }
        let treatments = eventsManual.map {
            NigtscoutTreatment(
                duration: nil,
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsCarbCorrection,
                createdAt: $0.actualDate?.truncatedToSecond ?? .distantPast,
                enteredBy: $0.enteredBy ?? CarbsEntry.manual,
                bolus: nil,
                insulin: nil,
                carbs: $0.carbs,
                fat: $0.fat,
                protein: $0.protein,
                foodType: $0.note,
                targetTop: nil,
                targetBottom: nil,
                id: $0.id,
                fpuID: nil,
                creation_date: $0.createdAt
            )
        }
        return treatments.sorted { $0.createdAt > $1.createdAt }
    }
}

extension NightscoutDataSync {
    /// returns temp targets converted to nightscout format, newest -> oldest
    private func convertTempTargetsToNightscout(events: [TempTarget]) -> [NigtscoutTreatment] {
        let eventsManual = events.filter { $0.enteredBy == TempTarget.manual }
        let treatments = eventsManual.map {
            NigtscoutTreatment(
                duration: $0.duration,
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsTempTarget,
                createdAt: $0.createdAt.truncatedToSecond,
                enteredBy: TempTarget.manual,
                bolus: nil,
                insulin: nil,
                notes: nil,
                carbs: nil,
                targetTop: $0.targetTop,
                targetBottom: $0.targetBottom
            )
        }
        return treatments.sorted { $0.createdAt > $1.createdAt }
    }
}
