import Foundation

struct FreeAPSSettings: JSON, Equatable, Sendable {
    var units: GlucoseUnits = .mmolL
    var closedLoop: Bool = false
    var allowAnnouncements: Bool = false
    var useAutotune: Bool = false
    var isUploadEnabled: Bool = false
    var glucoseUploadSchedule = UploadSchedule()
    var treatmentsAndLoopsUploadSchedule = UploadSchedule()
    var deviceStatusUploadSchedule = UploadSchedule()
    var nightscoutFetchEnabled: Bool = true
    var debugOptions: Bool = false
    var insulinReqPercentage: Decimal = 70
    var skipBolusScreenAfterCarbs: Bool = false
    var displayHR: Bool = false
    var useCalendar: Bool = false
    var displayCalendarIOBandCOB: Bool = false
    var displayCalendarEmojis: Bool = false
    var glucoseBadge: Bool = false
    var glucoseNotificationsAlways: Bool = false
    var useAlarmSound: Bool = false
    var addSourceInfoToGlucoseNotifications: Bool = false
    var lowGlucose: Decimal = 72
    var highGlucose: Decimal = 270
    var carbsRequiredThreshold: Decimal = 10
    var animatedBackground: Bool = false
    var useFPUconversion: Bool = true
    /// Convert a meal's fat and protein into future carb equivalents (Warsaw method). Off, the
    /// macros are still saved with the meal but no carb-equivalent entries are created from them.
    var fatProteinConversion: Bool = true
    var individualAdjustmentFactor: Decimal = 0.5
    var timeCap: Int = 8
    var minuteInterval: Int = 30
    var delay: Int = 60
    var useAppleHealth: Bool = false
    var glucoseSmoothing = GlucoseSmoothingSettings()
    var displayOnWatch: AwConfig = .BGTarget
    var overrideHbA1cUnit: Bool = false
    var high: Decimal = 145
    var low: Decimal = 70
    var uploadStats: Bool = false
    var uploadLogs: Bool = false
    /// Opt-in crash reports to open-iaps.app (Sharing screen). Independent of the other
    /// sharing toggles: a crash report needs nothing else to be useful.
    var uploadCrashReports: Bool = false
    var hours: Int = 6
    var xGridLines: Bool = true
    var yGridLines: Bool = true
    var yGridLabels: Bool = true
    var rulerMarks: Bool = false
    var inRangeAreaFill: Bool = false
    var secondaryChartBackdrop: Bool = true
    var insulinActivityGridLines: Bool = true
    var insulinActivityLabels: Bool = true
    var chartGlucosePeaks: Bool = false
    var showPredictionsLegend: Bool = true
    var maxCarbs: Decimal = 200
    var displayFatAndProteinOnWatch: Bool = false
    var confirmBolusFaster: Bool = false
    var onlyAutotuneBasals: Bool = false
    var overrideFactor: Decimal = 0.8
    var useCalc: Bool = true
    var fattyMeals: Bool = false
    var fattyMealFactor: Decimal = 0.7
    var displayPredictions: Bool = true
    var useLiveActivity: Bool = false
    var liveActivityChart = false
    var liveActivityChartShowPredictions = true
    var liveActivityWatchChart: Bool = false
    var liveActivityWatchPredictions: Bool = true
    var liveActivityWatchDelta: Bool = true
    var liveActivityWatchEventual: Bool = true
    var useTargetButton: Bool = false
    var alwaysUseColors: Bool = true
    var timeSettings: Bool = true
    var disable15MinTrend: Bool = false
    var hidePredictions: Bool = false
    // Sounds
    var hypoSound: String = "Default"
    var hyperSound: String = "Default"
    var ascending: String = "Default"
    var descending: String = "Default"
    var carbSound: String = "Default"
    var bolusFailure: String = "Silent"
    var missingLoops = true
    // Alerts
    var lowAlert: Bool = true
    var highAlert: Bool = true
    var ascendingAlert: Bool = true
    var descendingAlert: Bool = true
    var carbsRequiredAlert: Bool = true
    //
    var profilesOrTempTargets: Bool = true
    var allowBolusShortcut: Bool = false
    var allowedRemoteBolusAmount: Decimal = 0.0
    var eventualBG: Bool = true
    var minumimPrediction: Bool = true
    var minimumSMB: Decimal = 0.3
    var useInsulinBars: Bool = false
    var birthDate = Date.distantPast
    var sexSetting: Int = 3
    // Demographics — weight stored canonically in kg, height in cm (0 = unset).
    // Display unit is a separate preference; default metric.
    var weight: Decimal = 0
    var height: Decimal = 0
    var weightInLb: Bool = false
    var heightInFtIn: Bool = false
    // whether the daily Statistics upload carries the sex and the age (Settings › Sharing); a value set is not shared
    // until its toggle is on, and a value cleared in Settings › Demographics turns its toggle off
    // (`DemographicsSharing.settingSex`, `settingBirthDate`). The settings backup carries all the demographics (the
    // weight and the height too) either way.
    var shareSex: Bool = false
    var shareAge: Bool = false
    /// The share toggles were set from the values, and the birth date turned into a day, once
    /// (`DataMigrations.migrateDemographicsSharing`): it runs while the settings file lacks this key (an older
    /// build's), whatever its value, so a file this build wrote without the migration (a fresh install, a restored
    /// older backup: false) is never migrated. A downgrade drops the key (older builds don't know it), so the next
    /// upgrade runs the migration again, from the values as they are then: a toggle turned off since comes back on
    /// while its value is set, and the birth date is converted again (`DemographicsSharing.legacyBirthDay`).
    var demographicsSharingMigrated: Bool = false
    var displayDelta: Bool = false
    var profileID: String = "Hypo Treatment"
    var allowDilution: Bool = false
    var hideInsulinBadge: Bool = false
    var extended_overrides = false
    var displayExpiration = false
    var displaySAGE = true
    var sensorDays: Double = 10
    var fpus: Bool = true
    var fpuAmounts: Bool = false
    var carbButton: Bool = true
    var profileButton: Bool = true
    var showInsulinActivity: Bool = false
    var showCobChart: Bool = false
    // failed loops / device errors / missed readings on the main chart
    var loopEventsPlacement: LoopEventsPlacement = .hidden
    // the stats bar on Home: its range, Today or 24 h, picked on the card (Statistics never changes it). The other Home
    // cards have none: the Loops card shows the last 24 h, the insulin and meal cards Today
    var homeStatsRange: StatsPeriod = .last24h
    // the On board card on Home (the last 24 h): its glucose and carbs-on-board lanes, picked in its menu (IOB always)
    var homeOnBoardGlucose: Bool = true
    var homeOnBoardCOB: Bool = true
    // the usual day on Statistics' Day tab: shown or not, and over which of the last 14 / 30 / 90 days
    var statsUsualDay: Bool = false
    var statsUsualDayPeriod: StatsPeriod = .days14
    var glucoseOverrideThreshold: Decimal = 100
    var glucoseOverrideThresholdActive: Bool = false
    var glucoseOverrideThresholdActiveDown: Bool = false
    var glucoseOverrideThresholdDown: Decimal = 100
    var noCarbs: Bool = false
    var useCarbBars: Bool = false
    // ColorScheme
    var lightMode: LightMode = .auto
    // Auto ISF
    var autoisf: Bool = false
    var autocr: Bool = false
    var smbDeliveryRatioBGrange: Decimal = 0
    var smbDeliveryRatioMin: Decimal = 0.5
    var smbDeliveryRatioMax: Decimal = 0.5
    var autoISFhourlyChange: Decimal = 1
    var higherISFrangeWeight: Decimal = 0
    var lowerISFrangeWeight: Decimal = 0
    var postMealISFweight: Decimal = 0
    var enableBGacceleration: Bool = true
    var autoisfOneMinuteReadings: Bool = false
    var bgAccelISFweight: Decimal = 0
    var bgBrakeISFweight: Decimal = 0.10
    var iobThresholdPercent: Decimal = 100
    var autoisf_max: Decimal = 1.2
    var autoisf_min: Decimal = 0.8
    // B30
    var use_B30 = false
    var iTime_Start_Bolus: Decimal = 1.5
    var iTime_target: Decimal = 90
    var b30targetLevel: Decimal = 100
    var b30upperLimit: Decimal = 130
    var b30upperdelta: Decimal = 8
    var b30factor: Decimal = 5
    var b30_duration: Decimal = 30
    // Keto protection
    var ketoProtect: Bool = false
    var variableKetoProtect: Bool = false
    var ketoProtectBasalPercent: Decimal = 20
    var ketoProtectAbsolut: Bool = false
    var ketoProtectBasalAbsolut: Decimal = 0
    // 1-min loops
    var allowOneMinuteLoop: Bool = false // allow running loops every minute

    var calibrationRobustFit: Bool = false
    var calibrationRelaxLimits: Bool = false

    var ai: Bool = true
    var mealViewMicronutrients: Bool = false
    var nightTime = NightTimeConfiguration.default
}

extension FreeAPSSettings {
    var autoisfEffective: Bool {
        autoisf && !isNighttime
    }

    // TODO: the name is a little misleading - this returns true when "disable aisf during nighttime" is "on", AND now is nighttime
    var isNighttime: Bool {
        guard nightTime.enabled else { return false }

        let calendar = Calendar.current.dateComponents([.hour, .minute], from: .now)
        guard let h = calendar.hour, let m = calendar.minute else { return false }

        let now = h * 60 + m
        let start = nightTime.startHour * 60 + nightTime.startMinute
        let end = nightTime.endHour * 60 + nightTime.endMinute

        return (start > end && (now >= start || now < end)) ||
            (start <= end && now >= start && now < end)
    }

    var ketoProtectSettings: KetoProtectSettings {
        KetoProtectSettings(
            ketoProtect: ketoProtect,
            variableKetoProtect: variableKetoProtect,
            ketoProtectBasalPercent: ketoProtectBasalPercent,
            ketoProtectAbsolut: ketoProtectAbsolut,
            ketoProtectBasalAbsolut: ketoProtectBasalAbsolut
        )
    }
}

extension FreeAPSSettings: Decodable {
    // Needed to decode incomplete JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var settings = FreeAPSSettings()

        if let units = try? container.decode(GlucoseUnits.self, forKey: .units) {
            settings.units = units
        }

        if let closedLoop = try? container.decode(Bool.self, forKey: .closedLoop) {
            settings.closedLoop = closedLoop
        }

        if let allowAnnouncements = try? container.decode(Bool.self, forKey: .allowAnnouncements) {
            settings.allowAnnouncements = allowAnnouncements
        }

        if let useAutotune = try? container.decode(Bool.self, forKey: .useAutotune) {
            settings.useAutotune = useAutotune
        }

        if let isUploadEnabled = try? container.decode(Bool.self, forKey: .isUploadEnabled) {
            settings.isUploadEnabled = isUploadEnabled
        }

        if let glucoseUploadSchedule = try? container.decode(UploadSchedule.self, forKey: .glucoseUploadSchedule) {
            settings.glucoseUploadSchedule = glucoseUploadSchedule
        }

        if let treatmentsAndLoopsUploadSchedule = try? container.decode(
            UploadSchedule.self,
            forKey: .treatmentsAndLoopsUploadSchedule
        ) {
            settings.treatmentsAndLoopsUploadSchedule = treatmentsAndLoopsUploadSchedule
        }

        if let deviceStatusUploadSchedule = try? container.decode(UploadSchedule.self, forKey: .deviceStatusUploadSchedule) {
            settings.deviceStatusUploadSchedule = deviceStatusUploadSchedule
        }

        if let nightscoutFetchEnabled = try? container.decode(Bool.self, forKey: .nightscoutFetchEnabled) {
            settings.nightscoutFetchEnabled = nightscoutFetchEnabled
        }

        if let debugOptions = try? container.decode(Bool.self, forKey: .debugOptions) {
            settings.debugOptions = debugOptions
        }

        if let fpus = try? container.decode(Bool.self, forKey: .fpus) {
            settings.fpus = fpus
        }

        if let hidePredictions = try? container.decode(Bool.self, forKey: .hidePredictions) {
            settings.hidePredictions = hidePredictions
        }

        if let useCarbBars = try? container.decode(Bool.self, forKey: .useCarbBars) {
            settings.useCarbBars = useCarbBars
        }

        if let fpuAmounts = try? container.decode(Bool.self, forKey: .fpuAmounts) {
            settings.fpuAmounts = fpuAmounts
        }

        if let insulinReqPercentage = try? container.decode(Decimal.self, forKey: .insulinReqPercentage) {
            settings.insulinReqPercentage = insulinReqPercentage
        }

        if let skipBolusScreenAfterCarbs = try? container.decode(Bool.self, forKey: .skipBolusScreenAfterCarbs) {
            settings.skipBolusScreenAfterCarbs = skipBolusScreenAfterCarbs
        }

        if let noCarbs = try? container.decode(Bool.self, forKey: .noCarbs) {
            settings.noCarbs = noCarbs
        }

        if let displayHR = try? container.decode(Bool.self, forKey: .displayHR) {
            settings.displayHR = displayHR
            // compatibility if displayOnWatch is not available in json files
            settings.displayOnWatch = (displayHR == true) ? AwConfig.HR : AwConfig.BGTarget
        }

        if let displayOnWatch = try? container.decode(AwConfig.self, forKey: .displayOnWatch) {
            settings.displayOnWatch = displayOnWatch
        }

        if let useCalendar = try? container.decode(Bool.self, forKey: .useCalendar) {
            settings.useCalendar = useCalendar
        }

        if let displayCalendarIOBandCOB = try? container.decode(Bool.self, forKey: .displayCalendarIOBandCOB) {
            settings.displayCalendarIOBandCOB = displayCalendarIOBandCOB
        }

        if let displayCalendarEmojis = try? container.decode(Bool.self, forKey: .displayCalendarEmojis) {
            settings.displayCalendarEmojis = displayCalendarEmojis
        }

        if let useAppleHealth = try? container.decode(Bool.self, forKey: .useAppleHealth) {
            settings.useAppleHealth = useAppleHealth
        }

        if let glucoseBadge = try? container.decode(Bool.self, forKey: .glucoseBadge) {
            settings.glucoseBadge = glucoseBadge
        }

        if let useFPUconversion = try? container.decode(Bool.self, forKey: .useFPUconversion) {
            settings.useFPUconversion = useFPUconversion
        }

        if let fatProteinConversion = try? container.decode(Bool.self, forKey: .fatProteinConversion) {
            settings.fatProteinConversion = fatProteinConversion
        }

        if let individualAdjustmentFactor = try? container.decode(Decimal.self, forKey: .individualAdjustmentFactor) {
            settings.individualAdjustmentFactor = individualAdjustmentFactor
        }

        if let useCalc = try? container.decode(Bool.self, forKey: .useCalc) {
            settings.useCalc = useCalc
        }

        if let fattyMeals = try? container.decode(Bool.self, forKey: .fattyMeals) {
            settings.fattyMeals = fattyMeals
        }

        if let lowAlert = try? container.decode(Bool.self, forKey: .lowAlert) {
            settings.lowAlert = lowAlert
        }

        if let highAlert = try? container.decode(Bool.self, forKey: .highAlert) {
            settings.highAlert = highAlert
        }

        if let ascendingAlert = try? container.decode(Bool.self, forKey: .ascendingAlert) {
            settings.ascendingAlert = ascendingAlert
        }

        if let descendingAlert = try? container.decode(Bool.self, forKey: .descendingAlert) {
            settings.descendingAlert = descendingAlert
        }

        if let carbsRequiredAlert = try? container.decode(Bool.self, forKey: .carbsRequiredAlert) {
            settings.carbsRequiredAlert = carbsRequiredAlert
        }

        if let disable15MinTrend = try? container.decode(Bool.self, forKey: .disable15MinTrend) {
            settings.disable15MinTrend = disable15MinTrend
        }

        if let fattyMealFactor = try? container.decode(Decimal.self, forKey: .fattyMealFactor) {
            settings.fattyMealFactor = fattyMealFactor
        }

        if let overrideFactor = try? container.decode(Decimal.self, forKey: .overrideFactor) {
            settings.overrideFactor = overrideFactor
        }

        if let timeCap = try? container.decode(Int.self, forKey: .timeCap) {
            settings.timeCap = timeCap
        }

        if let minuteInterval = try? container.decode(Int.self, forKey: .minuteInterval) {
            settings.minuteInterval = minuteInterval
        }

        if let delay = try? container.decode(Int.self, forKey: .delay) {
            settings.delay = delay
        }

        if let glucoseNotificationsAlways = try? container.decode(Bool.self, forKey: .glucoseNotificationsAlways) {
            settings.glucoseNotificationsAlways = glucoseNotificationsAlways
        }

        if let useAlarmSound = try? container.decode(Bool.self, forKey: .useAlarmSound) {
            settings.useAlarmSound = useAlarmSound
        }

        if let carbButton = try? container.decode(Bool.self, forKey: .carbButton) {
            settings.carbButton = carbButton
        }

        if let profileButton = try? container.decode(Bool.self, forKey: .profileButton) {
            settings.profileButton = profileButton
        }

        if let showInsulinActivity = try? container.decode(Bool.self, forKey: .showInsulinActivity) {
            settings.showInsulinActivity = showInsulinActivity
        }

        if let showCobChart = try? container.decode(Bool.self, forKey: .showCobChart) {
            settings.showCobChart = showCobChart
        }

        if let loopEventsPlacement = try? container.decode(LoopEventsPlacement.self, forKey: .loopEventsPlacement) {
            settings.loopEventsPlacement = loopEventsPlacement
        }

        // only a range the card offers: an older build's 7–90 d (or Statistics' periods) start on 24 h
        if let homeStatsRange = try? container.decode(StatsPeriod.self, forKey: .homeStatsRange),
           StatsPeriod.homeStatsRanges.contains(homeStatsRange)
        {
            settings.homeStatsRange = homeStatsRange
        }

        if let homeOnBoardGlucose = try? container.decode(Bool.self, forKey: .homeOnBoardGlucose) {
            settings.homeOnBoardGlucose = homeOnBoardGlucose
        }

        if let homeOnBoardCOB = try? container.decode(Bool.self, forKey: .homeOnBoardCOB) {
            settings.homeOnBoardCOB = homeOnBoardCOB
        }

        if let statsUsualDay = try? container.decode(Bool.self, forKey: .statsUsualDay) {
            settings.statsUsualDay = statsUsualDay
        }

        // only a period the Day tab's usual day offers
        if let statsUsualDayPeriod = try? container.decode(StatsPeriod.self, forKey: .statsUsualDayPeriod),
           StatsPeriod.usualDayPeriods.contains(statsUsualDayPeriod)
        {
            settings.statsUsualDayPeriod = statsUsualDayPeriod
        }

        if let addSourceInfoToGlucoseNotifications = try? container.decode(
            Bool.self,
            forKey: .addSourceInfoToGlucoseNotifications
        ) {
            settings.addSourceInfoToGlucoseNotifications = addSourceInfoToGlucoseNotifications
        }

        if let lightMode = try? container.decode(LightMode.self, forKey: .lightMode) {
            settings.lightMode = lightMode
        }

        if let lowGlucose = try? container.decode(Decimal.self, forKey: .lowGlucose) {
            settings.lowGlucose = lowGlucose
        }

        if let highGlucose = try? container.decode(Decimal.self, forKey: .highGlucose) {
            settings.highGlucose = highGlucose
        }

        if let carbsRequiredThreshold = try? container.decode(Decimal.self, forKey: .carbsRequiredThreshold) {
            settings.carbsRequiredThreshold = carbsRequiredThreshold
        }

        if let animatedBackground = try? container.decode(Bool.self, forKey: .animatedBackground) {
            settings.animatedBackground = animatedBackground
        }

        if let glucoseSmoothing = try? container.decode(GlucoseSmoothingSettings.self, forKey: .glucoseSmoothing) {
            settings.glucoseSmoothing = glucoseSmoothing
        }

        if let low = try? container.decode(Decimal.self, forKey: .low) {
            settings.low = low
        }

        if let high = try? container.decode(Decimal.self, forKey: .high) {
            settings.high = high
        }

        if let sensorDays = try? container.decode(Double.self, forKey: .sensorDays) {
            settings.sensorDays = sensorDays
        }

        if let uploadStats = try? container.decode(Bool.self, forKey: .uploadStats) {
            settings.uploadStats = uploadStats
        }

        if let hours = try? container.decode(Int.self, forKey: .hours) {
            settings.hours = hours
        }

        if let xGridLines = try? container.decode(Bool.self, forKey: .xGridLines) {
            settings.xGridLines = xGridLines
        }

        if let yGridLines = try? container.decode(Bool.self, forKey: .yGridLines) {
            settings.yGridLines = yGridLines
        }

        if let yGridLabels = try? container.decode(Bool.self, forKey: .yGridLabels) {
            settings.yGridLabels = yGridLabels
        }

        if let rulerMarks = try? container.decode(Bool.self, forKey: .rulerMarks) {
            settings.rulerMarks = rulerMarks
        }

        if let inRangeAreaFill = try? container.decode(Bool.self, forKey: .inRangeAreaFill) {
            settings.inRangeAreaFill = inRangeAreaFill
        }

        if let secondaryChartBackdrop = try? container.decode(Bool.self, forKey: .secondaryChartBackdrop) {
            settings.secondaryChartBackdrop = secondaryChartBackdrop
        }

        if let insulinActivityGridLines = try? container.decode(Bool.self, forKey: .insulinActivityGridLines) {
            settings.insulinActivityGridLines = insulinActivityGridLines
        }

        if let insulinActivityLabels = try? container.decode(Bool.self, forKey: .insulinActivityLabels) {
            settings.insulinActivityLabels = insulinActivityLabels
        }

        if let chartGlucosePeaks = try? container.decode(Bool.self, forKey: .chartGlucosePeaks) {
            settings.chartGlucosePeaks = chartGlucosePeaks
        }

        if let showPredictionsLegend = try? container.decode(Bool.self, forKey: .showPredictionsLegend) {
            settings.showPredictionsLegend = showPredictionsLegend
        }

        if let overrideHbA1cUnit = try? container.decode(Bool.self, forKey: .overrideHbA1cUnit) {
            settings.overrideHbA1cUnit = overrideHbA1cUnit
        }

        if let maxCarbs = try? container.decode(Decimal.self, forKey: .maxCarbs) {
            settings.maxCarbs = maxCarbs
        }

        if let displayFatAndProteinOnWatch = try? container.decode(Bool.self, forKey: .displayFatAndProteinOnWatch) {
            settings.displayFatAndProteinOnWatch = displayFatAndProteinOnWatch
        }

        if let confirmBolusFaster = try? container.decode(Bool.self, forKey: .confirmBolusFaster) {
            settings.confirmBolusFaster = confirmBolusFaster
        }

        if let onlyAutotuneBasals = try? container.decode(Bool.self, forKey: .onlyAutotuneBasals) {
            settings.onlyAutotuneBasals = onlyAutotuneBasals
        }

        if let displayPredictions = try? container.decode(Bool.self, forKey: .displayPredictions) {
            settings.displayPredictions = displayPredictions
        }

        if let useLiveActivity = try? container.decode(Bool.self, forKey: .useLiveActivity) {
            settings.useLiveActivity = useLiveActivity
        }

        // --- live activity chart

        if let liveActivityChart = try? container.decode(Bool.self, forKey: .liveActivityChart) {
            settings.liveActivityChart = liveActivityChart
        }

        if let liveActivityChartShowPredictions = try? container.decode(Bool.self, forKey: .liveActivityChartShowPredictions) {
            settings.liveActivityChartShowPredictions = liveActivityChartShowPredictions
        }

        if let liveActivityWatchChart = try? container.decode(Bool.self, forKey: .liveActivityWatchChart) {
            settings.liveActivityWatchChart = liveActivityWatchChart
        }

        if let liveActivityWatchPredictions = try? container.decode(Bool.self, forKey: .liveActivityWatchPredictions) {
            settings.liveActivityWatchPredictions = liveActivityWatchPredictions
        }

        if let liveActivityWatchDelta = try? container.decode(Bool.self, forKey: .liveActivityWatchDelta) {
            settings.liveActivityWatchDelta = liveActivityWatchDelta
        }

        if let liveActivityWatchEventual = try? container.decode(Bool.self, forKey: .liveActivityWatchEventual) {
            settings.liveActivityWatchEventual = liveActivityWatchEventual
        }

        // ----

        if let useTargetButton = try? container.decode(Bool.self, forKey: .useTargetButton) {
            settings.useTargetButton = useTargetButton
        }

        if let alwaysUseColors = try? container.decode(Bool.self, forKey: .alwaysUseColors) {
            settings.alwaysUseColors = alwaysUseColors
        }

        if let timeSettings = try? container.decode(Bool.self, forKey: .timeSettings) {
            settings.timeSettings = timeSettings
        }

        if let hypoSound = try? container.decode(String.self, forKey: .hypoSound) {
            settings.hypoSound = hypoSound
        }

        if let hyperSound = try? container.decode(String.self, forKey: .hyperSound) {
            settings.hyperSound = hyperSound
        }

        if let ascending = try? container.decode(String.self, forKey: .ascending) {
            settings.ascending = ascending
        }

        if let descending = try? container.decode(String.self, forKey: .descending) {
            settings.descending = descending
        }

        if let carbSound = try? container.decode(String.self, forKey: .carbSound) {
            settings.carbSound = carbSound
        }

        if let bolusFailure = try? container.decode(String.self, forKey: .bolusFailure) {
            settings.bolusFailure = bolusFailure
        }

        if let missingLoops = try? container.decode(Bool.self, forKey: .missingLoops) {
            settings.missingLoops = missingLoops
        }

        if let profilesOrTempTargets = try? container.decode(Bool.self, forKey: .profilesOrTempTargets) {
            settings.profilesOrTempTargets = profilesOrTempTargets
        }

        if let allowBolusShortcut = try? container.decode(Bool.self, forKey: .allowBolusShortcut) {
            settings.allowBolusShortcut = allowBolusShortcut
        }

        if let allowedRemoteBolusAmount = try? container.decode(Decimal.self, forKey: .allowedRemoteBolusAmount) {
            settings.allowedRemoteBolusAmount = allowedRemoteBolusAmount
        }

        if let eventualBG = try? container.decode(Bool.self, forKey: .eventualBG) {
            settings.eventualBG = eventualBG
        }

        if let minumimPrediction = try? container.decode(Bool.self, forKey: .minumimPrediction) {
            settings.minumimPrediction = minumimPrediction
        }

        if let minimumSMB = try? container.decode(Decimal.self, forKey: .minimumSMB) {
            settings.minimumSMB = minimumSMB
        }

        if let useInsulinBars = try? container.decode(Bool.self, forKey: .useInsulinBars) {
            settings.useInsulinBars = useInsulinBars
        }

        if let birthDate = try? container.decode(Date.self, forKey: .birthDate) {
            settings.birthDate = birthDate
        }

        if let sexSetting = try? container.decode(Int.self, forKey: .sexSetting) {
            settings.sexSetting = sexSetting
        }

        if let weight = try? container.decode(Decimal.self, forKey: .weight) {
            settings.weight = weight
        }

        if let height = try? container.decode(Decimal.self, forKey: .height) {
            settings.height = height
        }

        if let weightInLb = try? container.decode(Bool.self, forKey: .weightInLb) {
            settings.weightInLb = weightInLb
        }

        if let heightInFtIn = try? container.decode(Bool.self, forKey: .heightInFtIn) {
            settings.heightInFtIn = heightInFtIn
        }

        if let shareSex = try? container.decode(Bool.self, forKey: .shareSex) {
            settings.shareSex = shareSex
        }

        if let shareAge = try? container.decode(Bool.self, forKey: .shareAge) {
            settings.shareAge = shareAge
        }

        if let demographicsSharingMigrated = try? container.decode(Bool.self, forKey: .demographicsSharingMigrated) {
            settings.demographicsSharingMigrated = demographicsSharingMigrated
        }

        if let displayDelta = try? container.decode(Bool.self, forKey: .displayDelta) {
            settings.displayDelta = displayDelta
        }

        if let profileID = try? container.decode(String.self, forKey: .profileID) {
            settings.profileID = profileID
        }

        if let hideInsulinBadge = try? container.decode(Bool.self, forKey: .hideInsulinBadge) {
            settings.hideInsulinBadge = hideInsulinBadge
        }

        if let allowDilution = try? container.decode(Bool.self, forKey: .allowDilution) {
            settings.allowDilution = allowDilution
        }

        if let extended_overrides = try? container.decode(Bool.self, forKey: .extended_overrides) {
            settings.extended_overrides = extended_overrides
        }

        if let displayExpiration = try? container.decode(Bool.self, forKey: .displayExpiration) {
            settings.displayExpiration = displayExpiration
        }

        if let displaySAGE = try? container.decode(Bool.self, forKey: .displaySAGE) {
            settings.displaySAGE = displaySAGE
        }
        // AutoISF
        if let autoisf = try? container.decode(Bool.self, forKey: .autoisf) {
            settings.autoisf = autoisf
        }

        if let autocr = try? container.decode(Bool.self, forKey: .autocr) {
            settings.autocr = autocr
        }

        if let enableBGacceleration = try? container.decode(Bool.self, forKey: .enableBGacceleration) {
            settings.enableBGacceleration = enableBGacceleration
        }

        if let autoisfOneMinuteReadings = try? container.decode(Bool.self, forKey: .autoisfOneMinuteReadings) {
            settings.autoisfOneMinuteReadings = autoisfOneMinuteReadings
        }

        if let use_B30 = try? container.decode(Bool.self, forKey: .use_B30) {
            settings.use_B30 = use_B30
        }

        if let smbDeliveryRatioBGrange = try? container.decode(Decimal.self, forKey: .smbDeliveryRatioBGrange) {
            settings.smbDeliveryRatioBGrange = smbDeliveryRatioBGrange
        }

        if let smbDeliveryRatioMin = try? container.decode(Decimal.self, forKey: .smbDeliveryRatioMin) {
            settings.smbDeliveryRatioMin = smbDeliveryRatioMin
        }

        if let smbDeliveryRatioMax = try? container.decode(Decimal.self, forKey: .smbDeliveryRatioMax) {
            settings.smbDeliveryRatioMax = smbDeliveryRatioMax
        }

        if let autoISFhourlyChange = try? container.decode(Decimal.self, forKey: .autoISFhourlyChange) {
            settings.autoISFhourlyChange = autoISFhourlyChange
        }

        if let higherISFrangeWeight = try? container.decode(Decimal.self, forKey: .higherISFrangeWeight) {
            settings.higherISFrangeWeight = higherISFrangeWeight
        }

        if let lowerISFrangeWeight = try? container.decode(Decimal.self, forKey: .lowerISFrangeWeight) {
            settings.lowerISFrangeWeight = lowerISFrangeWeight
        }

        if let postMealISFweight = try? container.decode(Decimal.self, forKey: .postMealISFweight) {
            settings.postMealISFweight = postMealISFweight
        }

        if let bgAccelISFweight = try? container.decode(Decimal.self, forKey: .bgAccelISFweight) {
            settings.bgAccelISFweight = bgAccelISFweight
        }

        if let bgBrakeISFweight = try? container.decode(Decimal.self, forKey: .bgBrakeISFweight) {
            settings.bgBrakeISFweight = bgBrakeISFweight
        }

        if let iTime_Start_Bolus = try? container.decode(Decimal.self, forKey: .iTime_Start_Bolus) {
            settings.iTime_Start_Bolus = iTime_Start_Bolus
        }

        if let b30targetLevel = try? container.decode(Decimal.self, forKey: .b30targetLevel) {
            settings.b30targetLevel = b30targetLevel
        }

        if let b30upperLimit = try? container.decode(Decimal.self, forKey: .b30upperLimit) {
            settings.b30upperLimit = b30upperLimit
        }

        if let b30upperdelta = try? container.decode(Decimal.self, forKey: .b30upperdelta) {
            settings.b30upperdelta = b30upperdelta
        }

        if let b30factor = try? container.decode(Decimal.self, forKey: .b30factor) {
            settings.b30factor = b30factor
        }

        if let iTime_target = try? container.decode(Decimal.self, forKey: .iTime_target) {
            settings.iTime_target = iTime_target
        }

        if let b30_duration = try? container.decode(Decimal.self, forKey: .b30_duration) {
            settings.b30_duration = b30_duration
        }

        if let iobThresholdPercent = try? container.decode(Decimal.self, forKey: .iobThresholdPercent) {
            settings.iobThresholdPercent = iobThresholdPercent
        }

        if let autoisf_max = try? container.decode(Decimal.self, forKey: .autoisf_max) {
            settings.autoisf_max = autoisf_max
        }

        if let autoisf_min = try? container.decode(Decimal.self, forKey: .autoisf_min) {
            settings.autoisf_min = autoisf_min
        }

        if let glucoseOverrideThreshold = try? container.decode(Decimal.self, forKey: .glucoseOverrideThreshold) {
            settings.glucoseOverrideThreshold = glucoseOverrideThreshold
        }

        if let glucoseOverrideThresholdActive = try? container.decode(Bool.self, forKey: .glucoseOverrideThresholdActive) {
            settings.glucoseOverrideThresholdActive = glucoseOverrideThresholdActive
        }

        if let glucoseOverrideThresholdDown = try? container.decode(Decimal.self, forKey: .glucoseOverrideThresholdDown) {
            settings.glucoseOverrideThresholdDown = glucoseOverrideThresholdDown
        }

        if let glucoseOverrideThresholdActiveDown = try? container
            .decode(Bool.self, forKey: .glucoseOverrideThresholdActiveDown)
        {
            settings.glucoseOverrideThresholdActiveDown = glucoseOverrideThresholdActiveDown
        }

        // Auto ISF Keto Protection
        if let ketoProtectBasalAbsolut = try? container.decode(Decimal.self, forKey: .ketoProtectBasalAbsolut) {
            settings.ketoProtectBasalAbsolut = ketoProtectBasalAbsolut
        }

        if let ketoProtect = try? container.decode(Bool.self, forKey: .ketoProtect) {
            settings.ketoProtect = ketoProtect
        }

        if let variableKetoProtect = try? container.decode(Bool.self, forKey: .variableKetoProtect) {
            settings.variableKetoProtect = variableKetoProtect
        }

        if let ketoProtectBasalPercent = try? container.decode(Decimal.self, forKey: .ketoProtectBasalPercent) {
            settings.ketoProtectBasalPercent = ketoProtectBasalPercent
        }

        if let ketoProtectAbsolut = try? container.decode(Bool.self, forKey: .ketoProtectAbsolut) {
            settings.ketoProtectAbsolut = ketoProtectAbsolut
        }

        // 1-minute loops
        if let allowOneMinuteLoop = try? container.decode(Bool.self, forKey: .allowOneMinuteLoop) {
            settings.allowOneMinuteLoop = allowOneMinuteLoop
        }

        if let calibrationRobustFit = try? container.decode(Bool.self, forKey: .calibrationRobustFit) {
            settings.calibrationRobustFit = calibrationRobustFit
        }

        if let calibrationRelaxLimits = try? container.decode(Bool.self, forKey: .calibrationRelaxLimits) {
            settings.calibrationRelaxLimits = calibrationRelaxLimits
        }

        if let ai = try? container.decode(Bool.self, forKey: .ai) {
            settings.ai = ai
        }

        if let mealViewMicronutrients = try? container.decode(Bool.self, forKey: .mealViewMicronutrients) {
            settings.mealViewMicronutrients = mealViewMicronutrients
        }

        if let uploadLogs = try? container.decode(Bool.self, forKey: .uploadLogs) {
            settings.uploadLogs = uploadLogs
        }

        if let uploadCrashReports = try? container.decode(Bool.self, forKey: .uploadCrashReports) {
            settings.uploadCrashReports = uploadCrashReports
        }

        if let nightTime = try? container.decode(NightTimeConfiguration.self, forKey: .nightTime) {
            settings.nightTime = nightTime
        }

        self = settings
    }
}

enum LightMode: String, JSON, Identifiable, CaseIterable {
    case light = "Light"
    case dark = "Dark"
    case auto = "Auto"

    var id: LightMode { self }
}

enum LoopEventsPlacement: String, JSON, Identifiable, CaseIterable {
    case hidden
    case top
    case bottom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hidden: return NSLocalizedString("Hidden", comment: "Loop events placement")
        case .top: return NSLocalizedString("Above the glucose", comment: "Loop events placement")
        case .bottom: return NSLocalizedString("Below the glucose", comment: "Loop events placement")
        }
    }
}

enum UploadScheduleInterval: String, JSON, Identifiable, CaseIterable {
    case always
    case everyHour
    case every12Hours
    case never

    var id: String { rawValue }

    /// "Never" is only offered for mobile data
    static let wifiCases: [UploadScheduleInterval] = [.always, .everyHour, .every12Hours]

    var displayName: String {
        switch self {
        case .always: return NSLocalizedString("Always", comment: "Upload schedule interval")
        case .everyHour: return NSLocalizedString("Every hour", comment: "Upload schedule interval")
        case .every12Hours: return NSLocalizedString("Every 12 hours", comment: "Upload schedule interval")
        case .never: return NSLocalizedString("Never", comment: "Upload schedule interval")
        }
    }

    /// the upload period, aligned on clock boundaries (`UploadScheduleGate.isDue`); `nil` means uploads are not allowed
    var timeInterval: TimeInterval? {
        switch self {
        case .always: return 0
        case .everyHour: return .hours(1)
        case .every12Hours: return .hours(12)
        case .never: return nil
        }
    }
}

enum UploadScheduleGroup: String, Identifiable, CaseIterable, Sendable {
    case glucose
    case treatmentsAndLoops
    case deviceStatus

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .glucose: return NSLocalizedString("Glucose", comment: "Upload schedule group")
        case .treatmentsAndLoops: return NSLocalizedString("Treatments & Loops", comment: "Upload schedule group")
        case .deviceStatus: return NSLocalizedString("Device Status", comment: "Upload schedule group")
        }
    }

    var scheduleKeyPath: KeyPath<FreeAPSSettings, UploadSchedule> {
        switch self {
        case .glucose: return \.glucoseUploadSchedule
        case .treatmentsAndLoops: return \.treatmentsAndLoopsUploadSchedule
        case .deviceStatus: return \.deviceStatusUploadSchedule
        }
    }
}

struct UploadSchedule: JSON, Equatable {
    var onWifi = UploadNetworkSchedule()
    var onCellular = UploadNetworkSchedule()
}

struct UploadNetworkSchedule: JSON, Equatable {
    var interval: UploadScheduleInterval = .always
    var alwaysWhileCharging: Bool = false
}

struct GlucoseSmoothingSettings: JSON, Equatable {
    var algorithm: GlucoseSmoothingAlgorithm = .off
    var savitzkyGolay = SavitzkyGolaySettings()
    var kalman = KalmanSettings()

    var isEnabled: Bool { algorithm != .off }
}

extension GlucoseSmoothingSettings {
    /// Field by field: a value this version does not know (an unknown algorithm, an out-of-range number
    /// of passes) falls back to that field's default instead of turning smoothing off altogether.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()

        algorithm = (try? container.decodeIfPresent(GlucoseSmoothingAlgorithm.self, forKey: .algorithm)) ?? algorithm
        savitzkyGolay = (try? container.decodeIfPresent(SavitzkyGolaySettings.self, forKey: .savitzkyGolay)) ??
            savitzkyGolay
        kalman = (try? container.decodeIfPresent(KalmanSettings.self, forKey: .kalman)) ?? kalman
    }

    private enum CodingKeys: String, CodingKey {
        case algorithm
        case savitzkyGolay
        case kalman
    }
}

enum GlucoseSmoothingAlgorithm: String, JSON, Identifiable, CaseIterable {
    case off
    case savitzkyGolay
    case kalman
    case exponential

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return NSLocalizedString("No smoothing", comment: "Glucose smoothing algorithm")
        case .savitzkyGolay: return NSLocalizedString("Savitzky-Golay", comment: "Glucose smoothing algorithm")
        case .kalman: return NSLocalizedString("Kalman filter", comment: "Glucose smoothing algorithm")
        case .exponential: return NSLocalizedString("Exponential", comment: "Glucose smoothing algorithm")
        }
    }

    var settingsDescription: String {
        switch self {
        case .off:
            return NSLocalizedString(
                "Glucose is used exactly as the CGM reports it.",
                comment: "Glucose smoothing algorithm description"
            )
        case .savitzkyGolay:
            return NSLocalizedString(
                "The smoothing used by older iAPS versions, which always ran it with 3 passes. Fits a curve through a window of about 30 minutes around each reading.",
                comment: "Glucose smoothing algorithm description"
            )
        case .kalman:
            return NSLocalizedString(
                "Tracks glucose and how fast it is changing, along with how sure it is of each. Ignores single readings that disagree with the trend, but follows genuine fast rises and falls.",
                comment: "Glucose smoothing algorithm description"
            )
        case .exponential:
            return NSLocalizedString(
                "Each reading is blended into two running averages, a plain one and one that follows the current trend, which counts for 60 percent of the result. The simplest option, and the only one that never revises an earlier reading - so older values on the chart lag behind the raw ones.",
                comment: "Glucose smoothing algorithm description"
            )
        }
    }

    var optionsDescription: String? {
        switch self {
        case .exponential,
             .off:
            return nil
        case .savitzkyGolay:
            return NSLocalizedString(
                "Each extra pass widens the window the curve is fitted over: a little less noise, but sharp peaks and dips are flattened more.",
                comment: "Glucose smoothing algorithm options description"
            )
        case .kalman:
            return NSLocalizedString(
                "How readily the filter gives up its own trend to follow the readings. Calmer is smoother, but the newest reading lags further behind a sharp turn.",
                comment: "Glucose smoothing algorithm options description"
            )
        }
    }
}

struct SavitzkyGolaySettings: JSON, Equatable {
    var passes: SavitzkyGolayPasses = .three
}

extension SavitzkyGolaySettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()

        passes = (try? container.decodeIfPresent(SavitzkyGolayPasses.self, forKey: .passes)) ?? passes
    }

    private enum CodingKeys: String, CodingKey {
        case passes
    }
}

enum SavitzkyGolayPasses: Int, JSON, Identifiable, CaseIterable {
    case one = 1
    case two = 2
    case three = 3

    var id: Int { rawValue }

    var displayName: String { "\(rawValue)" }
}

struct KalmanSettings: JSON, Equatable {
    var responsiveness: KalmanResponsiveness = .balanced
}

extension KalmanSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()

        responsiveness = (try? container.decodeIfPresent(KalmanResponsiveness.self, forKey: .responsiveness)) ??
            responsiveness
    }

    private enum CodingKeys: String, CodingKey {
        case responsiveness
    }
}

enum KalmanResponsiveness: String, JSON, Identifiable, CaseIterable {
    case calm
    case balanced
    case responsive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calm: return NSLocalizedString("Calm", comment: "Kalman responsiveness")
        case .balanced: return NSLocalizedString("Balanced", comment: "Kalman responsiveness")
        case .responsive: return NSLocalizedString("Responsive", comment: "Kalman responsiveness")
        }
    }

    /// Multiplier on the filter's process noise. `balanced` is the filter's default tuning.
    var processNoiseScale: Double {
        switch self {
        case .calm: return 0.7
        case .balanced: return 1
        case .responsive: return 1.5
        }
    }
}

// MARK: - Demographics

/// The sex and the birth date (Settings › Demographics, stored on the phone with the weight and the height) and which
/// of the two the daily Statistics upload carries (Settings › Sharing): the rules both screens and the uploads follow.
/// The settings backup carries all of them, the weight and the height too, whatever the toggles.
struct DemographicsSharing: Equatable, Sendable {
    /// `FreeAPSSettings.sexSetting`: 0 woman, 1 man, 2 other, 3 not set (the default)
    var sexSetting: Int
    /// `.distantPast` until set; otherwise a day, kept at 12:00 UTC (`birthCalendar`). Stored as it is: read as a day
    /// (`birthDay`), so a value not kept so (a restored older backup, the raw editor) reads as the right day too.
    var birthDate: Date
    var shareSex: Bool
    var shareAge: Bool

    init(sexSetting: Int = 3, birthDate: Date = .distantPast, shareSex: Bool = false, shareAge: Bool = false) {
        self.sexSetting = sexSetting
        self.birthDate = birthDate
        self.shareSex = shareSex
        self.shareAge = shareAge
    }

    init(_ settings: FreeAPSSettings) {
        self.init(
            sexSetting: settings.sexSetting,
            birthDate: settings.birthDate,
            shareSex: settings.shareSex,
            shareAge: settings.shareAge
        )
    }

    /// Woman, Man or Other
    var isSexSet: Bool { (0 ... 2).contains(sexSetting) }
    var isBirthDateSet: Bool { birthDate != .distantPast }

    /// Shared: the toggle on and the value set (clearing a value in Settings › Demographics or the Reference intakes
    /// sheet turns its toggle off, `settingSex`, `settingBirthDate`; one cleared otherwise, by a restored backup or
    /// the raw editor, may leave it on).
    var sharesSex: Bool { shareSex && isSexSet }
    var sharesAge: Bool { shareAge && isBirthDateSet }

    /// The sex set, in the same settings update as Sex sharing turned off when it is Not set (Other is set: kept).
    func settingSex(_ sexSetting: Int) -> DemographicsSharing {
        var updated = self
        updated.sexSetting = sexSetting
        if !updated.isSexSet { updated.shareSex = false }
        return updated
    }

    /// The birth date set (a day, `birthDate(day:)`) or cleared (`.distantPast`), in the same settings update as Age
    /// sharing turned off when cleared.
    func settingBirthDate(_ birthDate: Date) -> DemographicsSharing {
        var updated = self
        updated.birthDate = birthDate
        if !updated.isBirthDateSet { updated.shareAge = false }
        return updated
    }

    /// The reference intakes (Statistics › Nutrients) need Woman or Man and the birth date.
    var setsReferenceIntakes: Bool {
        Sex.savedSettings(sexSetting).hasHormonalSignal && isBirthDateSet
    }

    /// The Daily Log upload needs the sex shared as Woman or Man and the age shared, 1 to 120 years.
    func qualifiesForLogs(now: Date, calendar: Calendar) -> Bool {
        guard sharesSex, sharesAge, Sex.savedSettings(sexSetting).hasHormonalSignal,
              let age = Self.age(birthDate: birthDate, now: now, calendar: calendar)
        else { return false }
        return (1 ... 120).contains(age)
    }

    /// In whole years: from the birth day (`birthDay`, in `birthCalendar`) to today in `calendar`'s time zone (the
    /// phone's), so a birthday starts at midnight wherever the phone is; nil when the birth date is not set. Today is
    /// read in the Gregorian calendar, as the birth day is: the phone's calendar may be another, whose years aren't the
    /// Gregorian ones (Buddhist 2569, Japanese Reiwa 8, Islamic 1448 in 2026).
    static func age(birthDate: Date, now: Date, calendar: Calendar) -> Int? {
        guard birthDate != .distantPast else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let born = birthCalendar.dateComponents(
            [.year, .month, .day],
            from: birthDay(birthDate, timeZone: calendar.timeZone)
        )
        let today = gregorian.dateComponents([.year, .month, .day], from: now)
        return gregorian.dateComponents([.year], from: born, to: today).year
    }

    // MARK: The Statistics upload

    /// `Statistics.sex`: the setting when shared, otherwise 3 (not set).
    var statisticsSex: Int { sharesSex ? sexSetting : 3 }

    /// `Statistics.dob`: the birth date (as its day, `birthDay`) when shared, otherwise `.distantPast` (what an unset
    /// birth date always sent).
    var statisticsBirthDate: Date { sharesAge ? Self.birthDay(birthDate) : .distantPast }

    // MARK: Settings › Demographics

    /// The Sharing row's summary: "Off" while nothing is uploaded (`uploading`, the Online Backup and Statistics
    /// toggle, off), otherwise "Nothing shared", "Sex shared", "Age shared", "Sex and age shared".
    func summary(uploading: Bool) -> String {
        guard uploading else { return NSLocalizedString("Off", comment: "Demographics: nothing is uploaded") }
        switch (sharesSex, sharesAge) {
        case (false, false): return NSLocalizedString("Nothing shared", comment: "Demographics: none is shared")
        case (true, false): return NSLocalizedString("Sex shared", comment: "Demographics: what is shared")
        case (false, true): return NSLocalizedString("Age shared", comment: "Demographics: what is shared")
        case (true, true): return NSLocalizedString("Sex and age shared", comment: "Demographics: what is shared")
        }
    }

    /// The birth date the wheel starts on and edits (`BirthDateField`): its day (`birthDay`), nil when not set.
    var shownBirthDay: Date? { isBirthDateSet ? Self.birthDay(birthDate) : nil }

    /// The Reference intakes sheet (Statistics › Nutrients) saves Woman or Man with a birth date.
    static func canSaveReferenceIntakes(sex: Sex, birthDate: Date?) -> Bool {
        sex.hasHormonalSignal && birthDate.map { $0 != .distantPast } == true
    }

    // MARK: The birth date as a day

    /// The calendar a birth date is kept and read in: Gregorian, UTC. The date is a day, not a moment: kept at 12:00
    /// UTC of that day and read in UTC, it is the same day wherever the phone is, then or later (the old date picker
    /// kept the phone's midnight, which reads as the day before anywhere west of where it was entered).
    static let birthCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// The day picked (its year, month and day in `birthCalendar`, the calendar the picker shows) at 12:00 UTC.
    static func birthDate(day: Date) -> Date {
        let components = birthCalendar.dateComponents([.year, .month, .day], from: day)
        return birthCalendar.date(from: DateComponents(
            year: components.year,
            month: components.month,
            day: components.day,
            hour: 12
        )) ?? day
    }

    /// A day at 12:00 UTC (to the second): what `birthDate(day:)` keeps.
    static func isKeptAsDay(_ birthDate: Date) -> Bool {
        let noon = birthCalendar.startOfDay(for: birthDate).addingTimeInterval(.hours(12))
        return abs(birthDate.timeIntervalSince(noon)) < 1
    }

    /// The day a stored birth date is read as, by every reader (the age, the upload, the texts, the wheel), writing
    /// nothing: one kept as a day (`isKeptAsDay`, 12:00 UTC) as it is, wherever the phone is (at UTC+12 too, where
    /// it is a midnight); `.distantPast` as it is; any other (an older build's, from a restored backup, or the raw
    /// editor's) as `legacyBirthDay` converts it in the phone's zone `timeZone`. The stored value is rewritten only by
    /// the migration (`FreeAPSSettings.migratingDemographicsSharing`) or a day picked.
    /// A day off: a legacy date never migrated (a restored older backup after the migration, the raw editor) entered
    /// at midnight in a UTC+12 zone is 12:00 UTC of the day before, so it reads as that day, one day early, the phone
    /// at UTC+12 too (where `legacyBirthDay` would give the day). The kept day checked first is deliberate: a day this
    /// build kept reads as it is in every zone.
    static func birthDay(_ birthDate: Date, timeZone: TimeZone = .current) -> Date {
        guard birthDate != .distantPast, !isKeptAsDay(birthDate) else { return birthDate }
        return legacyBirthDay(birthDate, timeZone: timeZone)
    }

    /// A birth date from before the day was kept (settings from an older build, or a backup made by one; converted
    /// once, by `FreeAPSSettings.migratingDemographicsSharing`, and read so by `birthDay`) as its day at 12:00 UTC. The
    /// old date picker kept midnight in the zone it was entered in, which `timeZone` (the phone's at the migration, or
    /// at the read) may no longer be:
    /// 1. midnight in `timeZone` (that day's offset, DST included; the day's start where midnight was skipped): that
    ///    day, entered here (New Zealand or Fiji with the phone still there);
    /// 2. exactly 12:00:00 UTC: kept as it is, a day this build kept (an older build dropped the flag: a downgrade,
    ///    then this build again);
    /// 3. otherwise the UTC day 12 hours later: right for midnight in any zone from UTC−11 to UTC+11 (entered in
    ///    Berlin, read in New York).
    /// A day off: a UTC+12 midnight (12:00 UTC of the day before) read outside UTC+12, a UTC+13, UTC+14 or UTC−12
    /// one read outside its zone, one read 24 hours east of where it was entered (UTC−11 read at UTC+13: midnight
    /// there too), and a downgrade then upgrade with the phone at UTC+12 (its 12:00 UTC is midnight there, rule 1).
    static func legacyBirthDay(_ birthDate: Date, timeZone: TimeZone) -> Date {
        guard birthDate != .distantPast else { return birthDate }
        // to the second (a JSON round trip drifts a date by a millisecond or two)
        let moment = Date(timeIntervalSinceReferenceDate: birthDate.timeIntervalSinceReferenceDate.rounded())
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let day: DateComponents
        if local.startOfDay(for: moment) == moment {
            day = local.dateComponents([.year, .month, .day], from: moment)
        } else if birthCalendar.startOfDay(for: moment).addingTimeInterval(.hours(12)) == moment {
            return birthDate
        } else {
            day = birthCalendar.dateComponents([.year, .month, .day], from: moment.addingTimeInterval(.hours(12)))
        }
        return birthCalendar.date(from: DateComponents(
            year: day.year,
            month: day.month,
            day: day.day,
            hour: 12
        )) ?? birthDate
    }

    /// The birth picker's range: 1 January 1920 to today, as days (`birthCalendar`).
    static func birthDateRange(now: Date = Date(), timeZone: TimeZone = .current) -> ClosedRange<Date> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        let start = birthCalendar.date(from: DateComponents(year: 1920, month: 1, day: 1, hour: 12)) ?? now
        let end = birthCalendar.date(from: DateComponents(
            year: today.year,
            month: today.month,
            day: today.day,
            hour: 12
        )) ?? now
        return start ... Swift.max(start, end)
    }

    /// Where the birth wheel starts while not set: 1 January 30 years before this year (within `birthDateRange`), as
    /// a day. Not a birth date until the wheel is turned or "Set to" under it takes this day (`BirthDateField`).
    static func birthWheelStart(now: Date = Date(), timeZone: TimeZone = .current) -> Date {
        let range = birthDateRange(now: now, timeZone: timeZone)
        let year = birthCalendar.component(.year, from: range.upperBound) - 30
        let day = birthCalendar.date(from: DateComponents(year: year, month: 1, day: 1, hour: 12)) ?? range.upperBound
        return Swift.min(Swift.max(day, range.lowerBound), range.upperBound)
    }
}

extension FreeAPSSettings {
    /// The sex, the birth date and their share toggles, read and written together: Settings › Demographics writes them
    /// in one update (`DemographicsSharing.settingSex`, `settingBirthDate`: a value cleared turns its toggle off).
    var demographics: DemographicsSharing {
        get { DemographicsSharing(self) }
        set {
            sexSetting = newValue.sexSetting
            birthDate = newValue.birthDate
            shareSex = newValue.shareSex
            shareAge = newValue.shareAge
        }
    }

    /// Once, at the start, in a settings file without the `demographicsSharingMigrated` key (an older build's; see
    /// `DataMigrations.migrateDemographicsSharing`): each value set then stays shared as it was (the sex if Woman, Man
    /// or Other, the age if a birth date is set), whether Online Backup is on or not, and the birth date, whatever it
    /// is, becomes its day (`DemographicsSharing.legacyBirthDay`, the phone's zone `timeZone`). Values set later start
    /// not shared.
    func migratingDemographicsSharing(timeZone: TimeZone = .current) -> FreeAPSSettings {
        let values = demographics
        var migrated = self
        migrated.shareSex = values.isSexSet
        migrated.shareAge = values.isBirthDateSet
        migrated.birthDate = DemographicsSharing.legacyBirthDay(birthDate, timeZone: timeZone)
        migrated.demographicsSharingMigrated = true
        return migrated
    }
}
