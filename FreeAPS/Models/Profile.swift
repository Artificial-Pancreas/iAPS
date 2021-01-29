//
//  Profile.swift
//  FreeAPS
//
//  Created by Ivan Valkou on 21.01.2021.
//

import Foundation

struct Profile: JSON {
    var maxIOB: Double
    var maxDailySafetyMultiplier: Double
    var currentBasalSafetyMultiplier: Double
    var autosensMax: Double
    var autosensMin: Double
    var rewindResetsAutosens: Bool
    var highTemptargetRaisesSensitivity: Bool
    var lowTemptargetLowersSensitivity: Bool
    var sensitivityRaisesTarget: Bool
    var resistanceLowersTarget: Bool
    var advTargetAdjustments: Bool
    var exerciseMode: Bool
    var halfBasalExerciseTarget: Double
    var maxCOB: Double
    var wideBGTargetRange: Bool
    var skipNeutralTemps: Bool
    var unsuspendIfNoTemp: Bool
    var bolusSnoozeDIADivisor: Double
    var min5mCarbimpact: Double
    var autotuneISFAdjustmentFraction: Double
    var remainingCarbsFraction: Double
    var remainingCarbsCap: Double
    var enableUAM: Bool
    var a52RiskEnable: Bool
    var enableSMBWithCOB: Bool
    var enableSMBWithTemptarget: Bool
    var enableSMBAlways: Bool
    var enableSMBAfterCarbs: Bool
    var allowSMBWithHighTemptarget: Bool
    var maxSMBBasalMinutes: Double
    var maxUAMSMBBasalMinutes: Double
    var smbInterval: Double
    var bolusIncrement: Double
    var curve: InsulinCurve
    var useCustomPeakTime: Bool
    var insulinPeakTime: Double
    var carbsReqThreshold: Double
    var offlineHotspot: Bool // unused, for compatibility
    var noisyCGMTargetMultiplier: Double
    var suspendZerosIOB: Bool
    var enableEnliteBgproxy: Bool // unused, for compatibility

    init(
        maxIOB: Double = 0,
        maxDailySafetyMultiplier: Double = 3,
        currentBasalSafetyMultiplier: Double = 4,
        autosensMax: Double = 1.2,
        autosensMin: Double = 0.7,
        rewindResetsAutosens: Bool = true,
        highTemptargetRaisesSensitivity: Bool = false,
        lowTemptargetLowersSensitivity: Bool = false,
        sensitivityRaisesTarget: Bool = true,
        resistanceLowersTarget: Bool = false,
        advTargetAdjustments: Bool = false,
        exerciseMode: Bool = false,
        halfBasalExerciseTarget: Double = 160,
        maxCOB: Double = 120,
        wideBGTargetRange: Bool = false,
        skipNeutralTemps: Bool = false,
        unsuspendIfNoTemp: Bool = false,
        bolusSnoozeDIADivisor: Double = 2,
        min5mCarbimpact: Double = 8,
        autotuneISFAdjustmentFraction: Double = 1.0,
        remainingCarbsFraction: Double = 1.0,
        remainingCarbsCap: Double = 90,
        enableUAM: Bool = false,
        a52RiskEnable: Bool = false,
        enableSMBWithCOB: Bool = false,
        enableSMBWithTemptarget: Bool = false,
        enableSMBAlways: Bool = false,
        enableSMBAfterCarbs: Bool = false,
        allowSMBWithHighTemptarget: Bool = false,
        maxSMBBasalMinutes: Double = 30,
        maxUAMSMBBasalMinutes: Double = 30,
        smbInterval: Double = 3,
        bolusIncrement: Double = 0.1,
        curve: InsulinCurve = .rapidActing,
        useCustomPeakTime: Bool = false,
        insulinPeakTime: Double = 75,
        carbsReqThreshold: Double = 1,
        offlineHotspot: Bool = false, // unused, for compatibility
        noisyCGMTargetMultiplier: Double = 1.3,
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
        case resistanceLowersTarget = "resistanceLowersTarget"
        case advTargetAdjustments = "adv_target_adjustments"
        case exerciseMode = "exercise_mode"
        case halfBasalExerciseTarget = "half_basal_exercise_target"
        case maxCOB = "maxCOB"
        case wideBGTargetRange = "wide_bg_target_range"
        case skipNeutralTemps = "skip_neutral_temps"
        case unsuspendIfNoTemp = "unsuspend_if_no_temp"
        case bolusSnoozeDIADivisor = "bolussnooze_dia_divisor"
        case min5mCarbimpact = "min_5m_carbimpact"
        case autotuneISFAdjustmentFraction = "autotune_isf_adjustmentFraction"
        case remainingCarbsFraction = "remainingCarbsFraction"
        case remainingCarbsCap = "remainingCarbsCap"
        case enableUAM = "enableUAM"
        case a52RiskEnable = "A52_risk_enable"
        case enableSMBWithCOB = "enableSMB_with_COB"
        case enableSMBWithTemptarget = "enableSMB_with_temptarget"
        case enableSMBAlways = "enableSMB_always"
        case enableSMBAfterCarbs = "enableSMB_after_carbs"
        case allowSMBWithHighTemptarget = "allowSMB_with_high_temptarget"
        case maxSMBBasalMinutes = "maxSMBBasalMinutes"
        case maxUAMSMBBasalMinutes = "maxUAMSMBBasalMinutes"
        case smbInterval = "SMBInterval"
        case bolusIncrement = "bolus_increment"
        case curve = "curve"
        case useCustomPeakTime = "useCustomPeakTime"
        case insulinPeakTime = "insulinPeakTime"
        case carbsReqThreshold = "carbsReqThreshold"
        case offlineHotspot = "offline_hotspot"
        case noisyCGMTargetMultiplier = "noisyCGMTargetMultiplier"
        case suspendZerosIOB = "suspend_zeros_iob"
        case enableEnliteBgproxy = "enableEnliteBgproxy"
    }
}

enum InsulinCurve: String, Codable {
    case rapidActing = "rapid-acting"
    case ultraRapid = "ultra-rapid"
    case bilinear = "bilinear"
}
