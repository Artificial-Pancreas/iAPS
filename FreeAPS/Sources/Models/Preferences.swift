import Foundation

struct Preferences: JSON {
    var maxIOB: Decimal
    var maxDailySafetyMultiplier: Decimal
    var currentBasalSafetyMultiplier: Decimal
    var autosensMax: Decimal
    var autosensMin: Decimal
    var rewindResetsAutosens: Bool
    var highTemptargetRaisesSensitivity: Bool
    var lowTemptargetLowersSensitivity: Bool
    var sensitivityRaisesTarget: Bool
    var resistanceLowersTarget: Bool
    var advTargetAdjustments: Bool
    var exerciseMode: Bool
    var halfBasalExerciseTarget: Decimal
    var maxCOB: Decimal
    var wideBGTargetRange: Bool
    var skipNeutralTemps: Bool
    var unsuspendIfNoTemp: Bool
    var bolusSnoozeDIADivisor: Decimal
    var min5mCarbimpact: Decimal
    var autotuneISFAdjustmentFraction: Decimal
    var remainingCarbsFraction: Decimal
    var remainingCarbsCap: Decimal
    var enableUAM: Bool
    var a52RiskEnable: Bool
    var enableSMBWithCOB: Bool
    var enableSMBWithTemptarget: Bool
    var enableSMBAlways: Bool
    var enableSMBAfterCarbs: Bool
    var allowSMBWithHighTemptarget: Bool
    var maxSMBBasalMinutes: Decimal
    var maxUAMSMBBasalMinutes: Decimal
    var smbInterval: Decimal
    var bolusIncrement: Decimal
    var curve: InsulinCurve
    var useCustomPeakTime: Bool
    var insulinPeakTime: Decimal
    var carbsReqThreshold: Decimal
    var offlineHotspot: Bool // unused, for compatibility
    var noisyCGMTargetMultiplier: Decimal
    var suspendZerosIOB: Bool
    var enableEnliteBgproxy: Bool // unused, for compatibility

    init(
        maxIOB: Decimal = 0,
        maxDailySafetyMultiplier: Decimal = 3,
        currentBasalSafetyMultiplier: Decimal = 4,
        autosensMax: Decimal = 1.2,
        autosensMin: Decimal = 0.7,
        rewindResetsAutosens: Bool = true,
        highTemptargetRaisesSensitivity: Bool = false,
        lowTemptargetLowersSensitivity: Bool = false,
        sensitivityRaisesTarget: Bool = true,
        resistanceLowersTarget: Bool = false,
        advTargetAdjustments: Bool = false,
        exerciseMode: Bool = false,
        halfBasalExerciseTarget: Decimal = 160,
        maxCOB: Decimal = 120,
        wideBGTargetRange: Bool = false,
        skipNeutralTemps: Bool = false,
        unsuspendIfNoTemp: Bool = false,
        bolusSnoozeDIADivisor: Decimal = 2,
        min5mCarbimpact: Decimal = 8,
        autotuneISFAdjustmentFraction: Decimal = 1.0,
        remainingCarbsFraction: Decimal = 1.0,
        remainingCarbsCap: Decimal = 90,
        enableUAM: Bool = false,
        a52RiskEnable: Bool = false,
        enableSMBWithCOB: Bool = false,
        enableSMBWithTemptarget: Bool = false,
        enableSMBAlways: Bool = false,
        enableSMBAfterCarbs: Bool = false,
        allowSMBWithHighTemptarget: Bool = false,
        maxSMBBasalMinutes: Decimal = 30,
        maxUAMSMBBasalMinutes: Decimal = 30,
        smbInterval: Decimal = 3,
        bolusIncrement: Decimal = 0.1,
        curve: InsulinCurve = .rapidActing,
        useCustomPeakTime: Bool = false,
        insulinPeakTime: Decimal = 75,
        carbsReqThreshold: Decimal = 1,
        offlineHotspot: Bool = false, // unused, for compatibility
        noisyCGMTargetMultiplier: Decimal = 1.3,
        suspendZerosIOB: Bool = true,
        enableEnliteBgproxy: Bool = false // unused, for compatibility
    ) {
        self.maxIOB = maxIOB
        self.maxDailySafetyMultiplier = maxDailySafetyMultiplier
        self.currentBasalSafetyMultiplier = currentBasalSafetyMultiplier
        self.autosensMax = autosensMax
        self.autosensMin = autosensMin
        self.rewindResetsAutosens = rewindResetsAutosens
        self.highTemptargetRaisesSensitivity = highTemptargetRaisesSensitivity
        self.lowTemptargetLowersSensitivity = lowTemptargetLowersSensitivity
        self.sensitivityRaisesTarget = sensitivityRaisesTarget
        self.resistanceLowersTarget = resistanceLowersTarget
        self.advTargetAdjustments = advTargetAdjustments
        self.exerciseMode = exerciseMode
        self.halfBasalExerciseTarget = halfBasalExerciseTarget
        self.maxCOB = maxCOB
        self.wideBGTargetRange = wideBGTargetRange
        self.skipNeutralTemps = skipNeutralTemps
        self.unsuspendIfNoTemp = unsuspendIfNoTemp
        self.bolusSnoozeDIADivisor = bolusSnoozeDIADivisor
        self.min5mCarbimpact = min5mCarbimpact
        self.autotuneISFAdjustmentFraction = autotuneISFAdjustmentFraction
        self.remainingCarbsFraction = remainingCarbsFraction
        self.remainingCarbsCap = remainingCarbsCap
        self.enableUAM = enableUAM
        self.a52RiskEnable = a52RiskEnable
        self.enableSMBWithCOB = enableSMBWithCOB
        self.enableSMBWithTemptarget = enableSMBWithTemptarget
        self.enableSMBAlways = enableSMBAlways
        self.enableSMBAfterCarbs = enableSMBAfterCarbs
        self.allowSMBWithHighTemptarget = allowSMBWithHighTemptarget
        self.maxSMBBasalMinutes = maxSMBBasalMinutes
        self.maxUAMSMBBasalMinutes = maxUAMSMBBasalMinutes
        self.smbInterval = smbInterval
        self.bolusIncrement = bolusIncrement
        self.curve = curve
        self.useCustomPeakTime = useCustomPeakTime
        self.insulinPeakTime = insulinPeakTime
        self.carbsReqThreshold = carbsReqThreshold
        self.offlineHotspot = offlineHotspot
        self.noisyCGMTargetMultiplier = noisyCGMTargetMultiplier
        self.suspendZerosIOB = suspendZerosIOB
        self.enableEnliteBgproxy = enableEnliteBgproxy
    }
}

extension Preferences {
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
        case resistanceLowersTarget
        case advTargetAdjustments = "adv_target_adjustments"
        case exerciseMode = "exercise_mode"
        case halfBasalExerciseTarget = "half_basal_exercise_target"
        case maxCOB
        case wideBGTargetRange = "wide_bg_target_range"
        case skipNeutralTemps = "skip_neutral_temps"
        case unsuspendIfNoTemp = "unsuspend_if_no_temp"
        case bolusSnoozeDIADivisor = "bolussnooze_dia_divisor"
        case min5mCarbimpact = "min_5m_carbimpact"
        case autotuneISFAdjustmentFraction = "autotune_isf_adjustmentFraction"
        case remainingCarbsFraction
        case remainingCarbsCap
        case enableUAM
        case a52RiskEnable = "A52_risk_enable"
        case enableSMBWithCOB = "enableSMB_with_COB"
        case enableSMBWithTemptarget = "enableSMB_with_temptarget"
        case enableSMBAlways = "enableSMB_always"
        case enableSMBAfterCarbs = "enableSMB_after_carbs"
        case allowSMBWithHighTemptarget = "allowSMB_with_high_temptarget"
        case maxSMBBasalMinutes
        case maxUAMSMBBasalMinutes
        case smbInterval = "SMBInterval"
        case bolusIncrement = "bolus_increment"
        case curve
        case useCustomPeakTime
        case insulinPeakTime
        case carbsReqThreshold
        case offlineHotspot = "offline_hotspot"
        case noisyCGMTargetMultiplier
        case suspendZerosIOB = "suspend_zeros_iob"
        case enableEnliteBgproxy
    }
}

enum InsulinCurve: String, Codable {
    case rapidActing = "rapid-acting"
    case ultraRapid = "ultra-rapid"
    case bilinear
}

extension Preferences {
    var prettyPrinted: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return String(data: try! encoder.encode(self), encoding: .utf8)!
    }
}
