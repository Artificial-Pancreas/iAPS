import Combine
import CoreData
import LibreTransmitter
import LoopKit
import LoopKitUI
import SwiftDate
import SwiftUI
import Swinject
import UIKit

extension Home {
    final class StateModel: BaseStateModel<Provider>, LifetimeOwner, UIBindingOwner {
        @Injected() private var apsManager: APSManager!
        @Injected() private var storage: TempTargetsStorage!
        @Injected() private var deviceManager: DeviceDataManager!
        @Injected() private var overrideManager: OverrideManager!
        @Injected() private var appUIState: AppUIState!
        @Injected() private var databaseManager: DatabaseManager!

        private let coreDataStorage = CoreDataStorage()
        @Injected() private var overrideStorage: OverrideStorage!

        let uiBindings = UIBindings()
        private(set) var filteredHours = 24

        @Published private(set) var settings: FreeAPSSettings?

        private var preferences: Preferences!
        private var pumpSettings: PumpSettings!
        private var pumpHistory: [PumpHistoryEvent]!
        private var cgmSensorDays: Double?

        @Published var uploadStats = false
        @Published var enactedSuggestion: Suggestion?
        @Published var recentGlucose: BloodGlucose?
        @Published var glucoseDelta: Int?
        @Published var closedLoop = false
        @Published var pumpSuspended = false
        @Published var statusTitle = ""
        @Published var tempRate: Decimal?
        @Published var tempTarget: TempTarget?
        @Published var setupPump = false
        @Published var eventualBG: Int?
        @Published var carbsRequired: Decimal?
        @Published var allowManualTemp = false
        @Published var animatedBackground = false
        @Published var maxValue: Decimal = 1.2
        @Published var totalBolus: Decimal = 0
        @Published var isStatusPopupPresented: Bool = false
        /// A published release newer than this build (from the daily version check), if any.
        @Published var newerVersion: String?
        @Published var showVersionBanner = false
        @Published var showVersionAlert = false
        let versionNumber = Bundle.main.releaseVersionNumber ?? ""
        @Published var useTargetButton: Bool = false
        @Published var overrideHistory: [OverrideHistorySnapshot] = []
        @Published private(set) var latestOverride: OverrideSnapshot?
        // preset of the active override (nil when the override is not an existing named preset)
        @Published private(set) var overridePreset: OverridePresetsSnapshot?
        // preset scheduled to start when the active override runs to completion
        @Published private(set) var succeedingPreset: OverridePresetsSnapshot?
        // autoisf flag of the active override's Auto_ISF record (nil when no active override / no record)
        @Published private(set) var overrideAutoISF: Bool?
        @Published var alwaysUseColors: Bool = false
        @Published var useCalc: Bool = true
        @Published var hours: Int = 6
        @Published var iobData: [IOBData] = []
        @Published var displayDelta: Bool = false
        @Published var maxIOB: Decimal = 0
        @Published var maxCOB: Decimal = 0
        @Published var autoisf = false
        @Published var displayExpiration = false
        @Published var displaySAGE = true
        @Published var sensorDays: Double = 10
        @Published var carbButton: Bool = true
        @Published var profileButton: Bool = true
        @Published var ai: Bool = false

        /// the cards' menu picks, on the phone (UI-only, not in the settings)
        private let displayPreferences: StatsDisplayPreferences

        // the stats bar's range, picked on a long-press (`select(homeStatsRange:)`): what its header shows and its tap
        // opens Statistics on; the bar itself follows its config (`homeStatsConfig`). The other cards have no range: the
        // Loops card the last 24 h (`Home.loopsRange`), the insulin and meal cards Today
        @Published private(set) var homeStatsRange: StatsPeriod
        /// the stats bar's "Show TITR" (`showHomeStatsTITR`): drawn from the bar's result, no read of its own
        @Published private(set) var homeStatsTITR: Bool

        // the On board card, the last 24 h (no range of its own): its long-press menu's lanes (`showOnBoardGlucose`,
        // `showOnBoardCOB`)
        @Published private(set) var homeOnBoardGlucose: Bool
        @Published private(set) var homeOnBoardCOB: Bool
        /// as of its last build (`refreshOnBoard`); nil without the IOB rows (more than 3 in its window)
        @Published private(set) var homeOnBoard: HomeOnBoardCard.Content?
        /// the last `reasons` read (`setupData`): the last 24 h and the 7.5 min before them; nil before the first
        private var onBoardRows: [IOBData]?
        /// the `reasons` reads started (`setupData`) and the newest one of them applied: a loop's and its suggestion's
        /// read run at once, a read landing after a newer one is dropped
        private var reasonsReadsStarted = 0
        private var reasonsReadApplied = 0

        // the stats bar
        /// the latest result for `homeStatsConfig`: the range's read with the GMI line's latest; nil until the range's
        /// first read
        @Published private(set) var homeStats: HomeStatsSnapshot?
        /// the range and the settings the bar is computed for; nil until the settings are delivered
        private var homeStatsConfig: StatsConfig?
        /// the bar's part of the settings (`homeStatsConfig`); nil until they are delivered
        private var homeStatsSettings: Stat.StatsSettings?
        /// the range's latest read and its config: the GMI line's read lands beside it (`publishHomeStats`)
        private var homeStatsRangeResult: (summary: GlucoseSummary, config: StatsConfig)?
        /// the GMI line's latest read (`Home.gmiPeriod`), kept up to the next one lands; nil until the first one: no
        /// line meanwhile
        private var homeStatsGMI: GlucoseSummary?
        /// the range's read in flight: at most one, plus `homeStatsPending`
        private var homeStatsTask: Task<Void, Never>?
        /// a range read was asked for while one was in flight: it runs when that one is done, with the config of then
        private var homeStatsPending = false
        /// the GMI line's read in flight (the slow one, 90 d): at most one, plus `homeStatsGMIPending`; apart from the
        /// range's, so the range's result doesn't wait for it
        private var homeStatsGMITask: Task<Void, Never>?
        /// a GMI read was asked for while one was in flight: it runs when that one is done, with the bands of then
        private var homeStatsGMIPending = false
        /// a refresh was asked for in the background (or the app went there): `didBecomeActive` makes it (both reads)
        private var homeStatsAwaitsForeground = false

        // the Loops card, the last 24 h (`Home.loopsRange`)
        /// the latest result, as of its read; nil until the first one (a failed read keeps it)
        @Published private(set) var homeLoops: HomeLoopsCard.Content?
        /// the newest loop start of the result `homeLoops` shows (`HomeLoopStats.newestStart`): whether a reading
        /// changes it before the next loop (`homeLoopsReadingsChanged`)
        private var homeLoopsNewestStart: Date?
        /// the 1-minute loop, from the settings; nil until they are delivered
        private var homeLoopsConfig: LoopsConfig?
        /// the refresh in flight: at most one, plus `homeLoopsPending`
        private var homeLoopsTask: Task<Void, Never>?
        /// a refresh was asked for while one was in flight: it runs when that one is done, with the config of then
        private var homeLoopsPending = false
        /// a refresh was asked for in the background (or the app went there): `didBecomeActive` makes it
        private var homeLoopsAwaitsForeground = false
        /// a failed read's retry, in a minute
        private var homeLoopsRetry: Task<Void, Never>?

        // the meal card, Today (no range of its own)
        /// the latest result, as of its read; nil until the first one (a failed read keeps it)
        @Published private(set) var homeMeals: HomeMealsCard.Content?
        /// the settings were delivered: the first read's trigger
        private var homeMealsStarted = false
        /// the refresh in flight: at most one, plus `homeMealsPending`
        private var homeMealsTask: Task<Void, Never>?
        /// a refresh was asked for while one was in flight: it runs when that one is done
        private var homeMealsPending = false
        /// a refresh was asked for in the background (or the app went there): `didBecomeActive` makes it
        private var homeMealsAwaitsForeground = false
        /// a failed read's retry, in a minute
        private var homeMealsRetry: Task<Void, Never>?

        // the insulin card, Today (no range of its own)
        /// the latest result, as of its read (each day's insulin and the usual by the read's time): it changes only with
        /// a read; nil until the first one (a failed read keeps it)
        @Published private(set) var homeInsulin: HomeInsulinCard.Content?
        /// the settings were delivered: the first read's trigger
        private var homeInsulinStarted = false
        /// the read in flight: at most one, plus `homeInsulinPending`
        private var homeInsulinTask: Task<Void, Never>?
        /// a refresh was asked for while one was in flight: it runs when that one is done
        private var homeInsulinPending = false
        /// a refresh was asked for in the background (or the app went there): `didBecomeActive` makes it
        private var homeInsulinAwaitsForeground = false
        /// a failed read's retry, in a minute
        private var homeInsulinRetry: Task<Void, Never>?
        /// the newest `insulinStatsChanged` the last read read (its `seq` when it started): a change at or below it is
        /// skipped (the observer delivers the current change again after the background, where `didBecomeActive` reads)
        private var homeInsulinReadSeq = 0

        // Chart data
        var data = ChartModel(
            suggestion: nil,
            glucose: [],
            rawGlucose: [],
            activity: [],
            cob: [],
            isManual: [],
            tempBasals: [],
            boluses: [],
            suspensions: [],
            announcement: [],
            loopEvents: [],
            loopGaps: [],
            loopEventsPlacement: .top,
            hours: 24,
            maxBasal: 4,
            autotunedBasalProfile: [],
            basalProfile: [],
            tempTargets: [],
            carbs: [],
            units: .mmolL,
            smooth: false,
            highGlucose: 200,
            lowGlucose: 60,
            displayXgridLines: true,
            displayYgridLines: true,
            thresholdLines: true,
            latestOverride: nil,
            overrideHistory: [],
            minimumSMB: 0,
            insulinDIA: 7,
            insulinPeak: 75,
            maxBolus: 0,
            maxBolusValue: 1,
            maxCarbsValue: 1,
            maxIOB: 0,
            useInsulinBars: true,
            screenHours: 6,
            fpus: true,
            fpuAmounts: false,
            showInsulinActivity: false,
            showCobChart: false,
            secondaryChartBackdrop: true,
            inRangeAreaFill: false,
            chartGlucosePeaks: false,
            insulinActivityGridLines: true,
            insulinActivityLabels: true,
            yGridLabels: true,
            showPredictionsLegend: true,
            hidePredictions: false,
            useCarbBars: false
        )

        /// - Parameter displayPreferences: the cards' menu picks; tests pass their own `UserDefaults`
        init(resolver: Resolver, displayPreferences: StatsDisplayPreferences = StatsDisplayPreferences()) {
            self.displayPreferences = displayPreferences
            homeStatsRange = displayPreferences.homeStatsRange
            homeStatsTITR = displayPreferences.homeStatsTITR
            homeOnBoardGlucose = displayPreferences.homeOnBoardGlucose
            homeOnBoardCOB = displayPreferences.homeOnBoardCOB
            super.init(resolver: resolver)
        }

        override func subscribe() async {
            let fetchedSettings = await settingsManager.settings
            settings = fetchedSettings
            pumpSettings = await settingsManager.pumpSettings
            preferences = await settingsManager.preferences

            basalProfileUpdated(appCoordinator.basalProfile.value)
            autotuneUpdated(appCoordinator.autotune.value)

            pumpHistory = appCoordinator.pumpHistory.value.reversed()

            cgmSensorDays = appCoordinator.cgmStatus.value?.sensorDays

            tempTargetsUpdated(appCoordinator.tempTargets.value)

            await readFromSettings(fetchedSettings)
            readFromPreferences()
            readFromPumpSettings()

            setupBasals()
            setupBoluses()
            setupSuspensions()

            setupCarbs(appCoordinator.carbHistory.value)
            await setupAnnouncements()
            data.loopEvents = appCoordinator.loopEvents.value
            data.loopGaps = appCoordinator.loopGaps.value

            setupCob()

            data.suggestion = appCoordinator.suggested.value
            enactedSuggestion = appCoordinator.latestLoopOutcome.value?.enactedSuggestion

            carbsRequired = data.suggestion?.carbsReq

            setStatusTitle()
            refreshCurrentTempTarget()

            // before the awaits below, so the first summary is computed meanwhile
            subscribeHomeStats()
            subscribeHomeLoops()
            subscribeHomeMeals()
            subscribeHomeInsulin()
            subscribeHomeOnBoard()

            await setupOverrideHistory()
            await setupData()

            observeUI(appCoordinator.cgmStatus, map: { $0?.sensorDays }) { me, sensorDays in
                await me.cgmCensorDaysUpdated(sensorDays)
            }

            // refreshVersionNotice() runs from the view's onAppear, after the build-expiration check,
            // so on a cold launch the version alert is never flagged ahead of the expiration alert.
            // A check stored later (the loop path's daily slot) comes back through this subject.
            observeUI(appCoordinator.versionCheckStored, dropInitial: true) { me, _ in
                await me.versionCheckDidStore()
            }

            observeUI(
                appCoordinator.glucoseSmoothed,
                map: { $0.map { [$0.dateString.timeIntervalSince1970, Double($0.glucose)] } }
            ) { me, _ in
                await me.glucoseDidUpdate()
            }

            observeUI(appCoordinator.suggested) { me, suggestion in
                await me.suggestionDidUpdate(suggestion)
            }

            observeUI(appCoordinator.settings) { me, settings in
                await me.settingsUpdated(settings)
            }

            observeUI(appCoordinator.preferences) { me, preferences in
                await me.preferencesUpdated(preferences)
            }

            observeUI(appCoordinator.pumpSettings) { me, pumpSettings in
                await me.pumpSettingsUpdated(pumpSettings)
            }

            observeUI(appCoordinator.pumpHistory) { me, pumpHistory in
                await me.pumpHistoryDidUpdate(pumpHistory)
            }

            observeUI(appCoordinator.basalProfile) { me, basalProfile in
                me.basalProfileUpdated(basalProfile)
            }

            observeUI(appCoordinator.insulinActivity) { me, activity in
                me.data.activity = activity
            }

            observeUI(appCoordinator.autotune) { me, autotune in
                me.autotuneUpdated(autotune)
            }

            // not `==` (createdAt only): an edit in Nightscout keeps created_at and changes the duration
            observeUI(appCoordinator.tempTargets, isDuplicate: { TempTarget.identical($0, $1) }) { me, tempTargets in
                me.tempTargetsUpdated(tempTargets)
            }

            observeUI(appCoordinator.carbHistory) { me, carbHistory in
                await me.carbsUpdated(carbHistory)
            }

            observeUI(appCoordinator.loopEvents) { me, loopEvents in
                me.data.loopEvents = loopEvents
            }

            observeUI(appCoordinator.loopGaps) { me, loopGaps in
                me.data.loopGaps = loopGaps
            }

            observeUI(appCoordinator.latestLoopOutcome) { me, loopOutcome in
                guard let loopOutcome else { return }
                await me.loopCompleted(loopOutcome)
            }

            observeUI(appCoordinator.overridesChanged, dropInitial: true) { me, _ in
                await me.setupOverrideHistory()
            }

            subscribeSetting(\.hours, on: $hours) {
                let value = max(min($0, 24), 2)
                self.hours = value
                self.data.screenHours = value
            }

            observe(notification: UIApplication.didBecomeActiveNotification) { me in
                await me.refreshCurrentTempTarget()
            }

            observeUI(appCoordinator.pumpStatus) { me, pumpStatus in
                await me.pumpStatusUpdated(pumpStatus)
            }

            observeUI(appCoordinator.pumpInfo) { me, pumpInfo in
                await me.pumpInfoUpdated(pumpInfo)
            }

            $setupPump
                .sink { [weak self] show in
                    guard let self = self else { return }
                    guard show, let pumpInfo = appUIState.pumpInfo else {
                        self.router.mainSecondaryModalView.send(nil)
                        return
                    }
                    if pumpInfo.isOnboarded {
                        let view = PumpConfig.PumpSettingsView(
                            deviceManager: self.deviceManager,
                            completionDelegate: self,
                        ).asAny()
                        self.router.mainSecondaryModalView.send(view)
                    } else {
                        self.router.mainSecondaryModalView.send(nil)
                        self.showModal(for: .pumpConfig)
                    }
                }
                .store(in: lifetime)
        }

        private func settingsUpdated(_ settings: FreeAPSSettings) async {
            self.settings = settings
            await readFromSettings(settings)
            updateSensorDays()
            // TODO: are these needed here?
            await setupOverrideHistory()
            await setupData()
        }

        private func preferencesUpdated(_ preferences: Preferences) async {
            self.preferences = preferences
            readFromPreferences()
        }

        private func pumpSettingsUpdated(_ pumpSettings: PumpSettings) async {
            self.pumpSettings = pumpSettings
            readFromPumpSettings()
        }

        private func cgmCensorDaysUpdated(_ sensorDays: Double?) async {
            cgmSensorDays = sensorDays
            updateSensorDays()
        }

        private func pumpStatusUpdated(_ pumpStatus: PumpDisplayStatus?) async {
            if pumpStatus == nil {
                setupPump = false
            }
        }

        private func pumpInfoUpdated(_ pumpInfo: PumpDisplayInfo?) async {
            if pumpInfo == nil {
                setupPump = false
            }
        }

        private func updateSensorDays() {
            guard let settings else { return }
            sensorDays = cgmSensorDays ?? settings.sensorDays
        }

        func addCarbs() {
            showModal(for: .addCarbs(override: false, mode: .meal))
        }

        func runLoop() {
            provider.heartbeatNow()
        }

        func cancelBolus() {
            Task {
                await apsManager.cancelBolus()
            }
        }

        /// Asks the pump manager, not the published pump status: time-based pump managers (Omnipod, Minimed)
        /// don't report the end of a bolus, so the published status can stay "bolusing" until the next pump command.
        func pumpIsBolusing() -> Bool {
            deviceManager.currentPumpStatus()?.isBolusing ?? false
        }

        /// Recomputes the banner/alert from the stored version check. Called when Home comes up
        /// and when the app returns to the foreground; a check stored by the loop path arrives
        /// through `appCoordinator.versionCheckStored`, so nothing here runs on the loop path.
        ///
        /// A stored check older than 23 h is refreshed right away rather than waiting for the
        /// loop's slot; DatabaseManager.fetchVersion allows one attempt an hour, success or not.
        func refreshVersionNotice() {
            Task {
                let stored = await coreDataStorage.fetchVersion()
                applyVersionNotice(stored)
                if (stored?.date ?? .distantPast) < Date.now.subtractingTimeInterval(.hours(23)) {
                    // A new row, if the fetch succeeds, comes back through versionCheckStored.
                    await databaseManager.fetchVersion()
                }
            }
        }

        private func versionCheckDidStore() async {
            applyVersionNotice(await coreDataStorage.fetchVersion())
        }

        private func applyVersionNotice(_ stored: VNrSnapshot?) {
            let defaults = UserDefaults.standard
            guard let main = stored?.nr, !main.isEmpty else {
                newerVersion = nil
                showVersionBanner = false
                showVersionAlert = false
                return
            }
            let offered = Version(main: main, dev: stored?.dev ?? "")
                .offered(for: versionNumber, branch: Version.runningBranchName)
            newerVersion = offered
            showVersionBanner = offered != nil && defaults.string(forKey: IAPSconfig.versionBannerDismissed) != offered
            if let offered {
                if defaults.string(forKey: IAPSconfig.versionAlertShown) != offered {
                    showVersionAlert = true
                }
            } else {
                showVersionAlert = false
            }
        }

        func acknowledgeVersionAlert() {
            if let offered = newerVersion {
                UserDefaults.standard.set(offered, forKey: IAPSconfig.versionAlertShown)
            }
            showVersionAlert = false
        }

        func dismissVersionBanner() {
            if let offered = newerVersion {
                UserDefaults.standard.set(offered, forKey: IAPSconfig.versionBannerDismissed)
            }
            showVersionBanner = false
        }

        func cancelActiveOverride() {
            Task {
                await overrideManager.cancelActiveOverride()
                await setupOverrideHistory()
            }
        }

        func cancelTempTarget() {
            Task {
                await storage.cancelTempTarget()
            }
        }

        private func setupGlucose() {
            let rawGlucose = provider.rawGlucose(hours: filteredHours)

            data.isManual = provider.manualGlucose(hours: filteredHours)
            // the chart draws the smoothed series + raw values on top
            data.glucose = provider.smoothedGlucose(hours: filteredHours)
            data.rawGlucose = rawGlucose

            recentGlucose = rawGlucose.last
            if rawGlucose.count >= 2 {
                glucoseDelta = rawGlucose[rawGlucose.count - 1].glucose - rawGlucose[rawGlucose.count - 2].glucose
            } else {
                glucoseDelta = nil
            }
            // the readings, or the bands and the units (`readFromSettings`)
            refreshOnBoard()
        }

        private func setupBasals() {
            data.tempBasals = pumpHistory.filter {
                $0.type == .tempBasal || $0.type == .tempBasalDuration
            }
            let lastTempBasal = Array(data.tempBasals.suffix(2))
            guard lastTempBasal.count == 2 else {
                tempRate = nil
                return
            }

            guard let lastRate = lastTempBasal[0].rate, let lastDuration = lastTempBasal[1].durationMin else {
                tempRate = nil
                return
            }
            let lastDate = lastTempBasal[0].timestamp
            guard Date().timeIntervalSince(lastDate.addingTimeInterval(.minutes(lastDuration))) < 0 else {
                tempRate = nil
                return
            }
            tempRate = lastRate
        }

        private func setupBoluses() {
            data.boluses = pumpHistory.filter {
                $0.type == .bolus
            }
            data.maxBolusValue = data.boluses.compactMap(\.amount).max() ?? 1
        }

        private func setupSuspensions() {
            data.suspensions = pumpHistory.filter {
                $0.type == .pumpSuspend || $0.type == .pumpResume
            }

            let last = data.suspensions.last
            let tbr = data.tempBasals.first { $0.timestamp > (last?.timestamp ?? .distantPast) }

            // TODO: should we read this from the pump manager instead?
            pumpSuspended = tbr == nil && last?.type == .pumpSuspend
        }

        private func setupCob() {
            data.cob = iobData
        }

        private func readFromPumpSettings() {
            data.maxBasal = pumpSettings.maxBasal
            data.maxBolus = pumpSettings.maxBolus
            data.insulinDIA = pumpSettings.insulinActionCurve
        }

        private func setupCarbs(_ carbHistory: [CarbsEntry]) {
            data.carbs = carbHistory.filter { $0.carbs > 0 }
            data.maxCarbsValue = data.carbs.compactMap(\.carbs).max() ?? 1
        }

        private func setupOverrideHistory() async {
            overrideHistory = await provider.overrideHistory()
            let latestOverride = await overrideStorage.fetchCurrentActiveOverride()
            self.latestOverride = latestOverride
            data.latestOverride = latestOverride
            data.overrideHistory = overrideHistory

            if let latestOverride {
                if latestOverride.isPreset {
                    // a nameless preset counts as not found (mimics the old `name != ""` fetch predicate)
                    let preset = await overrideStorage.fetchOverridePreset(id: latestOverride.id)
                    overridePreset = (preset?.name?.isEmpty ?? true) ? nil : preset
                } else {
                    overridePreset = nil
                }
                overrideAutoISF = latestOverride.overrideAutoISF ? latestOverride.aisf?.autoisf : nil
            } else {
                overridePreset = nil
                overrideAutoISF = nil
            }

            if let latestOverride, latestOverride.succeedingStart != nil, let id = latestOverride.succeeding {
                succeedingPreset = await overrideStorage.fetchOverridePreset(id: id)
            } else {
                succeedingPreset = nil
            }
            data.succeedingOverride = succeedingPreset
        }

        private func setupAnnouncements() async {
            data.announcement = await provider.announcement(filteredHours)
        }

        private static let dateFormatter = {
            let dateFormatter = DateFormatter()
            dateFormatter.timeStyle = .short
            return dateFormatter
        }()

        private func setStatusTitle() {
            guard let suggestion = data.suggestion else {
                statusTitle = NSLocalizedString("No suggestion", comment: "Status title when there is no suggestion")
                return
            }

            if closedLoop,
               let enactedSuggestion,
               let timestamp = enactedSuggestion.timestamp,
               enactedSuggestion.deliverAt == suggestion.deliverAt, enactedSuggestion.recieved == true
            {
                statusTitle = NSLocalizedString("Enacted at", comment: "Headline in enacted pop up") + " " + Self.dateFormatter
                    .string(from: timestamp)
            } else if let suggestedDate = suggestion.deliverAt {
                statusTitle = NSLocalizedString("Suggested at", comment: "Headline in suggested pop up") + " " + Self
                    .dateFormatter
                    .string(from: suggestedDate)
            } else {
                statusTitle = "Suggested"
            }

            eventualBG = suggestion.eventualBG
        }

        private var tempTargetBoundaryTask: Task<Void, Never>?

        func refreshCurrentTempTarget() {
            updateCurrentTempTarget(appCoordinator.tempTargets.value)
        }

        /// update the active temp target
        /// schedule an update on temp target activation/expiry
        /// `tempTargets`: newest->oldest (as published by the temp targets storage)
        private func updateCurrentTempTarget(_ tempTargets: [TempTarget]) {
            tempTargetBoundaryTask?.cancel()
            tempTargetBoundaryTask = nil

            let now = Date()
            let newest = tempTargets.first
            let current = newest.flatMap { $0.isActive(at: now) ? $0 : nil }
            // the header shows the end time: a changed duration must reach it, `!=` compares only createdAt
            if !TempTarget.identical(tempTarget, current) {
                tempTarget = current
            }

            guard let newest, newest.duration != 0 else { return }
            let boundary = now < newest.createdAt ? newest.createdAt : newest.endDate
            guard boundary > now else { return }

            tempTargetBoundaryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(boundary.timeIntervalSinceNow))
                guard !Task.isCancelled else { return }
                self?.refreshCurrentTempTarget()
            }
        }

        // MARK: - Stats bar

        /// The stats bar's triggers (its range and the GMI line's 90 d, two reads). The settings' first delivery
        /// makes the first refresh; then new, backfilled, deleted or recalibrated readings, a wipe and a time zone change
        /// (`glucoseStatsChanged` comes after the save and the cache invalidation, never `glucoseSmoothed`: that one comes
        /// before the save), and midnight and DST. Nothing is clock-driven: the numbers are as of the last read (a
        /// stalled CGM shows the numbers of its last reading's read). Nothing runs in the background: a refresh asked
        /// for there (or the background itself) waits for the foreground, where `didBecomeActive` is the one trigger
        /// (the observers' foreground replay is held back).
        private func subscribeHomeStats() {
            observeUI(appCoordinator.settings, map: { Stat.StatsSettings($0) }) { me, settings in
                me.homeStatsSettings = settings
                me.homeStatsConfigChanged()
            }
            observeUI(appCoordinator.glucoseStatsChanged, dropInitial: true) { me, _ in
                me.refreshHomeStats()
            }
            // midnight, DST, a time zone change
            observe(notification: UIApplication.significantTimeChangeNotification) { me in
                await me.refreshHomeStats()
            }
            observe(notification: UIApplication.didEnterBackgroundNotification) { me in
                await me.homeStatsEnteredBackground()
            }
            observe(notification: UIApplication.didBecomeActiveNotification) { me in
                await me.homeStatsBecameActive()
            }
        }

        /// The range or the stats settings changed (or were delivered for the first time). The GMI line is read again
        /// only for other bands (the HbA1c unit is formatting, `publishHomeStats`): not for another range.
        private func homeStatsConfigChanged() {
            guard let settings = homeStatsSettings else { return }
            let config = StatsConfig(range: homeStatsRange, settings: settings)
            guard config != homeStatsConfig else { return }
            let bandsChanged = config.settings.bands != homeStatsConfig?.settings.bands
            homeStatsConfig = config
            refreshHomeStatsRange()
            if bandsChanged {
                refreshHomeStatsGMI()
            }
        }

        /// The stats bar's long-press menu: Today or 24 h, kept on the phone; the bar reads it.
        func select(homeStatsRange range: StatsPeriod) {
            guard range != homeStatsRange, StatsPeriod.homeStatsRanges.contains(range) else { return }
            homeStatsRange = range
            displayPreferences.homeStatsRange = range
            homeStatsConfigChanged()
        }

        /// The stats bar's long-press menu: "Show TITR", kept on the phone.
        func showHomeStatsTITR(_ shown: Bool) {
            guard shown != homeStatsTITR else { return }
            homeStatsTITR = shown
            displayPreferences.homeStatsTITR = shown
        }

        /// The On board card's long-press menu: its glucose lane, kept on the phone.
        func showOnBoardGlucose(_ shown: Bool) {
            guard shown != homeOnBoardGlucose else { return }
            homeOnBoardGlucose = shown
            displayPreferences.homeOnBoardGlucose = shown
        }

        /// The On board card's long-press menu: its carbs-on-board lane, kept on the phone.
        func showOnBoardCOB(_ shown: Bool) {
            guard shown != homeOnBoardCOB else { return }
            homeOnBoardCOB = shown
            displayPreferences.homeOnBoardCOB = shown
        }

        /// Recomputes the stats bar: its range and the GMI line, each read at once, after its read in flight (once,
        /// however often it is asked for meanwhile, with the config of then), or in the background not at all
        /// (`didBecomeActive` does it). The range's result is shown as soon as it lands, the GMI line added or updated
        /// when its own (90 d, slower) lands.
        func refreshHomeStats() {
            refreshHomeStatsRange()
            refreshHomeStatsGMI()
        }

        /// held back up to didBecomeActive, also in the inactive moment before it (the observers' foreground replay)
        private func homeStatsHeldBack() -> Bool {
            guard homeStatsAwaitsForeground || UIApplication.shared.applicationState == .background else { return false }
            homeStatsAwaitsForeground = true
            return true
        }

        /// One at a time: a call already running in the service can't be stopped, so a slow result must not be able to
        /// land after a newer one.
        private func refreshHomeStatsRange() {
            guard homeStatsConfig != nil, !homeStatsHeldBack() else { return }
            guard homeStatsTask == nil else {
                homeStatsPending = true
                return
            }
            startHomeStatsRefresh()
        }

        /// One at a time, as the range's.
        private func refreshHomeStatsGMI() {
            guard homeStatsConfig != nil, !homeStatsHeldBack() else { return }
            guard homeStatsGMITask == nil else {
                homeStatsGMIPending = true
                return
            }
            startHomeStatsGMIRefresh()
        }

        private func startHomeStatsRefresh() {
            guard let config = homeStatsConfig else { return }
            homeStatsPending = false
            let provider = self.provider
            homeStatsTask = Task { [weak self] in
                let summary = await provider.glucoseSummary(config.range, bands: config.settings.bands)
                guard let self else { return }
                self.homeStatsTask = nil
                // a newer request (a reading, the settings, midnight) replaces this result at once
                guard !self.homeStatsPending else {
                    self.refreshHomeStatsRange()
                    return
                }
                guard config == self.homeStatsConfig else { return }
                self.homeStatsRangeResult = (summary, config)
                self.publishHomeStats()
            }
        }

        /// The GMI line's 90 d: a read of its own (complete days from the service's day cache).
        private func startHomeStatsGMIRefresh() {
            guard let bands = homeStatsConfig?.settings.bands else { return }
            homeStatsGMIPending = false
            let provider = self.provider
            homeStatsGMITask = Task { [weak self] in
                let gmi = await provider.glucoseSummary(Home.gmiPeriod, bands: bands)
                guard let self else { return }
                self.homeStatsGMITask = nil
                // a newer request replaces this result at once
                guard !self.homeStatsGMIPending else {
                    self.refreshHomeStatsGMI()
                    return
                }
                guard bands == self.homeStatsConfig?.settings.bands else { return }
                self.homeStatsGMI = gmi
                self.publishHomeStats()
            }
        }

        /// The range's latest read with the GMI line's latest (none before its first read), in the range's config;
        /// nothing before the range's first read.
        private func publishHomeStats() {
            guard let range = homeStatsRangeResult else { return }
            let snapshot = HomeStatsSnapshot(
                range.summary,
                gmi: homeStatsGMI,
                period: range.config.range,
                settings: range.config.settings
            )
            if snapshot != homeStats {
                homeStats = snapshot
            }
        }

        /// The time went on in the background: the foreground refreshes.
        private func homeStatsEnteredBackground() {
            // the notification comes asynchronously: nothing to do when the app is back already
            guard UIApplication.shared.applicationState == .background else { return }
            homeStatsAwaitsForeground = true
        }

        /// The one foreground trigger: only back from the background (or after a refresh held back), not after
        /// Control Center, a system alert or Face ID, which don't change the numbers.
        private func homeStatsBecameActive() {
            guard homeStatsAwaitsForeground else { return }
            homeStatsAwaitsForeground = false
            refreshHomeStats()
        }

        // MARK: - Loops card

        /// The Loops card's triggers, as the stats bar's (`subscribeHomeStats`): the settings' first delivery makes the
        /// first refresh, then a change of the 1-minute loop, every loop (`loopCompleted`: the readings before it too),
        /// the readings changing while no loop comes (`glucoseStatsChanged`, only for the ongoing gap:
        /// `homeLoopsReadingsChanged`), and midnight and DST.
        /// Nothing is clock-driven: the card is as of its last read, an ongoing gap up to that read (the header shows the
        /// loop status). The one timer is a failed read's retry. Nothing runs in the background: a refresh asked for
        /// there waits for the foreground, where `didBecomeActive` is the one trigger.
        private func subscribeHomeLoops() {
            observeUI(appCoordinator.settings, map: { LoopsConfig($0) }) { me, config in
                me.homeLoopsConfigChanged(config)
            }
            observeUI(appCoordinator.glucoseStatsChanged, dropInitial: true) { me, _ in
                me.homeLoopsReadingsChanged()
            }
            // midnight, DST, a time zone change
            observe(notification: UIApplication.significantTimeChangeNotification) { me in
                await me.refreshHomeLoops()
            }
            observe(notification: UIApplication.didEnterBackgroundNotification) { me in
                await me.homeLoopsEnteredBackground()
            }
            observe(notification: UIApplication.didBecomeActiveNotification) { me in
                await me.homeLoopsBecameActive()
            }
        }

        /// The 1-minute loop changed (or was delivered for the first time).
        private func homeLoopsConfigChanged(_ config: LoopsConfig) {
            guard config != homeLoopsConfig else { return }
            homeLoopsConfig = config
            refreshHomeLoops()
        }

        /// The readings changed: the next loop reads them (a loop follows every reading), so read now only when they can
        /// change the card before it, the ongoing gap (`HomeLoopsCard.Content.readingMayChange`), or without a result.
        private func homeLoopsReadingsChanged() {
            guard homeLoops == nil || HomeLoopsCard.Content.readingMayChange(newestStart: homeLoopsNewestStart, now: Date())
            else { return }
            refreshHomeLoops()
        }

        /// Recomputes the Loops card: at once, after the refresh in flight (once, with the config of then), or in the
        /// background not at all (`didBecomeActive` does it). One at a time, as the stats bar's.
        func refreshHomeLoops() {
            guard homeLoopsConfig != nil else { return }
            cancelHomeLoopsRetry()
            // held back up to didBecomeActive, also in the inactive moment before it (the observers' foreground replay)
            if homeLoopsAwaitsForeground || UIApplication.shared.applicationState == .background {
                homeLoopsAwaitsForeground = true
                return
            }
            guard homeLoopsTask == nil else {
                homeLoopsPending = true
                return
            }
            startHomeLoopsRefresh()
        }

        private func startHomeLoopsRefresh() {
            guard let config = homeLoopsConfig else { return }
            homeLoopsPending = false
            let provider = self.provider
            homeLoopsTask = Task { [weak self] in
                let stats = await provider.loopStats(Home.loopsRange, allowOneMinuteLoop: config.allowOneMinuteLoop)
                guard let self else { return }
                self.homeLoopsTask = nil
                // a newer request (a loop, a reading, the settings, midnight) replaces this result at once
                guard !self.homeLoopsPending else {
                    self.refreshHomeLoops()
                    return
                }
                guard config == self.homeLoopsConfig else { return }
                guard let stats else {
                    self.homeLoopsReadFailed()
                    return
                }
                let content = HomeLoopsCard.Content(stats)
                self.homeLoopsNewestStart = stats.newestStart
                if content != self.homeLoops {
                    self.homeLoops = content
                }
            }
        }

        /// A failed read keeps the card as it is; the read is tried again in a minute, until one comes or another trigger
        /// reads. Without a result yet there is no card.
        private func homeLoopsReadFailed() {
            scheduleHomeLoopsRetry()
        }

        /// No retry in the background: the foreground refreshes.
        private func homeLoopsEnteredBackground() {
            // the notification comes asynchronously: nothing to do when the app is back already
            guard UIApplication.shared.applicationState == .background else { return }
            cancelHomeLoopsRetry()
            homeLoopsAwaitsForeground = true
        }

        /// The one foreground trigger: only back from the background (or after a refresh held back).
        private func homeLoopsBecameActive() {
            guard homeLoopsAwaitsForeground else { return }
            homeLoopsAwaitsForeground = false
            refreshHomeLoops()
        }

        private func cancelHomeLoopsRetry() {
            homeLoopsRetry?.cancel()
            homeLoopsRetry = nil
        }

        /// A failed read's retry, a minute after it (any other refresh first cancels it).
        private func scheduleHomeLoopsRetry() {
            cancelHomeLoopsRetry()
            guard UIApplication.shared.applicationState != .background else { return }
            homeLoopsRetry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(TimeInterval.minutes(1)))
                guard !Task.isCancelled else { return }
                self?.homeLoopsRetry = nil
                self?.refreshHomeLoops()
            }
        }

        // MARK: - Meal card

        /// The meal card's triggers, as the Loops card's (`subscribeHomeLoops`): the settings' first delivery makes the
        /// first refresh (it has no range: Today), then a meal stored or deleted (`mealsChanged`, after the save), and
        /// midnight and DST (a new today). Nothing is clock-driven: the card is as of its last read (an entry dated later
        /// counts from the first read after its time). The one timer is a failed read's retry. Nothing runs in the
        /// background: a refresh asked for there waits for the foreground, where `didBecomeActive` is the one trigger.
        private func subscribeHomeMeals() {
            // the first delivery only: no setting changes the card
            observeUI(appCoordinator.settings, map: { _ in true }) { me, _ in
                me.homeMealsSettingsDelivered()
            }
            observeUI(appCoordinator.mealsChanged, dropInitial: true) { me, _ in
                me.refreshHomeMeals()
            }
            // midnight, DST, a time zone change
            observe(notification: UIApplication.significantTimeChangeNotification) { me in
                await me.refreshHomeMeals()
            }
            observe(notification: UIApplication.didEnterBackgroundNotification) { me in
                await me.homeMealsEnteredBackground()
            }
            observe(notification: UIApplication.didBecomeActiveNotification) { me in
                await me.homeMealsBecameActive()
            }
        }

        /// The settings were delivered: the first read.
        private func homeMealsSettingsDelivered() {
            guard !homeMealsStarted else { return }
            homeMealsStarted = true
            refreshHomeMeals()
        }

        /// Recomputes the meal card: at once, after the refresh in flight (once), or in the background not at all
        /// (`didBecomeActive` does it). One at a time, as the stats bar's.
        func refreshHomeMeals() {
            guard homeMealsStarted else { return }
            cancelHomeMealsRetry()
            // held back up to didBecomeActive, also in the inactive moment before it (the observers' foreground replay)
            if homeMealsAwaitsForeground || UIApplication.shared.applicationState == .background {
                homeMealsAwaitsForeground = true
                return
            }
            guard homeMealsTask == nil else {
                homeMealsPending = true
                return
            }
            startHomeMealsRefresh()
        }

        private func startHomeMealsRefresh() {
            guard homeMealsStarted else { return }
            homeMealsPending = false
            let provider = self.provider
            homeMealsTask = Task { [weak self] in
                let content = await provider.mealsCard()
                guard let self else { return }
                self.homeMealsTask = nil
                // a newer request (a meal, midnight) replaces this result at once
                guard !self.homeMealsPending else {
                    self.refreshHomeMeals()
                    return
                }
                guard let content else {
                    self.homeMealsReadFailed()
                    return
                }
                if content != self.homeMeals {
                    self.homeMeals = content
                }
            }
        }

        /// As the Loops card's: a failed read keeps the card as it is; the read is tried again in a minute, until one
        /// comes or another trigger reads.
        private func homeMealsReadFailed() {
            scheduleHomeMealsRetry()
        }

        /// No retry in the background: the foreground refreshes.
        private func homeMealsEnteredBackground() {
            // the notification comes asynchronously: nothing to do when the app is back already
            guard UIApplication.shared.applicationState == .background else { return }
            cancelHomeMealsRetry()
            homeMealsAwaitsForeground = true
        }

        /// The one foreground trigger: only back from the background (or after a refresh held back).
        private func homeMealsBecameActive() {
            guard homeMealsAwaitsForeground else { return }
            homeMealsAwaitsForeground = false
            refreshHomeMeals()
        }

        private func cancelHomeMealsRetry() {
            homeMealsRetry?.cancel()
            homeMealsRetry = nil
        }

        /// A failed read's retry, a minute after it (any other refresh first cancels it).
        private func scheduleHomeMealsRetry() {
            cancelHomeMealsRetry()
            guard UIApplication.shared.applicationState != .background else { return }
            homeMealsRetry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(TimeInterval.minutes(1)))
                guard !Task.isCancelled else { return }
                self?.homeMealsRetry = nil
                self?.refreshHomeMeals()
            }
        }

        // MARK: - Insulin card

        /// The insulin card's triggers, as the meal card's (`subscribeHomeMeals`): the settings' first delivery makes the
        /// first refresh (it has no range: Today), then the insulin statistics changing (`insulinStatsChanged`, the
        /// Insulin tab's signal: after the service dropped the days a loop, a pump event, a backfill or a profile edit
        /// touched, never `insulinDataChanged`, which comes before that), and midnight and DST (the days move on; a read
        /// at midnight makes the new today). Nothing is clock-driven: Today shows the read's time (each day's insulin and
        /// the usual by 14:35), true between reads. The one timer is a failed read's retry. Nothing runs in the
        /// background: a refresh asked for there waits for the foreground, where `didBecomeActive` is the one trigger.
        private func subscribeHomeInsulin() {
            // the first delivery only: no setting changes the card
            observeUI(appCoordinator.settings, map: { _ in true }) { me, _ in
                me.homeInsulinSettingsDelivered()
            }
            observeUI(appCoordinator.insulinStatsChanged, dropInitial: true) { me, change in
                me.homeInsulinStatsChanged(change)
            }
            // midnight (also when it passed in the background: queued up to the foreground), DST, a time zone change
            observe(notification: UIApplication.significantTimeChangeNotification) { me in
                await me.refreshHomeInsulin()
            }
            observe(notification: UIApplication.didEnterBackgroundNotification) { me in
                await me.homeInsulinEnteredBackground()
            }
            observe(notification: UIApplication.didBecomeActiveNotification) { me in
                await me.homeInsulinBecameActive()
            }
        }

        /// The settings were delivered: the first read.
        private func homeInsulinSettingsDelivered() {
            guard !homeInsulinStarted else { return }
            homeInsulinStarted = true
            refreshHomeInsulin()
        }

        /// The insulin statistics changed: a read, unless the last one read this change already (the foreground's
        /// replay of it after `didBecomeActive` read).
        private func homeInsulinStatsChanged(_ change: StatsChange) {
            guard change.seq > homeInsulinReadSeq else { return }
            refreshHomeInsulin()
        }

        /// Reads the insulin card again: at once, after the one in flight (once), or in the background not at all
        /// (`didBecomeActive` does it). One at a time, as the stats bar's.
        func refreshHomeInsulin() {
            guard homeInsulinStarted else { return }
            cancelHomeInsulinRetry()
            // held back up to didBecomeActive, also in the inactive moment before it (the observers' foreground replay)
            if homeInsulinAwaitsForeground || UIApplication.shared.applicationState == .background {
                homeInsulinAwaitsForeground = true
                return
            }
            guard homeInsulinTask == nil else {
                homeInsulinPending = true
                return
            }
            startHomeInsulinRefresh()
        }

        private func startHomeInsulinRefresh() {
            guard homeInsulinStarted else { return }
            homeInsulinPending = false
            // before the read: the service published it after it dropped the changed days, so the read reads it
            homeInsulinReadSeq = appCoordinator.insulinStatsChanged.value.seq
            let provider = self.provider
            homeInsulinTask = Task { [weak self] in
                let content = await provider.insulinCard()
                guard let self else { return }
                self.homeInsulinTask = nil
                // a newer request (the insulin data, the time) replaces this result at once
                guard !self.homeInsulinPending else {
                    self.refreshHomeInsulin()
                    return
                }
                guard let content else {
                    self.homeInsulinReadFailed()
                    return
                }
                if content != self.homeInsulin {
                    self.homeInsulin = content
                }
            }
        }

        /// A failed read keeps the card as it is (as of its read: its time says so); the read is tried again in a minute
        /// (as the Loops card's): once a minute at most, until one comes or another trigger reads.
        private func homeInsulinReadFailed() {
            scheduleHomeInsulinRetry()
        }

        /// No retry in the background: the foreground refreshes.
        private func homeInsulinEnteredBackground() {
            // the notification comes asynchronously: nothing to do when the app is back already
            guard UIApplication.shared.applicationState == .background else { return }
            cancelHomeInsulinRetry()
            homeInsulinAwaitsForeground = true
        }

        /// The one foreground trigger: only back from the background (or after a refresh held back).
        private func homeInsulinBecameActive() {
            guard homeInsulinAwaitsForeground else { return }
            homeInsulinAwaitsForeground = false
            refreshHomeInsulin()
        }

        private func cancelHomeInsulinRetry() {
            homeInsulinRetry?.cancel()
            homeInsulinRetry = nil
        }

        /// A failed read's retry, a minute after it (any other refresh first cancels it).
        private func scheduleHomeInsulinRetry() {
            cancelHomeInsulinRetry()
            guard UIApplication.shared.applicationState != .background else { return }
            homeInsulinRetry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(TimeInterval.minutes(1)))
                guard !Task.isCancelled else { return }
                self?.homeInsulinRetry = nil
                self?.refreshHomeInsulin()
            }
        }

        private func setupData() async {
            reasonsReadsStarted += 1
            let read = reasonsReadsStarted
            let dayStart = Date().addingTimeInterval(-.hours(24))
            // 7.5 min more for the On board card: a row before its window counts up to the next one
            // (`InsulinStatsEngine.iobSpans`)
            let rows = await provider.reasons(since: dayStart.addingTimeInterval(-InsulinStatsEngine.iobMaximumSpan))
            guard read > reasonsReadApplied else { return }
            reasonsReadApplied = read
            // the main chart's COB: the last 24 h as before (`DateFilter.day`, newest -> oldest), the last rows kept with
            // 3 or fewer
            let day = rows.filter { $0.date > dayStart }
            if day.count > 3 {
                iobData = day
            }
            onBoardRows = rows
            refreshOnBoard()
        }

        // MARK: - On board card

        /// The On board card's triggers besides the data's (`setupData`: a loop, a suggestion, the settings;
        /// `setupGlucose`: a reading, the bands, the units): the foreground (its window is as of the build) and a time
        /// change (the hours: midnight, DST, a time zone). No clock. Its lanes' toggles need no build (`Content.lanes`).
        private func subscribeHomeOnBoard() {
            observe(notification: UIApplication.didBecomeActiveNotification) { me in
                await me.refreshOnBoard()
            }
            observe(notification: UIApplication.significantTimeChangeNotification) { me in
                await me.onBoardTimeChanged()
            }
        }

        /// Midnight, DST, a time zone: the hours. In the background the foreground builds it.
        private func onBoardTimeChanged() {
            guard UIApplication.shared.applicationState != .background else { return }
            refreshOnBoard()
        }

        /// Builds the card from the last IOB rows and the readings, as of now to the minute (cheap: up to 1440 rows and
        /// readings each, a 1-minute loop and CGM); published only when it changed (a loop's and its suggestion's builds
        /// in the same minute: once). No card with 3 rows or fewer in its window (`hasRows`): none yet, or a loop
        /// stopped long enough ago that the readings moved the window past them.
        private func refreshOnBoard() {
            let content = onBoardRows.map { rows in
                HomeOnBoardCard.Content(
                    iob: rows,
                    readings: data.glucose.map { HomeOnBoardCard.Reading(date: $0.dateString, mgdl: $0.glucose) },
                    bands: StatsBands(low: data.lowGlucose, high: data.highGlucose, units: data.units),
                    units: data.units,
                    now: Date(),
                    calendar: .current
                )
            }
            guard let content, content.hasRows else {
                if homeOnBoard != nil {
                    homeOnBoard = nil
                }
                return
            }
            if content != homeOnBoard {
                homeOnBoard = content
            }
        }

        func openCGM() {
            if let cgmInfo = appUIState.cgmInfo {
                if let url = cgmInfo.appURL {
                    // if app url is provided (nightscout, xDrip) - open it
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                } else if !cgmInfo.pumpIsCgm {
                    let view = CGM.CGMSettingsView(
                        deviceManager: deviceManager,
                        completionDelegate: self
                    ).asAny()
                    router.mainSecondaryModalView.send(view)
                }
            }
        }

        func infoPanelTTPercentage(_ hbt_: Double, _ target: Decimal) -> Decimal {
            guard hbt_ != 0 || target != 0 else {
                return 0
            }
            let c = Decimal(hbt_ - 100)
            let ratio = min(c / (target + c - 100), maxValue)
            return (ratio * 100)
        }
    }
}

extension Home.StateModel {
    private func glucoseDidUpdate() async {
        setupGlucose()
    }

    private func suggestionDidUpdate(_ suggestion: Suggestion?) async {
        data.suggestion = suggestion
        carbsRequired = suggestion?.carbsReq
        setStatusTitle()
        await setupOverrideHistory()
        await setupData()
        setupCob()
    }

    private func readFromSettings(_ settings: FreeAPSSettings) async {
        data.smooth = settings.glucoseSmoothing.isEnabled

        data.lowGlucose = settings.low
        data.highGlucose = settings.high
        data.displayXgridLines = settings.xGridLines
        data.displayYgridLines = settings.yGridLines
        data.thresholdLines = settings.rulerMarks
        data.showInsulinActivity = settings.showInsulinActivity
        data.showCobChart = settings.showCobChart
        data.secondaryChartBackdrop = settings.secondaryChartBackdrop
        data.inRangeAreaFill = settings.inRangeAreaFill
        data.chartGlucosePeaks = settings.chartGlucosePeaks
        data.insulinActivityGridLines = settings.insulinActivityGridLines
        data.insulinActivityLabels = settings.insulinActivityLabels
        data.yGridLabels = settings.yGridLabels
        data.showPredictionsLegend = settings.showPredictionsLegend
        data.loopEventsPlacement = settings.loopEventsPlacement
        useTargetButton = settings.useTargetButton

        alwaysUseColors = settings.alwaysUseColors
        useCalc = settings.useCalc
        data.minimumSMB = settings.minimumSMB
        data.useInsulinBars = settings.useInsulinBars
        data.fpus = settings.fpus
        data.fpuAmounts = settings.fpuAmounts
        data.hidePredictions = settings.hidePredictions
        data.useCarbBars = settings.useCarbBars
        displayDelta = settings.displayDelta
        autoisf = settings.autoisfEffective
        hours = max(min(settings.hours, 24), 2)
        data.screenHours = hours
        displayExpiration = settings.displayExpiration
        displaySAGE = settings.displaySAGE
        ai = settings.ai

        allowManualTemp = !settings.closedLoop
        uploadStats = settings.uploadStats
        closedLoop = settings.closedLoop
        data.units = settings.units
        animatedBackground = settings.animatedBackground

        carbButton = settings.carbButton
        profileButton = settings.profileButton

        setupGlucose()
    }

    private func readFromPreferences() {
        maxValue = preferences.autosensMax
        maxIOB = preferences.maxIOB
        maxCOB = preferences.maxCOB
        data.maxIOB = preferences.maxIOB
        data.insulinPeak = preferences.useCustomPeakTime ? preferences.insulinPeakTime :
            (preferences.curve == .ultraRapid ? 55 : 75)
    }

    private func pumpHistoryDidUpdate(_ pumpHistory: [PumpHistoryEvent]) async {
        self.pumpHistory = pumpHistory.reversed() // pump history is expected to be reversed, oldest -> newest
        setupBasals()
        setupBoluses()
        setupSuspensions()
        await setupAnnouncements()
    }

    private func basalProfileUpdated(_ basalProfile: [BasalProfileEntry]) {
        data.basalProfile = basalProfile
        data.autotunedBasalProfile = appCoordinator.autotune.value?.basalProfile ?? basalProfile
    }

    private func autotuneUpdated(_ autotune: Profile?) {
        data.autotunedBasalProfile = autotune?.basalProfile ?? appCoordinator.basalProfile.value
    }

    private func tempTargetsUpdated(_ tempTargets: [TempTarget]) {
        let now = Date()

        // the chart expects oldest -> newest
        data.tempTargets = tempTargets.reversed().filter {
            $0.createdAt.addingTimeInterval(.hours(hours)) > now
        }
        updateCurrentTempTarget(tempTargets)
    }

    private func carbsUpdated(_ carbsHistory: [CarbsEntry]) async {
        setupCarbs(carbsHistory)
        await setupAnnouncements()
    }

    private func loopCompleted(_ loopOutcome: LoopOutcome) async {
        enactedSuggestion = loopOutcome.enactedSuggestion
        setStatusTitle()
        refreshHomeLoops()
        await setupOverrideHistory()
        await setupData()
    }
}

extension Home.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        setupPump = false
    }
}
