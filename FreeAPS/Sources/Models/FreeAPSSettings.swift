import Foundation

struct FreeAPSSettings: JSON, Equatable {
    var units: GlucoseUnits = .mmolL
    var closedLoop: Bool = false
    var allowAnnouncements: Bool = false
    var useAutotune: Bool = false
    var isUploadEnabled: Bool = false
    var useLocalGlucoseSource: Bool = false
    var localGlucosePort: Int = 8080
    var debugOptions: Bool = false
    var insulinReqPercentage: Decimal = 70
    var skipBolusScreenAfterCarbs: Bool = false
    var displayHR: Bool = false
    var cgm: CGMType = .nightscout
    var uploadGlucose: Bool = true
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
    var profilesOrTempTargets: Bool = false
    var allowBolusShortcut: Bool = false
    var allowedRemoteBolusAmount: Decimal = 0.0
    var eventualBG: Bool = true
    var minumimPrediction: Bool = true
    var minimumSMB: Decimal = 0.3
    var useInsulinBars: Bool = false
    var disableCGMError: Bool = true
    var skipGlucoseChart: Bool = false
    var birthDate = Date.distantPast
    var sexSetting: Int = 3
    var displayDelta: Bool = false
    var profileID: String = "Hypo Treatment"
    var allowDilution: Bool = false
    var hideInsulinBadge: Bool = false
    var extended_overrides = false
    var extendHomeView = true
    var displayExpiration = false
    var sensorDays: Double = 10
    var anubis: Bool = false
    var fpus: Bool = true
    var fpuAmounts: Bool = false
    // Auto ISF
    var autoisf: Bool = false
    var smbDeliveryRatioBGrange: Decimal = 0
    var smbDeliveryRatioMin: Decimal = 0.5
    var smbDeliveryRatioMax: Decimal = 0.5
    var autoISFhourlyChange: Decimal = 1
    var higherISFrangeWeight: Decimal = 0
    var lowerISFrangeWeight: Decimal = 0
    var postMealISFweight: Decimal = 0.01
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

        if let useLocalGlucoseSource = try? container.decode(Bool.self, forKey: .useLocalGlucoseSource) {
            settings.useLocalGlucoseSource = useLocalGlucoseSource
        }

        if let localGlucosePort = try? container.decode(Int.self, forKey: .localGlucosePort) {
            settings.localGlucosePort = localGlucosePort
        }

        if let debugOptions = try? container.decode(Bool.self, forKey: .debugOptions) {
            settings.debugOptions = debugOptions
        }

        if let fpus = try? container.decode(Bool.self, forKey: .fpus) {
            settings.fpus = fpus
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

        if let displayHR = try? container.decode(Bool.self, forKey: .displayHR) {
            settings.displayHR = displayHR
            // compatibility if displayOnWatch is not available in json files
            settings.displayOnWatch = (displayHR == true) ? AwConfig.HR : AwConfig.BGTarget
        }

        if let displayOnWatch = try? container.decode(AwConfig.self, forKey: .displayOnWatch) {
            settings.displayOnWatch = displayOnWatch
        }

        if let cgm = try? container.decode(CGMType.self, forKey: .cgm) {
            settings.cgm = cgm
        }

        if let uploadGlucose = try? container.decode(Bool.self, forKey: .uploadGlucose) {
            settings.uploadGlucose = uploadGlucose
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

        if let anubis = try? container.decode(Bool.self, forKey: .anubis) {
            settings.anubis = anubis
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

        if let addSourceInfoToGlucoseNotifications = try? container.decode(
            Bool.self,
            forKey: .addSourceInfoToGlucoseNotifications
        ) {
            settings.addSourceInfoToGlucoseNotifications = addSourceInfoToGlucoseNotifications
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

        if let disableCGMError = try? container.decode(Bool.self, forKey: .disableCGMError) {
            settings.disableCGMError = disableCGMError
        }

        if let skipGlucoseChart = try? container.decode(Bool.self, forKey: .skipGlucoseChart) {
            settings.skipGlucoseChart = skipGlucoseChart
        }

        if let birthDate = try? container.decode(Date.self, forKey: .birthDate) {
            settings.birthDate = birthDate
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

        if let extendHomeView = try? container.decode(Bool.self, forKey: .extendHomeView) {
            settings.extendHomeView = extendHomeView
        }

        if let displayExpiration = try? container.decode(Bool.self, forKey: .displayExpiration) {
            settings.displayExpiration = displayExpiration
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

        self = settings
    }
}
