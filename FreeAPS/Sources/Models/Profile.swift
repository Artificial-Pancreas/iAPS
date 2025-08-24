import Foundation

struct Profile: Codable {
    var maxIOB: Double = 0
    var maxDailySafetyMultiplier: Double = 0
    var currentBasalSafetyMultiplier: Double = 0
    var autosensMax: Double = 0
    var autosensMin: Double = 0
    var rewindResetsAutosens: Bool = false
    var highTemptargetRaisesSensitivity: Bool = false
    var lowTemptargetLowersSensitivity: Bool = false
    var sensitivityRaisesTarget: Bool = false
    var resistanceLowersTarget: Bool = false
    var exerciseMode: Bool = false
    var halfBasalExerciseTarget: Int = 0
    var maxCOB: Double = 0
    var skipNeutralTemps: Bool = false
    var min5mCarbImpact: Double = 0
    var autotuneISFAdjustmentFraction: Double = 0
    var remainingCarbsFraction: Double = 0
    var remainingCarbsCap: Double = 0
    var enableUAM: Bool = false
    var enableSMBWithCOB: Bool = false
    var enableSMBWithTemptarget: Bool = false
    var enableSMBAlways: Bool = false
    var enableSMBAfterCarbs: Bool = false
    var enableSMBHighBG: Bool = false
    var enableSMBHighBGTarget: Double = 0
    var allowSMBWithHighTemptarget: Bool = false
    var maxSMBBasalMinutes: Double = 0
    var maxUAMSMBBasalMinutes: Double = 0
    var smbInterval: Int = 0
    var bolusIncrement: Double = 0
    var maxDeltaBGThreshold: Double = 0
    var curve: InsulinCurve
    var useCustomPeakTime: Bool = false
    var insulinPeakTime: Double = 0
    var carbsReqThreshold: Double = 0
    var noisyCGMTargetMultiplier: Double = 0
    var suspendZerosIOB: Bool = false
    var model: String?
    var basalProfile: [BasalProfileEntry] = []
    var carbRatios: CarbRatios
    var isfProfile: InsulinSensitivities
    var outUnits: GlucoseUnits?
    var dia: Double = 0
    var maxDailyBasal: Double = 0
    var maxBasal: Double = 0
    var minBG: Double = 0
    var maxBG: Double = 0
    var temptargetSet: Bool?
    var bgTargets: BGTargets
    var thresholdSetting: Double = 0
    var sens: Double = 0
    var carbRatio: Double = 0
    var currentBasal: Double = 0
    var iaps: FreeAPSSettings
    var dynamicVariables: DynamicVariables
    var oldCR: Double?
    var oldISF: Double?
    var old_basal: Double?
    var setBasal: Bool?
    var basalRate: Double?
    var smbDeliveryRatio: Double = 0
    var autoISFReasons: String?
    var autoISFString: String?
    var aisf: Double?
    var microbolusAllowed: Bool?
    var useNewFormula: Bool = false
    var enableDynamicCR: Bool = false
    var sigmoid: Bool = false
    var adjustmentFactor: Double = 0
    var weightPercentage: Double = 0
    var mw: String? // middleware return string
}

extension Profile {
    private enum CodingKeys: String, CodingKey {
        case maxIOB = "max_iob"
        case maxDailySafetyMultiplier = "max_daily_safety_multiplier"
        case currentBasalSafetyMultiplier = "current_basal_safety_multiplier"
        case autosensMax = "autosens_max"
        case autosensMin = "autosens_min"
        case rewindResetsAutosens = "rewind_resets_autosens"
        case highTemptargetRaisesSensitivity = "high_temptarget_raises_sensitivity"
        case lowTemptargetLowersSensitivity = "low_temptarget_lowers_sensitivity"
        case sensitivityRaisesTarget = "sensitivity_raises_target"
        case resistanceLowersTarget = "resistance_lowers_target"
        case exerciseMode = "exercise_mode"
        case halfBasalExerciseTarget = "half_basal_exercise_target"
        case maxCOB
        case skipNeutralTemps = "skip_neutral_temps"
        case min5mCarbImpact = "min_5m_carbimpact"
        case autotuneISFAdjustmentFraction = "autotune_isf_adjustmentFraction"
        case remainingCarbsFraction
        case remainingCarbsCap
        case enableUAM
        case enableSMBWithCOB = "enableSMB_with_COB"
        case enableSMBWithTemptarget = "enableSMB_with_temptarget"
        case enableSMBAlways = "enableSMB_always"
        case enableSMBAfterCarbs = "enableSMB_after_carbs"
        case enableSMBHighBG = "enableSMB_high_bg"
        case enableSMBHighBGTarget = "enableSMB_high_bg_target"
        case allowSMBWithHighTemptarget = "allowSMB_with_high_temptarget"
        case maxSMBBasalMinutes
        case maxUAMSMBBasalMinutes
        case smbInterval = "SMBInterval"
        case bolusIncrement = "bolus_increment"
        case maxDeltaBGThreshold = "maxDelta_bg_threshold"
        case curve
        case useCustomPeakTime
        case insulinPeakTime
        case carbsReqThreshold
        case noisyCGMTargetMultiplier
        case suspendZerosIOB = "suspend_zeros_iob"
        case model
        case basalProfile = "basalprofile"
        case carbRatios = "carb_ratios"
        case isfProfile
        case outUnits = "out_units"
        case dia
        case maxDailyBasal = "max_daily_basal"
        case maxBasal = "max_basal"
        case minBG = "min_bg"
        case maxBG = "max_bg"
        case temptargetSet
        case bgTargets = "bg_targets"
        case thresholdSetting = "threshold_setting"
        case sens
        case carbRatio = "carb_ratio"
        case currentBasal = "current_basal"
        case iaps
        case dynamicVariables
        case oldCR = "old_cr"
        case oldISF = "old_isf"
        case old_basal
        case setBasal = "set_basal"
        case basalRate = "basal_rate"
        case smbDeliveryRatio = "smb_delivery_ratio"
        case autoISFReasons = "autoISFreasons"
        case autoISFString = "autoISFstring"
        case aisf
        case microbolusAllowed
        case useNewFormula
        case enableDynamicCR
        case sigmoid
        case adjustmentFactor
        case weightPercentage
        case mw
    }
}
