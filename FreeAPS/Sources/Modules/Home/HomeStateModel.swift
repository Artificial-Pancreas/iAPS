import Combine
import CoreData
import LibreTransmitter
import LoopKit
import LoopKitUI
import SwiftDate
import SwiftUI

extension Home {
    final class StateModel: BaseStateModel<Provider>, LifetimeOwner {
        @Injected() private var apsManager: APSManager!
        @Injected() private var nightscoutManager: NightscoutManager!
        @Injected() private var storage: TempTargetsStorage!
        @Injected() private var deviceManager: DeviceDataManager!
        @Injected() private var appUIState: AppUIState!

        private let coredataContext = CoreDataStack.shared.persistentContainer.viewContext
        private let coreDataStorage = CoreDataStorage()
        private let overrideStorage = OverrideStorage()

        private let timer = DispatchTimer(timeInterval: 5)
        private(set) var filteredHours = 24

        @Published private(set) var settings: FreeAPSSettings?

        private var preferences: Preferences!
        private var pumpSettings: PumpSettings!
        private var basalProfile: [BasalProfileEntry]!
        private var pumpHistory: [PumpHistoryEvent]!
        private var cgmSensorDays: Double?

        @Published var dynamicVariables: DynamicVariables?
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
        @Published var alwaysUseColors: Bool = false
        @Published var useCalc: Bool = true
        @Published var hours: Int = 6
        @Published var iobData: [IOBData] = []
        @Published var carbData: Decimal = 0
        @Published var iobs: Decimal = 0
        @Published var neg: Int = 0
        @Published var tddChange: Decimal = 0
        @Published var tddAverage: Decimal = 0
        @Published var tddYesterday: Decimal = 0
        @Published var tdd2DaysAgo: Decimal = 0
        @Published var tdd3DaysAgo: Decimal = 0
        @Published var tddActualAverage: Decimal = 0
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
            hours: 24,
            maxBasal: 4,
            autotunedBasalProfile: [],
            basalProfile: [],
            tempTargets: [],
            carbs: [],
            timerDate: Date(),
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
            maxCOB: 1,
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
            iob: nil,
            hidePredictions: false,
            useCarbBars: false
        )

        func startTimer() {
            timer.fire()
            timer.resume()
        }

        func stopTimer() {
            timer.suspend()
        }

        override func subscribe() async {
            let fetchedSettings = await settingsManager.settings
            settings = fetchedSettings
            pumpSettings = await settingsManager.pumpSettings
            preferences = await settingsManager.preferences
            basalProfile = await provider.basalProfile()
            pumpHistory = await provider.pumpHistory(hours: filteredHours)

            cgmSensorDays = appCoordinator.cgmInfo.value?.sensorDays

            data.tempTargets = await provider.tempTargets(hours: filteredHours)

            await readFromSettings(fetchedSettings)
            readFromPreferences()
            readFromPumpSettings()

            await setupBasals()
            await setupBoluses()
            await setupActivity()
            await setupSuspensions()

            await setupBasalProfile(basalProfile)
            await setupCarbs()
            await setupAnnouncements()

            setupLoopStatsBackground()
            setupCob()
            setupMeals()

            data.suggestion = appCoordinator.suggested.value
            enactedSuggestion = appCoordinator.latestLoopOutcome.value?.enactedSuggestion
            dynamicVariables = await provider.dynamicVariables

            carbsRequired = data.suggestion?.carbsReq

            setStatusTitle()
            await setupCurrentTempTarget()

            await setupOverrideHistory()
            await setupData()

            observe(appCoordinator.cgmInfo.map(\.?.sensorDays).removeDuplicates()) { me, sensorDays in
                await me.cgmCensorDaysUpdated(sensorDays)
            }

            observe(appCoordinator.glucoseHistory.dropFirst()) { me, glucose in
                // TODO: use the provided value inside the function, currently it re-reads from the storage
                await me.glucoseDidUpdate(glucose)
            }

            observe(appCoordinator.suggested) { me, suggestion in
                await me.suggestionDidUpdate(suggestion)
            }

            observe(appCoordinator.iobTicks.dropFirst().map(\.?.first)) { me, iob in
                await me.currentIobUpdated(iob)
            }

            observe(appCoordinator.settings.dropFirst()) { me, settings in
                await me.settingsUpdated(settings)
            }

            observe(appCoordinator.preferences.dropFirst()) { me, preferences in
                await me.preferencesUpdated(preferences)
            }

            observe(appCoordinator.pumpSettings.dropFirst()) { me, pumpSettings in
                await me.pumpSettingsUpdated(pumpSettings)
            }

            observe(appCoordinator.pumpHistory.dropFirst()) { me, pumpHistory in
                await me.pumpHistoryDidUpdate(pumpHistory)
            }

            observe(appCoordinator.basalProfileUpdates) { me, basalProfile in
                await me.basalProfileUpdated(basalProfile)
            }

            observe(appCoordinator.tempTargets.dropFirst()) { me, tempTargets in
                await me.tempTargetsUpdated(tempTargets)
            }

            observe(appCoordinator.carbHistory.dropFirst()) { me, carbHistory in
                await me.carbsUpdated(carbHistory)
            }

            observe(appCoordinator.loopCompleted) { me, loopOutcome in
                await me.loopCompleted(loopOutcome)
            }

            subscribeSetting(\.hours, on: $hours) {
                let value = max(min($0, 24), 2)
                self.hours = value
                self.data.screenHours = value
            }

            timer.eventHandler = {
                Task { @MainActor [weak self] in
                    self?.data.timerDate = Date()
                    await self?.setupCurrentTempTarget()
                }
            }

            observe(appCoordinator.pumpStatus) { me, pumpStatus in
                await me.pumpStatusUpdated(pumpStatus)
            }

            observe(appCoordinator.pumpInfo) { me, pumpInfo in
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

        func cancelProfile() {
            Task {
                // Is there a saved Override?
                if let activeOveride = await overrideStorage.fetchLatestOverride().first {
                    let presetName = await overrideStorage.isPresetName()
                    // Is the Override a Preset?
                    if let preset = presetName {
                        if let duration = await overrideStorage.cancelProfile() {
                            // Update in Nightscout
                            await nightscoutManager.uploadOverride(preset, duration, activeOveride.date ?? Date.now)
                        }
                    } else if activeOveride.isPreset { // Because hard coded Hypo treatment isn't actually a preset
                        if let duration = await overrideStorage.cancelProfile() {
                            await nightscoutManager.uploadOverride("📉", duration, activeOveride.date ?? Date.now)
                        }
                    } else {
                        let nsString = activeOveride.percentage.formatted() != "100" ? activeOveride.percentage
                            .formatted() + " %" : "Custom"
                        if let duration = await overrideStorage.cancelProfile() {
                            await nightscoutManager.uploadOverride(nsString, duration, activeOveride.date ?? Date.now)
                        }
                    }
                }
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
            data.isManual = await provider.manualGlucose(hours: filteredHours)
            data.glucose = await provider.filteredGlucose(hours: filteredHours)
            readings = await coreDataStorage.fetchGlucose(interval: DateFilter.today.startDate)
            recentGlucose = data.glucose.last
            if data.glucose.count >= 2 {
                glucoseDelta =
                    NSDecimalNumber(
                        decimal:
                        (recentGlucose?.unfiltered ?? 0) -
                            (data.glucose[data.glucose.count - 2].unfiltered ?? 0)
                    ).intValue
            } else {
                glucoseDelta = nil
            }
        }

        private func setupBasals() async {
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

        private func setupBoluses() async {
            data.boluses = pumpHistory.filter {
                $0.type == .bolus
            }
            data.maxBolusValue = data.boluses.compactMap(\.amount).max() ?? 1
        }

        private func setupSuspensions() async {
            data.suspensions = pumpHistory.filter {
                $0.type == .pumpSuspend || $0.type == .pumpResume
            }

            let last = data.suspensions.last
            let tbr = data.tempBasals.first { $0.timestamp > (last?.timestamp ?? .distantPast) }

            // TODO: should we read this from the pump manager instead?
            pumpSuspended = tbr == nil && last?.type == .pumpSuspend
        }

        private func setupActivity() async {
            data.activity = await coreDataStorage.fetchInsulinData(interval: DateFilter.day.startDate)
        }

        private func setupCob() {
            data.cob = iobData
        }

        private func readFromPumpSettings() {
            data.maxBasal = pumpSettings.maxBasal
            data.maxBolus = pumpSettings.maxBolus
            data.insulinDIA = pumpSettings.insulinActionCurve
        }

        private func setupBasalProfile(_ basalProfile: [BasalProfileEntry]) async {
            data.autotunedBasalProfile = await provider.autotunedBasalProfile()
            data.basalProfile = basalProfile
        }

        private func setupCarbs() async {
            data.carbs = await provider.carbs(hours: filteredHours)
            data.maxCarbsValue = data.carbs.compactMap(\.carbs).max() ?? 1
        }

        private func setupOverrideHistory() async {
            overrideHistory = await provider.overrideHistory()
            data.latestOverride = await provider.latestOverride()
            data.overrideHistory = overrideHistory
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
                    let time = (loopStats.last?.start ?? Date.now).addingTimeInterval(-5.minutes.timeInterval)

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

        private func setupCurrentTempTarget() async {
            tempTarget = await provider.tempTarget()
        }

        private func currentIobUpdated(_ iob: IOBEntry?) async {
            data.iob = iob?.iob
        }

        private func setupData() async {
            if let data = await provider.reasons() {
                iobData = data
                carbData = data.map(\.cob).reduce(0, +)
                iobs = data.map(\.iob).reduce(0, +)
                neg = data.filter({ $0.iob < 0 }).count * 5
                let tdds = await coreDataStorage.fetchTDD(interval: DateFilter.tenDays.startDate)
                let yesterday = (tdds.first(where: {
                    ($0.timestamp ?? .distantFuture) <= Date().addingTimeInterval(-24.hours.timeInterval)
                })?.tdd ?? 0) as Decimal
                let oneDaysAgo = tdds.last
                tddChange = ((tdds.first?.tdd ?? 0) as Decimal) - yesterday
                tddYesterday = (oneDaysAgo?.tdd ?? 0) as Decimal
                tdd2DaysAgo = (tdds.first(where: {
                    ($0.timestamp ?? .distantFuture) <= (oneDaysAgo?.timestamp ?? .distantPast)
                        .addingTimeInterval(-1.days.timeInterval)
                })?.tdd ?? 0) as Decimal
                tdd3DaysAgo = (tdds.first(where: {
                    ($0.timestamp ?? .distantFuture) <= (oneDaysAgo?.timestamp ?? .distantPast)
                        .addingTimeInterval(-2.days.timeInterval)
                })?.tdd ?? 0) as Decimal

                if let tdds_ = await provider.dynamicVariables {
                    tddAverage = ((tdds.first?.tdd ?? 0) as Decimal) - tdds_.average_total_data
                    tddActualAverage = tdds_.average_total_data
                }
            }
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
        data.iob = suggestion?.iob
        carbsRequired = suggestion?.carbsReq
        setStatusTitle()
        await setupOverrideHistory()
        setupLoopStatsBackground()
        await setupData()
        await setupActivity()
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
        data.maxCOB = preferences.maxCOB
        data.insulinPeak = preferences.useCustomPeakTime ? preferences.insulinPeakTime :
            (preferences.curve == .ultraRapid ? 55 : 75)
    }

    private func pumpHistoryDidUpdate(_ pumpHistory: [PumpHistoryEvent]) async {
        self.pumpHistory = pumpHistory
        await setupBasals()
        await setupBoluses()
        await setupSuspensions()
        await setupAnnouncements()
        await setupActivity()
    }

    private func basalProfileUpdated(_ basalProfile: [BasalProfileEntry]) async {
        await setupBasalProfile(basalProfile)
    }

    private func tempTargetsUpdated(_ tempTargets: [TempTarget]) async {
        let now = Date()
        data.tempTargets = tempTargets.filter { // TODO: this filter is duplicated in the provider
            $0.createdAt.addingTimeInterval(hours.hours.timeInterval) > now
        }
    }

    private func carbsUpdated(_: [CarbsEntry]) async {
        // TODO: use the provided values instead of re-reading
        await setupCarbs()
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
