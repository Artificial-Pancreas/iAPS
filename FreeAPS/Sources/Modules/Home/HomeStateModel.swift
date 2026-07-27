import Combine
import CoreData
import LibreTransmitter
import LoopKit
import LoopKitUI
import SwiftDate
import SwiftUI
import UIKit

extension Home {
    final class StateModel: BaseStateModel<Provider>, LifetimeOwner, UIBindingOwner {
        @Injected() private var apsManager: APSManager!
        @Injected() private var storage: TempTargetsStorage!
        @Injected() private var deviceManager: DeviceDataManager!
        @Injected() private var overrideManager: OverrideManager!
        @Injected() private var appUIState: AppUIState!

        private let coredataContext = CoreDataStack.shared.persistentContainer.viewContext
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
        @Published var overrideUnit: Bool = false
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
        @Published var readings: [ReadingsSnapshot] = []
        @Published var loopStatistics: (Int, Int, Double, String) = (0, 0, 0, "")
        @Published var standing: Bool = false
        @Published var preview: Bool = true
        @Published var useTargetButton: Bool = false
        @Published var overrideHistory: [OverrideHistorySnapshot] = []
        @Published private(set) var latestOverride: OverrideSnapshot?
        // preset of the active override (nil when the override is not an existing named preset)
        @Published private(set) var overridePreset: OverridePresetsSnapshot?
        // autoisf flag of the active override's Auto_ISF record (nil when no active override / no record)
        @Published private(set) var overrideAutoISF: Bool?
        @Published var alwaysUseColors: Bool = false
        @Published var useCalc: Bool = true
        @Published var hours: Int = 6
        @Published var iobData: [IOBData] = []
        @Published var showIOBChart: Bool = false
        @Published var showCOBChart: Bool = false
        @Published var insulinStatistics: InsulinStatistics = .empty
        @Published var skipGlucoseChart: Bool = false
        @Published var displayDelta: Bool = false
        @Published var maxIOB: Decimal = 0
        @Published var maxCOB: Decimal = 0
        @Published var autoisf = false
        @Published var displayExpiration = false
        @Published var displaySAGE = true
        @Published var sensorDays: Double = 10
        @Published var carbButton: Bool = true
        @Published var profileButton: Bool = true
        @Published var mealData = MealData()
        @Published var ai: Bool = false
        @Published var individual = Individual.default
        @Published var selectedMealInterval: DateFilter = .today

        // Chart data
        var data = ChartModel(
            suggestion: nil,
            glucose: [],
            activity: [],
            cob: [],
            isManual: [],
            tempBasals: [],
            boluses: [],
            suspensions: [],
            announcement: [],
            loopEvents: [],
            glucoseGaps: [],
            showLoopEvents: true,
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

        override func subscribe() async {
            let fetchedSettings = await settingsManager.settings
            settings = fetchedSettings
            pumpSettings = await settingsManager.pumpSettings
            preferences = await settingsManager.preferences

            basalProfileUpdated(appCoordinator.basalProfile.value)
            autotuneUpdated(appCoordinator.autotune.value)

            pumpHistory = appCoordinator.pumpHistory.value.reversed()

            cgmSensorDays = appCoordinator.cgmInfo.value?.sensorDays

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
            data.glucoseGaps = appCoordinator.glucoseGaps.value

            setupLoopStatsBackground()
            setupCob()
            setupMeals()

            data.suggestion = appCoordinator.suggested.value
            enactedSuggestion = appCoordinator.latestLoopOutcome.value?.enactedSuggestion

            carbsRequired = data.suggestion?.carbsReq

            setStatusTitle()
            refreshCurrentTempTarget()

            await setupOverrideHistory()
            await setupData()

            observeUI(appCoordinator.cgmInfo, map: { $0?.sensorDays }) { me, sensorDays in
                await me.cgmCensorDaysUpdated(sensorDays)
            }

            observeUI(appCoordinator.glucoseRaw) { me, glucose in
                // TODO: use the provided value inside the function, currently it re-reads from the storage
                await me.glucoseDidUpdate(glucose)
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

            observeUI(appCoordinator.tempTargets) { me, tempTargets in
                me.tempTargetsUpdated(tempTargets)
            }

            observeUI(appCoordinator.carbHistory) { me, carbHistory in
                await me.carbsUpdated(carbHistory)
            }

            observeUI(appCoordinator.loopEvents) { me, loopEvents in
                me.data.loopEvents = loopEvents
            }

            observeUI(appCoordinator.glucoseGaps) { me, glucoseGaps in
                me.data.glucoseGaps = glucoseGaps
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
            showModal(for: .addCarbs(editMode: false, override: false, mode: .meal))
        }

        func runLoop() {
            provider.heartbeatNow()
        }

        func cancelBolus() {
            Task {
                await apsManager.cancelBolus()
            }
        }

        func cancelActiveOverride() {
            Task {
                await overrideManager.cancelActiveOverride()
                await setupOverrideHistory()
            }
        }

        func cancelTempTarget() {
            Task {
                await storage.storeTempTargets([TempTarget.cancel(at: Date())])
                let saveToCoreData = TempTargets(context: self.coredataContext)
                saveToCoreData.active = false
                saveToCoreData.date = Date()
                try? self.coredataContext.save()

                let setHBT = TempTargetsSlider(context: self.coredataContext)
                setHBT.enabled = false
                setHBT.date = Date()
                try? self.coredataContext.save()
            }
        }

        private func setupGlucose() async {
            data.isManual = provider.manualGlucose(hours: filteredHours)
            data.glucose = provider.smoothedGlucose(hours: filteredHours)
            readings = await coreDataStorage.fetchGlucose(interval: DateFilter.today.startDate)
            recentGlucose = data.glucose.last
            if data.glucose.count >= 2 {
                glucoseDelta =
                    NSDecimalNumber(
                        decimal:
                        (recentGlucose?.unfiltered ?? 0) -
                            data.glucose[data.glucose.count - 2].unfiltered
                    ).intValue
            } else {
                glucoseDelta = nil
            }
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
        }

        private func setupLoopStatsBackground() {
            Task {
                let loopStats = await self.coreDataStorage.fetchLoopStats(interval: DateFilter.today.startDate)
                let readings = await self.coreDataStorage.fetchGlucose(interval: DateFilter.today.startDate).compactMap(\.glucose)
                    .count

                let result = await Task.detached {
                    let loops = loopStats.compactMap({ each in each.loopStatus }).count
                    let percentage = min(readings != 0 ? (Double(loops) / Double(readings) * 100) : 0, 100)
                    // First loop date
                    let time = (loopStats.last?.start ?? Date.now).subtractingTimeInterval(.minutes(5))

                    let average = -1 * (time.timeIntervalSinceNow / 60) / max(Double(loops), 1)

                    return (
                        loops,
                        readings,
                        percentage,
                        average.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + " min"
                    )
                }.value
                self.loopStatistics = result
            }
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
        private func updateCurrentTempTarget(_ tempTargets: [TempTarget]) {
            tempTargetBoundaryTask?.cancel()
            tempTargetBoundaryTask = nil

            let now = Date()
            let last = tempTargets.last
            let current = last.flatMap { $0.isActive(at: now) ? $0 : nil }
            if tempTarget != current {
                tempTarget = current
            }

            guard let last, last.duration != 0 else { return }
            let boundary = now < last.createdAt ? last.createdAt : last.endDate
            guard boundary > now else { return }

            tempTargetBoundaryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(boundary.timeIntervalSinceNow))
                guard !Task.isCancelled else { return }
                self?.refreshCurrentTempTarget()
            }
        }

        private func setupData() async {
            if let data = await provider.reasons() {
                iobData = data
                showIOBChart = data.isNotEmpty
                showCOBChart = data.contains { $0.cob > 0 }
                insulinStatistics = await makeInsulinStatistics(reasons: data)
            }
        }

        private func makeInsulinStatistics(reasons: [IOBData]) async -> InsulinStatistics {
            let minutesWithNegativeIOB = reasons.filter { $0.iob < 0 }.count * 5

            let tdds = await coreDataStorage.fetchTDD(interval: DateFilter.tenDays.startDate)

            // Time-adjusted average daily TDD over the last ten days. The walk is shared with the dynamic-variables path; this one is post-loop.
            let actualAverage = tdds.averageDailyTDD

            let latestTDD = (tdds.first?.tdd ?? 0) as Decimal
            let yesterdayTDD = (tdds.first(where: {
                ($0.timestamp ?? .distantFuture) <= Date().subtractingTimeInterval(.hours(24))
            })?.tdd ?? 0) as Decimal

            let todayStart = DateFilter.today.startDate as Date
            let oneDayAgo = tdds.last(where: { ($0.timestamp ?? .distantPast) >= todayStart })
            let tdd2DaysAgo = (tdds.first(where: {
                ($0.timestamp ?? .distantFuture) <= (oneDayAgo?.timestamp ?? .distantPast)
                    .subtractingTimeInterval(.hours(24))
            })?.tdd ?? 0) as Decimal
            let tdd3DaysAgo = (tdds.first(where: {
                ($0.timestamp ?? .distantFuture) <= (oneDayAgo?.timestamp ?? .distantPast)
                    .subtractingTimeInterval(.days(2))
            })?.tdd ?? 0) as Decimal

            return InsulinStatistics(
                minutesWithNegativeIOB: minutesWithNegativeIOB,
                tddChange: latestTDD - yesterdayTDD,
                tddAverage: latestTDD - actualAverage,
                tddYesterday: (oneDayAgo?.tdd ?? 0) as Decimal,
                tdd2DaysAgo: tdd2DaysAgo,
                tdd3DaysAgo: tdd3DaysAgo,
                tddActualAverage: actualAverage
            )
        }

        func setupMeals() {
            Task {
                print("Meal Flow: update mealData")

                let meals = await provider.fetchedMeals(selectedMealInterval.startDate)

                mealData = MealData(
                    carbs: sum(\.carbs, in: meals),
                    fat: sum(\.fat, in: meals),
                    protein: sum(\.protein, in: meals),
                    fiber: sum(\.fiber, in: meals),
                    kcal: 0,
                    servings: meals.count,
                    micronutrients: microCount(meals),
                    intervalDays: DateFilter.interval(meals)
                )

                mealData.kcal =
                    4 * (mealData.carbs + mealData.protein) +
                    9 * mealData.fat

                debugPrintMealData()
            }
        }

        private func sum(
            _ keyPath: KeyPath<MealsSnapshot, Decimal?>,
            in meals: [MealsSnapshot]
        ) -> Decimal {
            meals
                .compactMap { $0[keyPath: keyPath] as Decimal? }
                .reduce(0, +)
        }

        private func microCount(_ meals: [MealsSnapshot]) -> [MicroNutrient: Decimal] {
            meals.reduce(into: [:]) { result, meal in
                for (nutrient, amount) in meal.micronutrientTotals {
                    result[nutrient, default: 0] += amount
                }
            }
        }

        private func debugPrintMealData() {
            print("Meal Flow Carbs: \(mealData.carbs)")
            print("Meal Flow Protein: \(mealData.protein)")
            print("Meal Flow Fat: \(mealData.fat)")

            for item in mealData.micronutrients {
                print(
                    "Meal Flow Micro \(item.key.rawValue) \(item.value)"
                )
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
    private func glucoseDidUpdate(_: [BloodGlucose]) async {
        await setupGlucose()
        setupLoopStatsBackground()
    }

    private func suggestionDidUpdate(_ suggestion: Suggestion?) async {
        data.suggestion = suggestion
        carbsRequired = suggestion?.carbsReq
        setStatusTitle()
        await setupOverrideHistory()
        setupLoopStatsBackground()
        await setupData()
        setupCob()
    }

    private func readFromSettings(_ settings: FreeAPSSettings) async {
        data.smooth = settings.smoothGlucose

        data.lowGlucose = settings.low
        data.highGlucose = settings.high
        overrideUnit = settings.overrideHbA1cUnit
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
        data.showLoopEvents = settings.showLoopEvents
        useTargetButton = settings.useTargetButton

        alwaysUseColors = settings.alwaysUseColors
        useCalc = settings.useCalc
        data.minimumSMB = settings.minimumSMB
        data.useInsulinBars = settings.useInsulinBars
        data.fpus = settings.fpus
        data.fpuAmounts = settings.fpuAmounts
        data.hidePredictions = settings.hidePredictions
        data.useCarbBars = settings.useCarbBars
        skipGlucoseChart = settings.skipGlucoseChart
        displayDelta = settings.displayDelta
        autoisf = settings.autoisfEffective
        hours = max(min(settings.hours, 24), 2)
        data.screenHours = hours
        displayExpiration = settings.displayExpiration
        displaySAGE = settings.displaySAGE
        ai = settings.ai
        individual.sex = Sex.savedSettings(settings.sexSetting)
        individual.age = Int((settings.birthDate.timeIntervalSinceNow.hours / (365 * 24)).rounded(.towardZero))

        allowManualTemp = !settings.closedLoop
        uploadStats = settings.uploadStats
        closedLoop = settings.closedLoop
        data.units = settings.units
        animatedBackground = settings.animatedBackground

        carbButton = settings.carbButton
        profileButton = settings.profileButton

        await setupGlucose()
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
        // TODO: refactor the code to assume the standard newest->oldest ordering instead
        // chart + current-detection expect oldest -> newest
        let tempTargets = Array(tempTargets.reversed())

        let now = Date()

        data.tempTargets = tempTargets.filter {
            $0.createdAt.addingTimeInterval(.hours(hours)) > now
        }
        updateCurrentTempTarget(tempTargets)
    }

    private func carbsUpdated(_ carbsHistory: [CarbsEntry]) async {
        setupCarbs(carbsHistory)
        await setupAnnouncements()
        setupMeals()
    }

    private func loopCompleted(_ loopOutcome: LoopOutcome) async {
        enactedSuggestion = loopOutcome.enactedSuggestion
        setStatusTitle()
        await setupOverrideHistory()
        setupLoopStatsBackground()
        await setupData()
    }
}

extension Home.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        setupPump = false
    }
}
