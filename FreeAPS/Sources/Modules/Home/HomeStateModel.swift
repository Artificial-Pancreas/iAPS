import Combine
import CoreData
import LoopKitUI
import SwiftDate
import SwiftUI

extension Home {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var broadcaster: Broadcaster!
        @Injected() var apsManager: APSManager!
        @Injected() var nightscoutManager: NightscoutManager!
        @Injected() var storage: TempTargetsStorage!
        @Injected() var keychain: Keychain!
        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext
        private let timer = DispatchTimer(timeInterval: 5)
        private(set) var filteredHours = 24

        @Published var dynamicVariables: DynamicVariables?
        @Published var uploadStats = false
        @Published var enactedSuggestion: Suggestion?
        @Published var recentGlucose: BloodGlucose?
        @Published var glucoseDelta: Int?
        @Published var overrideUnit: Bool = false
        @Published var closedLoop = false
        @Published var pumpSuspended = false
        @Published var isLooping = false
        @Published var statusTitle = ""
        @Published var lastLoopDate: Date = .distantPast
        @Published var tempRate: Decimal?
        @Published var battery: Battery?
        @Published var reservoir: Decimal?
        @Published var pumpName = ""
        @Published var pumpExpiresAtDate: Date?
        @Published var tempTarget: TempTarget?
        @Published var setupPump = false
        @Published var errorMessage: String? = nil
        @Published var errorDate: Date? = nil
        @Published var bolusProgress: Decimal?
        @Published var bolusAmount: Decimal?
        @Published var eventualBG: Int?
        @Published var carbsRequired: Decimal?
        @Published var allowManualTemp = false
        @Published var pumpDisplayState: PumpDisplayState?
        @Published var alarm: GlucoseAlarm?
        @Published var animatedBackground = false
        @Published var manualTempBasal = false
        @Published var smooth = false
        @Published var maxValue: Decimal = 1.2
        @Published var timeZone: TimeZone?
        @Published var totalBolus: Decimal = 0
        @Published var isStatusPopupPresented: Bool = false
        @Published var readings: [Readings] = []
        @Published var loopStatistics: (Int, Int, Double, String) = (0, 0, 0, "")
        @Published var standing: Bool = false
        @Published var preview: Bool = true
        @Published var useTargetButton: Bool = false
        @Published var overrideHistory: [OverrideHistory] = []
        @Published var overrides: [Override] = []
        @Published var alwaysUseColors: Bool = true
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
        @Published var openAPSSettings: Preferences?
        @Published var extended = true
        @Published var maxIOB: Decimal = 0
        @Published var maxCOB: Decimal = 0
        @Published var autoisf = false

        // Chart data
        var data = ChartModel(
            suggestion: nil,
            glucose: [],
            isManual: [],
            tempBasals: [],
            boluses: [],
            suspensions: [],
            announcement: [],
            hours: 24,
            maxBasal: 2,
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
            overrideHistory: [],
            minimumSMB: 0,
            maxBolus: 0,
            maxBolusValue: 1,
            useInsulinBars: true,
            screenHours: 6
        )

        override func subscribe() {
            setupGlucose()
            setupBasals()
            setupBoluses()
            setupSuspensions()
            setupPumpSettings()
            setupBasalProfile()
            setupTempTargets()
            setupCarbs()
            setupBattery()
            setupReservoir()
            setupAnnouncements()
            setupCurrentPumpTimezone()
            setupOverrideHistory()
            setupLoopStats()
            setupData()

            data.suggestion = provider.suggestion
            dynamicVariables = provider.dynamicVariables
            overrideHistory = provider.overrideHistory()
            uploadStats = settingsManager.settings.uploadStats
            enactedSuggestion = provider.enactedSuggestion
            data.units = settingsManager.settings.units
            allowManualTemp = !settingsManager.settings.closedLoop
            closedLoop = settingsManager.settings.closedLoop
            lastLoopDate = apsManager.lastLoopDate
            carbsRequired = data.suggestion?.carbsReq
            alarm = provider.glucoseStorage.alarm
            manualTempBasal = apsManager.isManualTempBasal
            setStatusTitle()
            setupCurrentTempTarget()
            smooth = settingsManager.settings.smoothGlucose
            maxValue = settingsManager.preferences.autosensMax
            data.lowGlucose = settingsManager.settings.low
            data.highGlucose = settingsManager.settings.high
            overrideUnit = settingsManager.settings.overrideHbA1cUnit
            data.displayXgridLines = settingsManager.settings.xGridLines
            data.displayYgridLines = settingsManager.settings.yGridLines
            data.thresholdLines = settingsManager.settings.rulerMarks
            useTargetButton = settingsManager.settings.useTargetButton
            data.screenHours = settingsManager.settings.hours
            alwaysUseColors = settingsManager.settings.alwaysUseColors
            useCalc = settingsManager.settings.useCalc
            data.minimumSMB = settingsManager.settings.minimumSMB
            data.maxBolus = settingsManager.pumpSettings.maxBolus
            data.useInsulinBars = settingsManager.settings.useInsulinBars
            skipGlucoseChart = settingsManager.settings.skipGlucoseChart
            displayDelta = settingsManager.settings.displayDelta
            extended = settingsManager.settings.extendHomeView
            maxIOB = settingsManager.preferences.maxIOB
            maxCOB = settingsManager.preferences.maxCOB
            autoisf = settingsManager.settings.autoisf
            hours = settingsManager.settings.hours

            broadcaster.register(GlucoseObserver.self, observer: self)
            broadcaster.register(SuggestionObserver.self, observer: self)
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PumpHistoryObserver.self, observer: self)
            broadcaster.register(PumpSettingsObserver.self, observer: self)
            broadcaster.register(BasalProfileObserver.self, observer: self)
            broadcaster.register(TempTargetsObserver.self, observer: self)
            broadcaster.register(CarbsObserver.self, observer: self)
            broadcaster.register(EnactedSuggestionObserver.self, observer: self)
            broadcaster.register(PumpBatteryObserver.self, observer: self)
            broadcaster.register(PumpReservoirObserver.self, observer: self)
            broadcaster.register(PumpTimeZoneObserver.self, observer: self)
            animatedBackground = settingsManager.settings.animatedBackground

            subscribeSetting(
                \.hours,
                on: $hours,
                initial: {
                    let value = max(min($0, 24), 2)
                    hours = value
                },
                map: { $0 }
            )

            timer.eventHandler = {
                DispatchQueue.main.async { [weak self] in
                    self?.data.timerDate = Date()
                    self?.setupCurrentTempTarget()
                }
            }
            timer.resume()

            apsManager.isLooping
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.isLooping, on: self)
                .store(in: &lifetime)

            apsManager.lastLoopDateSubject
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.lastLoopDate, on: self)
                .store(in: &lifetime)

            apsManager.pumpName
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.pumpName, on: self)
                .store(in: &lifetime)

            apsManager.pumpExpiresAtDate
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.pumpExpiresAtDate, on: self)
                .store(in: &lifetime)

            apsManager.lastError
                .receive(on: DispatchQueue.main)
                .map { [weak self] error in
                    self?.errorDate = error == nil ? nil : Date()
                    if let error = error {
                        info(.default, error.localizedDescription)
                    }
                    return error?.localizedDescription
                }
                .weakAssign(to: \.errorMessage, on: self)
                .store(in: &lifetime)

            apsManager.bolusProgress
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.bolusProgress, on: self)
                .store(in: &lifetime)

            apsManager.bolusAmount
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.bolusAmount, on: self)
                .store(in: &lifetime)

            apsManager.pumpDisplayState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self else { return }
                    self.pumpDisplayState = state
                    if state == nil {
                        self.reservoir = nil
                        self.battery = nil
                        self.pumpName = ""
                        self.pumpExpiresAtDate = nil
                        self.setupPump = false
                    } else {
                        self.setupBattery()
                        self.setupReservoir()
                    }
                }
                .store(in: &lifetime)

            $setupPump
                .sink { [weak self] show in
                    guard let self = self else { return }
                    if show, let pumpManager = self.provider.apsManager.pumpManager,
                       let bluetoothProvider = self.provider.apsManager.bluetoothManager
                    {
                        let view = PumpConfig.PumpSettingsView(
                            pumpManager: pumpManager,
                            bluetoothManager: bluetoothProvider,
                            completionDelegate: self,
                            setupDelegate: self
                        ).asAny()
                        self.router.mainSecondaryModalView.send(view)
                    } else {
                        self.router.mainSecondaryModalView.send(nil)
                    }
                }
                .store(in: &lifetime)
        }

        func addCarbs() {
            showModal(for: .addCarbs(editMode: false, override: false))
        }

        func runLoop() {
            provider.heartbeatNow()
        }

        func cancelBolus() {
            apsManager.cancelBolus()
        }

        func cancelProfile() {
            let os = OverrideStorage()
            // Is there a saved Override?
            if let activeOveride = os.fetchLatestOverride().first {
                let presetName = os.isPresetName()
                // Is the Override a Preset?
                if let preset = presetName {
                    if let duration = os.cancelProfile() {
                        // Update in Nightscout
                        nightscoutManager.editOverride(preset, duration, activeOveride.date ?? Date.now)
                    }
                } else if activeOveride.isPreset { // Because hard coded Hypo treatment isn't actually a preset
                    if let duration = os.cancelProfile() {
                        nightscoutManager.editOverride("📉", duration, activeOveride.date ?? Date.now)
                    }
                } else {
                    let nsString = activeOveride.percentage.formatted() != "100" ? activeOveride.percentage
                        .formatted() + " %" : "Custom"
                    if let duration = os.cancelProfile() {
                        nightscoutManager.editOverride(nsString, duration, activeOveride.date ?? Date.now)
                    }
                }
            }
            setupOverrideHistory()
        }

        func cancelTempTarget() {
            storage.storeTempTargets([TempTarget.cancel(at: Date())])
            coredataContext.performAndWait {
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

        func fetchPreferences() {
            let token = Token().getIdentifier()
            let database = Database(token: token)
            database.fetchPreferences("default")
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.service, "Preferences fetched from database. Profile: default")
                    case let .failure(error):
                        debug(.service, "Preferences fetched from database failed. Error: " + error.localizedDescription)
                    }
                }
            receiveValue: { self.openAPSSettings = $0 }
                .store(in: &lifetime)
        }

        private func setupGlucose() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.data.isManual = self.provider.manualGlucose(hours: self.filteredHours)
                self.data.glucose = self.provider.filteredGlucose(hours: self.filteredHours)
                self.readings = CoreDataStorage().fetchGlucose(interval: DateFilter().today)
                self.recentGlucose = self.data.glucose.last
                if self.data.glucose.count >= 2 {
                    self
                        .glucoseDelta = (self.recentGlucose?.glucose ?? 0) -
                        (self.data.glucose[self.data.glucose.count - 2].glucose ?? 0)
                } else {
                    self.glucoseDelta = nil
                }
                self.alarm = self.provider.glucoseStorage.alarm
            }
        }

        private func setupBasals() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.manualTempBasal = self.apsManager.isManualTempBasal
                self.data.tempBasals = self.provider.pumpHistory(hours: self.filteredHours).filter {
                    $0.type == .tempBasal || $0.type == .tempBasalDuration
                }
                let lastTempBasal = Array(self.data.tempBasals.suffix(2))
                guard lastTempBasal.count == 2 else {
                    self.tempRate = nil
                    return
                }

                guard let lastRate = lastTempBasal[0].rate, let lastDuration = lastTempBasal[1].durationMin else {
                    self.tempRate = nil
                    return
                }
                let lastDate = lastTempBasal[0].timestamp
                guard Date().timeIntervalSince(lastDate.addingTimeInterval(lastDuration.minutes.timeInterval)) < 0 else {
                    self.tempRate = nil
                    return
                }
                self.tempRate = lastRate
            }
        }

        private func setupBoluses() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.data.boluses = self.provider.pumpHistory(hours: self.filteredHours).filter {
                    $0.type == .bolus
                }
                self.data.maxBolusValue = self.data.boluses.compactMap(\.amount).max() ?? 1
            }
        }

        private func setupSuspensions() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.data.suspensions = self.provider.pumpHistory(hours: self.filteredHours).filter {
                    $0.type == .pumpSuspend || $0.type == .pumpResume
                }

                let last = self.data.suspensions.last
                let tbr = self.data.tempBasals.first { $0.timestamp > (last?.timestamp ?? .distantPast) }

                self.pumpSuspended = tbr == nil && last?.type == .pumpSuspend
            }
        }

        private func setupPumpSettings() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.data.maxBasal = self.provider.pumpSettings().maxBasal
            }
        }

        private func setupBasalProfile() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.data.autotunedBasalProfile = self.provider.autotunedBasalProfile()
                self.data.basalProfile = self.provider.basalProfile()
            }
        }

        private func setupTempTargets() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.manualTempBasal = self.apsManager.isManualTempBasal
                self.data.tempTargets = self.provider.tempTargets(hours: self.filteredHours)
            }
        }

        private func setupCarbs() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.data.carbs = self.provider.carbs(hours: self.filteredHours)
            }
        }

        private func setupOverrideHistory() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.data.overrideHistory = self.provider.overrideHistory()
            }
        }

        private func setupLoopStats() {
            let loopStats = CoreDataStorage().fetchLoopStats(interval: DateFilter().today)
            let loops = loopStats.compactMap({ each in each.loopStatus }).count
            let readings = CoreDataStorage().fetchGlucose(interval: DateFilter().today).compactMap({ each in each.glucose }).count
            let percentage = min(readings != 0 ? (Double(loops) / Double(readings) * 100) : 0, 100)
            // First loop date
            let time = (loopStats.last?.start ?? Date.now).addingTimeInterval(-5.minutes.timeInterval)

            let average = -1 * (time.timeIntervalSinceNow / 60) / max(Double(loops), 1)

            loopStatistics = (
                loops,
                readings,
                percentage,
                average.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) + " min"
            )
        }

        private func setupOverrides() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.overrides = self.provider.overrides()
            }
        }

        private func setupAnnouncements() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.data.announcement = self.provider.announcement(self.filteredHours)
            }
        }

        private func setStatusTitle() {
            guard let suggestion = data.suggestion else {
                statusTitle = "No suggestion"
                return
            }

            let dateFormatter = DateFormatter()
            dateFormatter.timeStyle = .short
            if closedLoop,
               let enactedSuggestion = enactedSuggestion,
               let timestamp = enactedSuggestion.timestamp,
               enactedSuggestion.deliverAt == suggestion.deliverAt, enactedSuggestion.recieved == true
            {
                statusTitle = NSLocalizedString("Enacted at", comment: "Headline in enacted pop up") + " " + dateFormatter
                    .string(from: timestamp)
            } else if let suggestedDate = suggestion.deliverAt {
                statusTitle = NSLocalizedString("Suggested at", comment: "Headline in suggested pop up") + " " + dateFormatter
                    .string(from: suggestedDate)
            } else {
                statusTitle = "Suggested"
            }

            eventualBG = suggestion.eventualBG
        }

        private func setupReservoir() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.reservoir = self.provider.pumpReservoir()
            }
        }

        private func setupBattery() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.battery = self.provider.pumpBattery()
            }
        }

        private func setupCurrentTempTarget() {
            tempTarget = provider.tempTarget()
        }

        private func setupCurrentPumpTimezone() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.timeZone = self.provider.pumpTimeZone()
            }
        }

        private func setupData() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let data = self.provider.reasons() {
                    self.iobData = data
                    self.carbData = data.map(\.cob).reduce(0, +)
                    self.iobs = data.map(\.iob).reduce(0, +)
                    neg = data.filter({ $0.iob < 0 }).count * 5
                    let tdds = CoreDataStorage().fetchTDD(interval: DateFilter().tenDays)
                    let yesterday = (tdds.first(where: {
                        ($0.timestamp ?? .distantFuture) <= Date().addingTimeInterval(-24.hours.timeInterval)
                    })?.tdd ?? 0) as Decimal
                    let oneDaysAgo = CoreDataStorage().fetchTDD(interval: DateFilter().today).last
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

                    if let tdds_ = self.provider.dynamicVariables {
                        tddAverage = ((tdds.first?.tdd ?? 0) as Decimal) - tdds_.average_total_data
                        tddActualAverage = tdds_.average_total_data
                    }
                }
            }
        }

        func openCGM() {
            guard var url = nightscoutManager.cgmURL else { return }

            switch url.absoluteString {
            case "http://127.0.0.1:1979":
                url = URL(string: "spikeapp://")!
            case "http://127.0.0.1:17580":
                url = URL(string: "diabox://")!
            case CGMType.libreTransmitter.appURL?.absoluteString:
                showModal(for: .libreConfig)
            default: break
            }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
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

extension Home.StateModel:
    GlucoseObserver,
    SuggestionObserver,
    SettingsObserver,
    PumpHistoryObserver,
    PumpSettingsObserver,
    BasalProfileObserver,
    TempTargetsObserver,
    CarbsObserver,
    EnactedSuggestionObserver,
    PumpBatteryObserver,
    PumpReservoirObserver,
    PumpTimeZoneObserver
{
    func glucoseDidUpdate(_: [BloodGlucose]) {
        setupGlucose()
        setupLoopStats()
    }

    func suggestionDidUpdate(_ suggestion: Suggestion) {
        data.suggestion = suggestion
        carbsRequired = suggestion.carbsReq
        setStatusTitle()
        setupOverrideHistory()
        setupLoopStats()
        setupData()
    }

    func settingsDidChange(_ settings: FreeAPSSettings) {
        allowManualTemp = !settings.closedLoop
        uploadStats = settingsManager.settings.uploadStats
        closedLoop = settingsManager.settings.closedLoop
        data.units = settingsManager.settings.units
        animatedBackground = settingsManager.settings.animatedBackground
        manualTempBasal = apsManager.isManualTempBasal
        data.smooth = settingsManager.settings.smoothGlucose
        data.lowGlucose = settingsManager.settings.low
        data.highGlucose = settingsManager.settings.high
        overrideUnit = settingsManager.settings.overrideHbA1cUnit
        data.displayXgridLines = settingsManager.settings.xGridLines
        data.displayYgridLines = settingsManager.settings.yGridLines
        data.thresholdLines = settingsManager.settings.rulerMarks
        useTargetButton = settingsManager.settings.useTargetButton
        data.screenHours = settingsManager.settings.hours
        alwaysUseColors = settingsManager.settings.alwaysUseColors
        useCalc = settingsManager.settings.useCalc
        data.minimumSMB = settingsManager.settings.minimumSMB
        data.maxBolus = settingsManager.pumpSettings.maxBolus
        data.useInsulinBars = settingsManager.settings.useInsulinBars
        skipGlucoseChart = settingsManager.settings.skipGlucoseChart
        displayDelta = settingsManager.settings.displayDelta
        extended = settingsManager.settings.extendHomeView
        maxIOB = settingsManager.preferences.maxIOB
        maxCOB = settingsManager.preferences.maxCOB
        autoisf = settingsManager.settings.autoisf
        hours = settingsManager.settings.hours
        setupGlucose()
        setupOverrideHistory()
        setupData()
    }

    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        setupBasals()
        setupBoluses()
        setupSuspensions()
        setupAnnouncements()
    }

    func pumpSettingsDidChange(_: PumpSettings) {
        setupPumpSettings()
    }

    func basalProfileDidChange(_: [BasalProfileEntry]) {
        setupBasalProfile()
    }

    func tempTargetsDidUpdate(_: [TempTarget]) {
        setupTempTargets()
    }

    func carbsDidUpdate(_: [CarbsEntry]) {
        setupCarbs()
        setupAnnouncements()
    }

    func enactedSuggestionDidUpdate(_ suggestion: Suggestion) {
        enactedSuggestion = suggestion
        setStatusTitle()
        setupOverrideHistory()
        setupLoopStats()
        setupData()
    }

    func pumpBatteryDidChange(_: Battery) {
        setupBattery()
    }

    func pumpReservoirDidChange(_: Decimal) {
        setupReservoir()
    }

    func pumpTimeZoneDidChange(_: TimeZone) {
        setupCurrentPumpTimezone()
    }
}

extension Home.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        setupPump = false
    }
}

extension Home.StateModel: PumpManagerOnboardingDelegate {
    func pumpManagerOnboarding(didCreatePumpManager pumpManager: PumpManagerUI) {
        provider.apsManager.pumpManager = pumpManager
        if let insulinType = pumpManager.status.insulinType {
            settingsManager.updateInsulinCurve(insulinType)
        }
    }

    func pumpManagerOnboarding(didOnboardPumpManager _: PumpManagerUI) {
        // nothing to do
    }

    func pumpManagerOnboarding(didPauseOnboarding _: PumpManagerUI) {
        // TODO:
    }
}
