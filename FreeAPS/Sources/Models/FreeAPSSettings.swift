import Foundation

struct FreeAPSSettings: JSON, Equatable {
    var units: GlucoseUnits = .mmolL
    var closedLoop: Bool = false
    var allowAnnouncements: Bool = false
    var useAutotune: Bool = false
    var isUploadEnabled: Bool = false
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
    var individualAdjustmentFactor: Decimal = 0.5
    var timeCap: Int = 8
    var minuteInterval: Int = 30
    var delay: Int = 60
    var useAppleHealth: Bool = false
    var smoothGlucose: Bool = false
    var displayOnWatch: AwConfig = .BGTarget
    var overrideHbA1cUnit: Bool = false
    var high: Decimal = 145
    var low: Decimal = 70
    var uploadStats: Bool = false
    var hours: Int = 6
    var xGridLines: Bool = true
    var yGridLines: Bool = true
    var oneDimensionalGraph: Bool = false
    var rulerMarks: Bool = false
    var maxCarbs: Decimal = 1000
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
    var useTargetButton: Bool = false
    var alwaysUseColors: Bool = false
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
    var profilesOrTempTargets: Bool = false
    var allowBolusShortcut: Bool = false
    var allowedRemoteBolusAmount: Decimal = 0.0
    var eventualBG: Bool = false
    var minumimPrediction: Bool = false
    var minimumSMB: Decimal = 0.3
    var useInsulinBars: Bool = false
    var skipGlucoseChart: Bool = false
    var birthDate = Date.distantPast
    var sexSetting: Int = 3
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
    var smbDeliveryRatioBGrange: Decimal = 0
    var smbDeliveryRatioMin: Decimal = 0.5
    var smbDeliveryRatioMax: Decimal = 0.5
    var autoISFhourlyChange: Decimal = 1
    var higherISFrangeWeight: Decimal = 0
    var lowerISFrangeWeight: Decimal = 0
    var postMealISFweight: Decimal = 0
    var enableBGacceleration: Bool = true
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
    var allowOneMinuteGlucose: Bool = false // allow sending 1-minute readings to oref, even if loops are with 5-minute intervals
    // AI Food Search Variablen
    var aiProvider: String = "Basic Analysis (Free)"
    var claudeAPIKey: String = ""
    var claudeQuery: String = ""
    var openAIQuery: String = ""
    var openAIAPIKey: String = ""
    var googleGeminiAPIKey: String = ""
    var googleGeminiQuery: String = ""
    var barcodeSearchProvider: String = "OpenFoodFacts"
    var textSearchProvider: String = "USDA FoodData Central"
    var aiImageProvider: String = "OpenAI (ChatGPT API)"
    var analysisMode: String = "standard"
    var advancedDosingRecommendationsEnabled: Bool = false
    var useGPT5ForOpenAI: Bool = false
    var ai: Bool = true
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

        if let smoothGlucose = try? container.decode(Bool.self, forKey: .smoothGlucose) {
            settings.smoothGlucose = smoothGlucose
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

        if let oneDimensionalGraph = try? container.decode(Bool.self, forKey: .oneDimensionalGraph) {
            settings.oneDimensionalGraph = oneDimensionalGraph
        }

        if let rulerMarks = try? container.decode(Bool.self, forKey: .rulerMarks) {
            settings.rulerMarks = rulerMarks
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

        if let skipGlucoseChart = try? container.decode(Bool.self, forKey: .skipGlucoseChart) {
            settings.skipGlucoseChart = skipGlucoseChart
        }

        if let birthDate = try? container.decode(Date.self, forKey: .birthDate) {
            settings.birthDate = birthDate
        }

        if let sexSetting = try? container.decode(Int.self, forKey: .sexSetting) {
            settings.sexSetting = sexSetting
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

        if let enableBGacceleration = try? container.decode(Bool.self, forKey: .enableBGacceleration) {
            settings.enableBGacceleration = enableBGacceleration
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

        if let ketoProtectAbsolut = try? container.decode(Bool.self, forKey: .ketoProtectAbsolut) {
            settings.ketoProtectAbsolut = ketoProtectAbsolut
        }

        // 1-minute loops
        if let allowOneMinuteLoop = try? container.decode(Bool.self, forKey: .allowOneMinuteLoop) {
            settings.allowOneMinuteLoop = allowOneMinuteLoop
        }
        if let allowOneMinuteGlucose = try? container.decode(Bool.self, forKey: .allowOneMinuteGlucose) {
            settings.allowOneMinuteGlucose = allowOneMinuteGlucose
        }

        if let aiProvider = try? container.decode(String.self, forKey: .aiProvider) {
            settings.aiProvider = aiProvider
        }

        if let claudeAPIKey = try? container.decode(String.self, forKey: .claudeAPIKey) {
            settings.claudeAPIKey = claudeAPIKey
        }

        if let claudeQuery = try? container.decode(String.self, forKey: .claudeQuery) {
            settings.claudeQuery = claudeQuery
        }

        if let openAIAPIKey = try? container.decode(String.self, forKey: .openAIAPIKey) {
            settings.openAIAPIKey = openAIAPIKey
        }

        if let openAIQuery = try? container.decode(String.self, forKey: .openAIQuery) {
            settings.openAIQuery = openAIQuery
        }

        if let googleGeminiAPIKey = try? container.decode(String.self, forKey: .googleGeminiAPIKey) {
            settings.googleGeminiAPIKey = googleGeminiAPIKey
        }

        if let googleGeminiQuery = try? container.decode(String.self, forKey: .googleGeminiQuery) {
            settings.googleGeminiQuery = googleGeminiQuery
        }

        if let textSearchProvider = try? container.decode(String.self, forKey: .textSearchProvider) {
            settings.textSearchProvider = textSearchProvider
        }
        if let barcodeSearchProvider = try? container.decode(String.self, forKey: .barcodeSearchProvider) {
            settings.barcodeSearchProvider = barcodeSearchProvider
        }

        if let aiImageProvider = try? container.decode(String.self, forKey: .aiImageProvider) {
            settings.aiImageProvider = aiImageProvider
        }

        if let analysisMode = try? container.decode(String.self, forKey: .analysisMode) {
            settings.analysisMode = analysisMode
        }

        if let advancedDosingRecommendationsEnabled = try? container.decode(
            Bool.self,
            forKey: .advancedDosingRecommendationsEnabled
        ) {
            settings.advancedDosingRecommendationsEnabled = advancedDosingRecommendationsEnabled
        }

        if let useGPT5ForOpenAI = try? container.decode(Bool.self, forKey: .useGPT5ForOpenAI) {
            settings.useGPT5ForOpenAI = useGPT5ForOpenAI
        }

        if let ai = try? container.decode(Bool.self, forKey: .ai) {
            settings.ai = ai
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
