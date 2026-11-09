import CGMBLEKit
import Combine
import CoreData
import G7SensorKit
import LoopKit
import SwiftUI

extension NightscoutConfig {
    final class StateModel: BaseStateModel<Provider>, UIBindingOwner {
        let uiBindings = UIBindings()
        @Injected() private var keychain: Keychain!
        @Injected() private var nightscoutManager: NightscoutManager!
        @Injected() private var glucoseStorage: GlucoseStorage!
        @Injected() private var coreDataManager: CoreDataManager!
        @Injected() private var apsManager: APSManager!
        @Injected() private var deviceManager: DeviceDataManager!
        @Injected() private var basalProfileStorage: BasalProfileStorage!
        @Injected() private var isfScheduleStorage: IsfScheduleStorage!
        @Injected() private var crScheduleStorage: CarbRatioScheduleStorage!
        @Injected() private var bgTargetsScheduleStorage: BgTargetsScheduleStorage!
        @Injected() private var pumpEventStore: PumpEventStore!
        @Injected() private var cgmSessionStore: CGMSessionStore!

        private let coredataContext = CoreDataStack.shared.persistentContainer.viewContext
        private let coreDataStorage = CoreDataStorage()

        @Published var url = ""
        @Published var secret = ""
        @Published var message = ""
        @Published var connecting = false
        enum BackfillPhase {
            case fetching
            case saving
        }

        enum BackfillKind {
            case glucose
            case insulin
        }

        /// nil: no backfill running
        @Published var backfillPhase: BackfillPhase?
        /// what the running (or last) backfill fetches: one runs at a time
        @Published var backfillKind: BackfillKind = .glucose
        /// of the phase
        @Published var backfillingProgress = 0.0
        /// how the last glucose backfill went, until the next one starts
        @Published var backfillResult: String?
        /// how the last insulin backfill went, until the next one starts
        @Published var insulinBackfillResult: String?
        var backfilling: Bool { backfillPhase != nil }
        @Published var uploading = false
        @Published var uploadingProgress = 0.0
        @Published var isUploadEnabled = false // Allow uploads
        @Published var uploadsPausedUntil: Date?
        @Published var nightscoutFetchEnabled = true // Allow fetch
        @Setting(\.glucoseUploadSchedule) var glucoseUploadSchedule = UploadSchedule()
        @Setting(\.treatmentsAndLoopsUploadSchedule) var treatmentsAndLoopsUploadSchedule = UploadSchedule()
        @Setting(\.deviceStatusUploadSchedule) var deviceStatusUploadSchedule = UploadSchedule()
        @Published var units: GlucoseUnits = .mmolL
        @Published var dia: Decimal = 6
        @Published var maxBasal: Decimal = 4
        @Published var maxBolus: Decimal = 10
        @Published var allowAnnouncements: Bool = false
        @Published var backFillInterval: Decimal = 1 {
            didSet {
                let clamped = min(max(backFillInterval, 1), 90)
                if backFillInterval != clamped {
                    backFillInterval = clamped
                }
            }
        }

        @Published var uploadInterval: Decimal = 1 {
            didSet {
                let clamped = min(max(uploadInterval, 1), 90)
                if uploadInterval != clamped {
                    uploadInterval = clamped
                }
            }
        }

        @Published var cgmSupportsGlucoseUpload: Bool = false
        @Published var cgmEnablesGlucoseUpload: Bool = false
        @Published var cgmDisablesGlucoseUpload: Bool = false

        override func subscribe() async {
            url = keychain.getValue(String.self, forKey: Config.urlKey) ?? ""
            secret = keychain.getValue(String.self, forKey: Config.secretKey) ?? ""

            let settings = await settingsManager.settings
            let pumpSettings = await settingsManager.pumpSettings

            units = settings.units
            dia = pumpSettings.insulinActionCurve
            maxBasal = pumpSettings.maxBasal
            maxBolus = pumpSettings.maxBolus

            updatedShouldUploadGlucose()

            subscribeSetting(\.allowAnnouncements, on: $allowAnnouncements) { self.allowAnnouncements = $0 }
            subscribeSetting(\.isUploadEnabled, on: $isUploadEnabled) { self.isUploadEnabled = $0 }
            subscribeSetting(\.nightscoutFetchEnabled, on: $nightscoutFetchEnabled) { self.nightscoutFetchEnabled = $0 }

            uploadsPausedUntil = NightscoutUploadPause.pausedUntil
            watchForPauseExpiry()

            observeUI(appCoordinator.cgmInfo) { me, _ in
                me.updatedShouldUploadGlucose()
            }
            observeUI(appCoordinator.cgmStatus) { me, _ in
                me.updatedShouldUploadGlucose()
            }
        }

        var uploadsPaused: Bool {
            guard let uploadsPausedUntil else { return false }
            return uploadsPausedUntil > Date()
        }

        func pauseUploads(for duration: UploadPauseDuration) {
            setPause(until: Date.now.addingTimeInterval(duration.timeInterval))
        }

        func resumeUploads() {
            setPause(until: nil)
        }

        private func setPause(until: Date?) {
            NightscoutUploadPause.pausedUntil = until
            uploadsPausedUntil = until
        }

        /// Uploads resume on their own once the deadline passes, but the screen would keep claiming to be
        /// paused. Clearing the elapsed date both refreshes the UI and tidies the stored value away.
        private func watchForPauseExpiry() {
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard let self else { return }
                    if let until = uploadsPausedUntil, until <= Date() {
                        setPause(until: nil)
                    }
                }
            }.store(in: lifetime)
        }

        private func updatedShouldUploadGlucose() {
            guard let cgmInfo = appCoordinator.cgmInfo.value,
                  let cgmStatus = appCoordinator.cgmStatus.value
            else {
                cgmSupportsGlucoseUpload = false
                cgmEnablesGlucoseUpload = false
                cgmDisablesGlucoseUpload = false
                return
            }
            cgmSupportsGlucoseUpload = cgmInfo.glucoseUploadSupported
            cgmEnablesGlucoseUpload = cgmStatus.shouldUploadGlucose
            cgmDisablesGlucoseUpload = cgmInfo.glucoseUploadSupported && !cgmStatus.shouldUploadGlucose
        }

        func connect() {
            if let CheckURL = url.last, CheckURL == "/" {
                let fixedURL = url.dropLast()
                url = String(fixedURL)
            }
            guard let url = URL(string: url) else {
                message = "Invalid URL"
                return
            }
            connecting = true
            message = ""
            Task {
                do {
                    try await NightscoutAPI(url: url, secret: secret.isEmpty ? nil : secret).checkConnection()
                    self.message = "Connected!"
                    self.keychain.setValue(self.url, forKey: Config.urlKey)
                    self.keychain.setValue(self.secret, forKey: Config.secretKey)

                    appCoordinator.sendNightscoutConfigChanged()
                } catch {
                    self.message = "Error: \(error.localizedDescription)"
                }
                connecting = false
            }
        }

        private func readConcentration() async -> Double {
            await coreDataStorage.insulinConcentration().concentration
        }

        func importSettings() {
            Task {
                guard await nightscoutManager.isConfigured() else {
                    saveError("Can't access nightscoutAPI")
                    return
                }
                let pumpInfo = self.appCoordinator.pumpInfo.value

                let fetchedProfileStore: [FetchedNightscoutProfileStore]
                do {
                    fetchedProfileStore = try await self.nightscoutManager.fetchProfile()
                } catch let importError {
                    debug(.nightscout, "Error occured: " + importError.localizedDescription)
                    saveError("Error occurred: " + importError.localizedDescription)
                    return
                }

                guard let fetchedProfile: ScheduledNightscoutProfile = fetchedProfileStore.first?.store["default"]
                else {
                    saveError("\nCan't find the default Nightscout Profile.")
                    return
                }

                guard fetchedProfile.units.contains(self.units.rawValue.prefix(4)) else {
                    debug(
                        .nightscout,
                        "Mismatching glucose units in Nightscout and Pump Settings. Import settings aborted."
                    )
                    saveError("\nMismatching glucose units in Nightscout and Pump Settings. Import settings aborted.")
                    return
                }

                var areCRsOK = true
                let carbratios = fetchedProfile.carbratio
                    .map { carbratio -> CarbRatioEntry in
                        if carbratio.value <= 0 {
                            areCRsOK = false
                        }
                        return CarbRatioEntry(
                            start: carbratio.time,
                            offset: self.offset(carbratio.time) / 60,
                            ratio: carbratio.value
                        )
                    }
                let carbratiosProfile = CarbRatios(units: CarbUnit.grams, schedule: carbratios)
                guard areCRsOK else {
                    saveError(
                        "\nInvalid Carb Ratio settings in Nightscout.\n\nImport aborted. Please check your Nightscout Profile Carb Ratios Settings!"
                    )
                    return
                }

                var areBasalsOK = true
                let pumpName = pumpInfo?.name
                let basals = fetchedProfile.basal
                    .map { basal -> BasalProfileEntry in
                        if pumpName != "Omnipod DASH", basal.value <= 0
                        {
                            areBasalsOK = false
                        }
                        return BasalProfileEntry(
                            start: basal.time,
                            minutes: self.offset(basal.time) / 60,
                            rate: basal.value
                        )
                    }

                guard areBasalsOK else {
                    saveError(
                        "\nInvalid Nightcsout Basal Settings. Some or all of your basal settings are 0 U/h.\n\nImport aborted. Please check your Nightscout Profile Basal Settings before trying to import again. Import has been aborted.)"
                    )
                    return
                }

                // DASH pumps can have 0U/h basal rates but don't import if total basals (24 hours) amount to 0 U.
                if pumpName == "Omnipod DASH", basals.map({ each in each.rate }).reduce(0, +) <= 0 {
                    areBasalsOK = false
                }
                guard areBasalsOK else {
                    saveError(
                        "\nYour total Basal insulin amount to 0 U or lower in Nightscout Profile settings.\n\n Please check your Nightscout Profile Basal Settings before trying to import again. Import has been aborted.)"
                    )
                    return
                }

                let sensitivities = fetchedProfile.sens.map { sensitivity -> InsulinSensitivityEntry in
                    InsulinSensitivityEntry(
                        sensitivity: sensitivity.value,
                        offset: self.offset(sensitivity.time) / 60,
                        start: sensitivity.time
                    )
                }
                if sensitivities.filter({ $0.sensitivity <= 0 }).isNotEmpty {
                    saveError(
                        "\nInvalid Nightcsout Sensitivities Settings. \n\nImport aborted. Please check your Nightscout Profile Sensitivities Settings!"
                    )
                    return
                }

                let sensitivitiesProfile = InsulinSensitivities(
                    units: self.units,
                    userPreferredUnits: self.units,
                    sensitivities: sensitivities
                )

                let targets = fetchedProfile.target_low
                    .map { target -> BGTargetEntry in
                        BGTargetEntry(
                            low: target.value,
                            high: target.value,
                            start: target.time,
                            offset: self.offset(target.time) / 60
                        )
                    }

                let targetsProfile = BGTargets(
                    units: self.units,
                    userPreferredUnits: self.units,
                    targets: targets
                )

                // IS THERE A PUMP?
                guard pumpInfo != nil else {
                    await crScheduleStorage.updateCrSchedule(carbratiosProfile)
                    await basalProfileStorage.updateBasalProfile(basals)
                    await isfScheduleStorage.updateIsfSchedule(sensitivitiesProfile)
                    await bgTargetsScheduleStorage.updateBgTargetsSchedule(targetsProfile)
                    let error =
                        "Settings were imported but the Basals couldn't be saved to pump (No pump). Check your basal settings and tap ´Save on Pump´ to sync the new basal settings"
                    debug(.service, error)
                    saveError(error)
                    return
                }

                // SAVE TO STORAGE. SAVE TO PUMP (LoopKit)
                let concentration = await readConcentration()
                do {
                    if let adjustedBasals = try await deviceManager.syncBasalRateSchedule(
                        items: basals,
                        concentration: concentration
                    ) {
                        await self.basalProfileStorage.updateBasalProfile(adjustedBasals)
                    } else {
                        await self.basalProfileStorage.updateBasalProfile(basals)
                    }
                    await crScheduleStorage.updateCrSchedule(carbratiosProfile)
                    await isfScheduleStorage.updateIsfSchedule(sensitivitiesProfile)
                    await bgTargetsScheduleStorage.updateBgTargetsSchedule(targetsProfile)
                    debug(.service, "Settings have been imported and the Basals saved to pump!")
                    // DIA. Save if changed.
                    let dia = fetchedProfile.dia
                    if dia != self.dia, dia >= 0 {
                        let pumpSettings = PumpSettings(
                            insulinActionCurve: dia,
                            maxBolus: self.maxBolus,
                            maxBasal: self.maxBasal
                        )
                        await self.settingsManager.updatePumpSettings(pumpSettings)
                        debug(.nightscout, "DIA setting updated to " + dia.description + " after a NS import.")
                    }

                } catch {
                    let error =
                        "\nSettings were imported but the Basals couldn't be saved to pump (communication error). Check your basal settings and tap ´Save on Pump´ to sync the new basal settings"
                    saveError(error)
                    debug(.service, "Basals couldn't be save to pump: \(error)")
                }
            }
        }

        private func offset(_ string: String) -> Int {
            let hours = Int(string.prefix(2)) ?? 0
            let minutes = Int(string.suffix(2)) ?? 0
            return ((hours * 60) + minutes) * 60
        }

        private func saveError(_ string: String) {
            coredataContext.performAndWait {
                let saveToCoreData = ImportError(context: self.coredataContext)
                saveToCoreData.date = Date()
                saveToCoreData.error = string
                if coredataContext.hasChanges {
                    try? coredataContext.save()
                }
            }
        }

        func backfillGlucose() {
            guard !backfilling else { return }
            backfillKind = .glucose
            backfillPhase = .fetching
            backfillingProgress = 0.0
            backfillResult = nil
            Task {
                defer { backfillPhase = nil }
                let since = Date.now.subtractingTimeInterval(.days(backFillInterval))
                var fetched: FetchedGlucose?
                for await progress in await nightscoutManager.fetchGlucose(since: since) {
                    switch progress {
                    case let .progress(progress):
                        self.backfillingProgress = progress
                    case let .done(result):
                        fetched = result
                    }
                }
                guard let fetched else { return }
                // nothing to save: straight to the result
                guard fetched.glucose.isNotEmpty else {
                    backfillResult = Self.backfillMessage(fetched, CoreDataManager.GlucoseStoreOutcome())
                    return
                }

                backfillPhase = .saving
                backfillingProgress = 0.0
                let stored = await storeBackfilledGlucose(fetched.glucose)
                // the CGM of the readings no CGM session names, from the entries' device, over the days fetched
                let named = await backfillCGMs(fetched, since: since)
                backfillResult = [Self.backfillMessage(fetched, stored), named.flatMap(Self.cgmBackfillMessage)]
                    .compactMap { $0 }.filter(\.isNotEmpty).joined(separator: "\n")
            }
        }

        /// The CGM backfill (`NightscoutCGMBackfill.run`) over the glucose backfill's complete time, from the entries
        /// it fetched; nil when it didn't run (nothing fetched completely, Nightscout not reachable).
        private func backfillCGMs(_ fetched: FetchedGlucose, since: Date) async -> NightscoutCGMBackfillOutcome? {
            let from: Date
            switch fetched.failure {
            case .none: from = since
            case let .pageFailed(reached?, _): from = reached
            case .notConfigured,
                 .notReachable,
                 .pageFailed(nil, _): return nil
            }
            let now = Date()
            guard let window = NightscoutCGMBackfill.window(from: from, now: now),
                  let source = await nightscoutManager.cgmBackfillSource()
            else { return nil }
            let readings: [Date]
            do {
                readings = try await coreDataStorage.fetchGlucosePoints(from: window.start, to: window.end).map(\.time)
            } catch {
                return NightscoutCGMBackfillOutcome(failure: error.localizedDescription)
            }
            let sessions = await cgmSessionStore.sessions(in: DateInterval(start: .distantPast, end: .distantFuture))
            let entries = fetched.glucose.compactMap { glucose -> NightscoutCGMSessions.Entry? in
                guard glucose.type == GlucoseType.sgv.rawValue, let device = glucose.device else { return nil }
                return NightscoutCGMSessions.Entry(date: glucose.dateString, device: device)
            }
            let store = cgmSessionStore!
            return await NightscoutCGMBackfill.run(
                entries: entries,
                window: window,
                readings: readings,
                sessions: sessions,
                source: source,
                store: { await store.storeBackfilled($0, replacing: $1) }
            )
        }

        /// "Nightscout named the CGM of 120 of 400 readings without one"; nil when none were without one
        private static func cgmBackfillMessage(_ outcome: NightscoutCGMBackfillOutcome) -> String? {
            if let failure = outcome.failure {
                return String(
                    format: NSLocalizedString(
                        "Naming the CGMs failed: %@",
                        comment: "Glucose backfill result: the CGM backfill's error"
                    ),
                    failure
                )
            }
            guard outcome.unknown > 0 else { return nil }
            return String(
                format: NSLocalizedString(
                    "Nightscout named the CGM of %1$d of %2$d readings without one",
                    comment: "Glucose backfill result: the readings no CGM session covered, and those Nightscout named"
                ),
                outcome.named,
                outcome.unknown
            )
        }

        private func storeBackfilledGlucose(_ glucose: [BloodGlucose]) async -> CoreDataManager.GlucoseStoreOutcome {
            debug(.nightscout, "fetched \(glucose.count) glucose records from nightscout")

            // the last 24 hours first, into core data and glucose storage: the gap Home and the loop see is filled
            // at once, and kept if the rest is interrupted. Core data before glucose storage: the readings glucose
            // storage passes on to core data are then stored already, so the count is what this backfill inserted
            let cutOffDate = Date.now.subtractingTimeInterval(.hours(24))
            let recent = glucose.filter { $0.dateString >= cutOffDate }
            let older = glucose.filter { cutOffDate > $0.dateString }
            // of the progress: as the readings
            let recentShare = Double(recent.count) / Double(max(glucose.count, 1))

            var outcome = await coreDataManager.storeGlucose(recent) { [weak self] progress in
                self?.backfillingProgress = progress * recentShare
            }
            _ = await glucoseStorage.storeGlucose(recent)
            guard outcome.error == nil else { return outcome }

            let rest = await coreDataManager.storeGlucose(older) { [weak self] progress in
                self?.backfillingProgress = recentShare + progress * (1 - recentShare)
            }
            outcome.inserted += rest.inserted
            outcome.error = rest.error
            outcome.reached = rest.reached
            return outcome
        }

        private static func backfillMessage(_ fetched: FetchedGlucose, _ stored: CoreDataManager.GlucoseStoreOutcome) -> String {
            switch fetched.failure {
            case .notConfigured:
                return NSLocalizedString("Nightscout is not configured", comment: "Glucose backfill result")
            case .notReachable:
                return NSLocalizedString("No network connection", comment: "Glucose backfill result")
            case .none where fetched.glucose.isEmpty:
                return NSLocalizedString("Nightscout returned no readings", comment: "Glucose backfill result")
            case .none,
                 .pageFailed:
                var lines: [String] = []
                if fetched.glucose.isNotEmpty {
                    lines.append(
                        stored.inserted == 1 ?
                            NSLocalizedString("Imported 1 reading", comment: "Glucose backfill result") :
                            String(
                                format: NSLocalizedString("Imported %d readings", comment: "Glucose backfill result"),
                                stored.inserted
                            )
                    )
                }
                if let error = stored.error {
                    lines.append(
                        stopped(at: stored.reached, error) ??
                            String(format: NSLocalizedString("Saving failed: %@", comment: "Glucose backfill result"), error)
                    )
                }
                if case let .pageFailed(reached, error) = fetched.failure {
                    lines.append(
                        stopped(at: reached, error) ??
                            String(format: NSLocalizedString("Fetching failed: %@", comment: "Glucose backfill result"), error)
                    )
                }
                return lines.joined(separator: "\n")
            }
        }

        /// "Stopped at <date>: <error>"; nil without a date
        private static func stopped(at date: Date?, _ error: String) -> String? {
            guard let date else { return nil }
            return String(
                format: NSLocalizedString("Stopped at %@: %@", comment: "Glucose backfill result: date, error"),
                date.formatted(date: .abbreviated, time: .shortened),
                error
            )
        }

        /// The insulin backfill: the basal schedules first (the days are judged by the schedule then in effect), then
        /// the insulin records, in batches through the pump event store. Read-only GETs, nothing automatic.
        func backfillInsulin() {
            guard !backfilling else { return }
            backfillKind = .insulin
            backfillPhase = .fetching
            backfillingProgress = 0.0
            insulinBackfillResult = nil
            Task {
                defer { backfillPhase = nil }
                let since = Date.now.subtractingTimeInterval(.days(backFillInterval))
                var fetched: FetchedInsulin?
                for await progress in await nightscoutManager.fetchInsulin(since: since) {
                    switch progress {
                    case let .progress(progress):
                        self.backfillingProgress = progress
                    case let .done(result):
                        fetched = result
                    }
                }
                guard let fetched else { return }
                switch fetched.failure {
                case .notConfigured,
                     .notReachable:
                    insulinBackfillResult = Self.insulinBackfillMessage(InsulinBackfillOutcome(fetched: fetched))
                    return
                case .none,
                     .pageFailed:
                    break
                }

                backfillPhase = .saving
                backfillingProgress = 0.0
                // mapped off the main actor: tens of thousands of treatments for 90 days
                let prepared = await Task.detached(priority: .userInitiated) {
                    NightscoutInsulinBackfill(fetched: fetched)
                }.value
                debug(
                    .nightscout,
                    "insulin backfill: \(fetched.treatments.count) treatments -> \(prepared.records.count) records, " +
                        "\(prepared.schedules.count) basal schedules; \(fetched.sessionTreatments.count) Site Changes and " +
                        "Announcements" + (fetched.sessionsFailure.map { " (stopped early: \($0))" } ?? "")
                )

                var outcome = InsulinBackfillOutcome(fetched: fetched)
                outcome.records = prepared.records.count
                outcome.usableSchedules = prepared.schedules.count
                if fetched.schedulesFailure == nil {
                    outcome.schedules = await pumpEventStore.storeScheduleBackfill(prepared.schedules)
                }
                // an incomplete fetch (a page failed) stores the records of its complete time all the same, upserted by
                // identity (a re-run completes them); its sessions are built over `sessionsComplete` only (a failed
                // session query shortens it; none without one: `prepared.sessions` is nil), and are not built when
                // there are no records
                if prepared.records.isNotEmpty {
                    outcome.stored = await pumpEventStore.storeBackfill(prepared.records) { progress in
                        // the task holds the model already (as the phase's `defer` does)
                        self.backfillingProgress = progress
                    }
                    // the pump sessions from the Site Changes and alarms, after the records (their evidence). Only
                    // with records: a run that fetched no insulin has no evidence, and would replace the stored
                    // sessions of its window with none
                    if let sessions = prepared.sessions {
                        await pumpEventStore.storeNightscoutSessions(sessions)
                    }
                }
                insulinBackfillResult = Self.insulinBackfillMessage(outcome)
            }
        }

        /// What an insulin backfill did, for its result line.
        struct InsulinBackfillOutcome {
            let fetched: FetchedInsulin
            /// the records the treatments mapped to
            var records = 0
            var stored = PumpEventStore.BackfillOutcome()
            /// the basal schedules the profiles mapped to
            var usableSchedules = 0
            /// the schedules imported; nil: not stored (the fetch failed)
            var schedules: Result<Int, Error>?
        }

        static func insulinBackfillMessage(_ outcome: InsulinBackfillOutcome) -> String {
            let fetched = outcome.fetched
            var lines: [String] = []
            switch fetched.failure {
            case .notConfigured:
                return NSLocalizedString("Nightscout is not configured", comment: "Insulin backfill result")
            case .notReachable:
                return NSLocalizedString("No network connection", comment: "Insulin backfill result")
            case .none where outcome.records == 0:
                lines.append(NSLocalizedString("Nightscout returned no insulin", comment: "Insulin backfill result"))
            case .none,
                 .pageFailed:
                if outcome.records > 0 {
                    let imported = outcome.stored.inserted + outcome.stored.updated
                    lines.append(
                        imported == 1 ?
                            NSLocalizedString("Imported 1 insulin record", comment: "Insulin backfill result") :
                            String(
                                format: NSLocalizedString("Imported %d insulin records", comment: "Insulin backfill result"),
                                imported
                            )
                    )
                }
                if outcome.stored.recent > 0 {
                    lines.append(String(
                        format: NSLocalizedString(
                            "%d records from the last 24 h left out",
                            comment: "Insulin backfill result: records in the time the pump history file covers"
                        ),
                        outcome.stored.recent
                    ))
                }
                if outcome.stored.skipped > 0 {
                    lines.append(String(
                        format: NSLocalizedString(
                            "%d records skipped: iAPS has them",
                            comment: "Insulin backfill result: records inside the pump's own history"
                        ),
                        outcome.stored.skipped
                    ))
                }
                if let error = outcome.stored.error {
                    lines.append(
                        stopped(at: outcome.stored.reached, error) ??
                            String(format: NSLocalizedString("Saving failed: %@", comment: "Insulin backfill result"), error)
                    )
                }
                if case let .pageFailed(reached, error) = fetched.failure {
                    lines.append(
                        stopped(at: reached, error) ??
                            String(format: NSLocalizedString("Fetching failed: %@", comment: "Insulin backfill result"), error)
                    )
                }
            }

            if let error = fetched.schedulesFailure {
                lines.append(String(
                    format: NSLocalizedString("Fetching basal schedules failed: %@", comment: "Insulin backfill result"),
                    error
                ))
            } else {
                switch outcome.schedules {
                case .success where outcome.usableSchedules == 0:
                    lines.append(NSLocalizedString("No basal schedules in Nightscout", comment: "Insulin backfill result"))
                case let .success(count):
                    lines.append(String(
                        format: NSLocalizedString("Imported %d basal schedules", comment: "Insulin backfill result"),
                        count
                    ))
                case let .failure(error):
                    lines.append(String(
                        format: NSLocalizedString("Saving basal schedules failed: %@", comment: "Insulin backfill result"),
                        error.localizedDescription
                    ))
                case .none:
                    break
                }
            }
            return lines.joined(separator: "\n")
        }

        func uploadOldGlucose() {
            uploading = true
            uploadingProgress = 0.0

            Task {
                let since = Date.now.subtractingTimeInterval(.days(self.uploadInterval))
                let readings = await coreDataStorage.fetchGlucose(interval: since as NSDate)
                // each reading with its recorded CGM session's Nightscout device, as the live upload sends it
                let sessions = await cgmSessionStore.sessions(in: DateInterval(start: since, end: .distantFuture))
                    .filter { $0.source == .recorded }
                let bloodGlucose = readings.compactMap { reading in
                    let device = reading.date.flatMap { CGMSessionAttribution.device(at: $0, sessions) }
                    return Self.glucoseUpload(reading, device: device)
                }

                for await progress in await self.nightscoutManager.uploadOldGlucose(bloodGlucose: bloodGlucose) {
                    self.uploadingProgress = progress
                }
                self.uploading = false
            }
        }

        /// A stored reading as the live glucose upload sends it (`BloodGlucose.toNightscoutEntry`): a CGM reading as
        /// an sgv entry (no type: stored before the type was), a manual BG as an mbg entry; nil for the rest (an mbg
        /// came from Nightscout) and for a reading without a date or an id
        /// - Parameter device: the Nightscout `device` of the recorded CGM session covering it (`CGMSession.device`);
        ///   nil: none covers it, it is uploaded without one
        nonisolated static func glucoseUpload(_ reading: ReadingsSnapshot, device: String? = nil) -> BloodGlucose? {
            guard let date = reading.date,
                  let id = reading.id
            else {
                return nil
            }
            let glucose = BloodGlucose(
                _id: id,
                glucose: Int(reading.glucose),
                direction: nil,
                date: Decimal(Int(date.timeIntervalSince1970 * 1000)),
                dateString: date,
                noise: nil,
                type: reading.type ?? GlucoseType.sgv.rawValue,
                activationDate: nil,
                sessionStartDate: nil,
                transmitterID: nil,
                // a CGM reading's: a manual BG came from no CGM
                device: (reading.type ?? GlucoseType.sgv.rawValue) == GlucoseType.sgv.rawValue ? device : nil
            )
            return glucose.toNightscoutEntry != nil ? glucose : nil
        }

        func delete() {
            keychain.removeObject(forKey: Config.urlKey)
            keychain.removeObject(forKey: Config.secretKey)
            url = ""
            secret = ""
            appCoordinator.sendNightscoutConfigChanged()
        }
    }
}

enum UploadPauseDuration: Int, Identifiable, CaseIterable {
    case threeHours = 3
    case sixHours = 6
    case twelveHours = 12
    case twentyHours = 20

    var id: Int { rawValue }

    var timeInterval: TimeInterval { .hours(rawValue) }

    var displayName: String {
        switch self {
        case .threeHours: return NSLocalizedString("For 3 hours", comment: "Pause uploads duration")
        case .sixHours: return NSLocalizedString("For 6 hours", comment: "Pause uploads duration")
        case .twelveHours: return NSLocalizedString("For 12 hours", comment: "Pause uploads duration")
        case .twentyHours: return NSLocalizedString("For 20 hours", comment: "Pause uploads duration")
        }
    }
}
