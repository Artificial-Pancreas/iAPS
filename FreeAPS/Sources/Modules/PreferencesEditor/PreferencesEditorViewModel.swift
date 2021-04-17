import Foundation
import SwiftUI

extension PreferencesEditor {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject,
        PreferencesSettable where Provider: PreferencesEditorProvider
    {
        @Injected() var settingsManager: SettingsManager!
        private(set) var preferences = Preferences()
        @Published var unitsIndex = 1
        @Published var allowAnnouncements = false
        @Published var insulinReqFraction: Decimal = 0.7

        @Published var decimalFields: [Field<Decimal>] = []
        @Published var boolFields: [Field<Bool>] = []
        @Published var insulinCurveField = Field<InsulinCurve>(
            displayName: "Insulin curve",
            keypath: \.curve,
            value: .rapidActing
        )

        override func subscribe() {
            preferences = provider.preferences
            unitsIndex = settingsManager.settings.units == .mgdL ? 0 : 1
            allowAnnouncements = settingsManager.settings.allowAnnouncements
            insulinCurveField.value = preferences.curve
            insulinCurveField.settable = self
            insulinReqFraction = settingsManager.settings.insulinReqFraction ?? 0.7

            $unitsIndex
                .removeDuplicates()
                .sink { [weak self] index in
                    self?.settingsManager.settings.units = index == 0 ? .mgdL : .mmolL
                }
                .store(in: &lifetime)

            $allowAnnouncements
                .removeDuplicates()
                .sink { [weak self] allow in
                    self?.settingsManager.settings.allowAnnouncements = allow
                }
                .store(in: &lifetime)

            $insulinReqFraction
                .removeDuplicates()
                .sink { [weak self] fraction in
                    self?.settingsManager.settings.insulinReqFraction = fraction
                }
                .store(in: &lifetime)

            boolFields = [
                Field(
                    displayName: "Rewind Resets Autosens",
                    keypath: \.rewindResetsAutosens,
                    value: preferences.rewindResetsAutosens,
                    settable: self
                ),
                Field(
                    displayName: "High Temptarget Raises Sensitivity",
                    keypath: \.highTemptargetRaisesSensitivity,
                    value: preferences.highTemptargetRaisesSensitivity,
                    settable: self
                ),
                Field(
                    displayName: "Low Temptarget Lowers Sensitivity",
                    keypath: \.lowTemptargetLowersSensitivity,
                    value: preferences.lowTemptargetLowersSensitivity,
                    settable: self
                ),
                Field(
                    displayName: "Sensitivity Raises Target",
                    keypath: \.sensitivityRaisesTarget,
                    value: preferences.sensitivityRaisesTarget,
                    settable: self
                ),
                Field(
                    displayName: "Resistance Lowers Target",
                    keypath: \.resistanceLowersTarget,
                    value: preferences.resistanceLowersTarget,
                    settable: self
                ),
                Field(
                    displayName: "Advanced Target Adjustments",
                    keypath: \.advTargetAdjustments,
                    value: preferences.advTargetAdjustments,
                    settable: self
                ),
                Field(
                    displayName: "Exercise Mode",
                    keypath: \.exerciseMode,
                    value: preferences.exerciseMode,
                    settable: self
                ),
                Field(
                    displayName: "Wide BG Target Range",
                    keypath: \.wideBGTargetRange,
                    value: preferences.wideBGTargetRange,
                    settable: self
                ),
                Field(
                    displayName: "Skip Neutral Temps",
                    keypath: \.skipNeutralTemps,
                    value: preferences.skipNeutralTemps,
                    settable: self
                ),
                Field(
                    displayName: "Unsuspend If No Temp",
                    keypath: \.unsuspendIfNoTemp,
                    value: preferences.unsuspendIfNoTemp,
                    settable: self
                ),
                Field(
                    displayName: "Enable UAM",
                    keypath: \.enableUAM,
                    value: preferences.enableUAM,
                    settable: self
                ),
//                Field(
//                    displayName: "A52 Risk Enable",
//                    keypath: \.a52RiskEnable,
//                    value: preferences.a52RiskEnable,
//                    settable: self
//                ),
                Field(
                    displayName: "Enable SMB With COB",
                    keypath: \.enableSMBWithCOB,
                    value: preferences.enableSMBWithCOB,
                    settable: self
                ),
                Field(
                    displayName: "Enable SMB With Temptarget",
                    keypath: \.enableSMBWithTemptarget,
                    value: preferences.enableSMBWithTemptarget,
                    settable: self
                ),
                Field(
                    displayName: "Enable SMB Always",
                    keypath: \.enableSMBAlways,
                    value: preferences.enableSMBAlways,
                    settable: self
                ),
                Field(
                    displayName: "Enable SMB After Carbs",
                    keypath: \.enableSMBAfterCarbs,
                    value: preferences.enableSMBAfterCarbs,
                    settable: self
                ),
                Field(
                    displayName: "Allow SMB With High Temptarget",
                    keypath: \.allowSMBWithHighTemptarget,
                    value: preferences.allowSMBWithHighTemptarget,
                    settable: self
                ),
                Field(
                    displayName: "Use Custom Peak Time",
                    keypath: \.useCustomPeakTime,
                    value: preferences.useCustomPeakTime,
                    settable: self
                ),
                Field(
                    displayName: "Suspend Zeros IOB",
                    keypath: \.suspendZerosIOB,
                    value: preferences.suspendZerosIOB,
                    settable: self
                )
            ]

            decimalFields = [
                Field(
                    displayName: "Max IOB",
                    keypath: \.maxIOB,
                    value: preferences.maxIOB,
                    settable: self
                ),
                Field(
                    displayName: "Max Daily Safety Multiplier",
                    keypath: \.maxDailySafetyMultiplier,
                    value: preferences.maxDailySafetyMultiplier,
                    settable: self
                ),
                Field(
                    displayName: "Current Basal Safety Multiplier",
                    keypath: \.currentBasalSafetyMultiplier,
                    value: preferences.currentBasalSafetyMultiplier,
                    settable: self
                ),
                Field(
                    displayName: "Autosens Max",
                    keypath: \.autosensMax,
                    value: preferences.autosensMax,
                    settable: self
                ),
                Field(
                    displayName: "Autosens Min",
                    keypath: \.autosensMin,
                    value: preferences.autosensMin,
                    settable: self
                ),
                Field(
                    displayName: "Half Basal Exercise Target",
                    keypath: \.halfBasalExerciseTarget,
                    value: preferences.halfBasalExerciseTarget,
                    settable: self
                ),
                Field(
                    displayName: "Max COB",
                    keypath: \.maxCOB,
                    value: preferences.maxCOB,
                    settable: self
                ),
                Field(
                    displayName: "Bolus Snooze DIA Divisor",
                    keypath: \.bolusSnoozeDIADivisor,
                    value: preferences.bolusSnoozeDIADivisor,
                    settable: self
                ),
                Field(
                    displayName: "Min 5m Carbimpact",
                    keypath: \.min5mCarbimpact,
                    value: preferences.min5mCarbimpact,
                    settable: self
                ),
                Field(
                    displayName: "Autotune ISF Adjustment Fraction",
                    keypath: \.autotuneISFAdjustmentFraction,
                    value: preferences.autotuneISFAdjustmentFraction,
                    settable: self
                ),
                Field(
                    displayName: "Remaining Carbs Fraction",
                    keypath: \.remainingCarbsFraction,
                    value: preferences.remainingCarbsFraction,
                    settable: self
                ),
                Field(
                    displayName: "Remaining Carbs Cap",
                    keypath: \.remainingCarbsCap,
                    value: preferences.remainingCarbsCap,
                    settable: self
                ),
                Field(
                    displayName: "Max SMB Basal Minutes",
                    keypath: \.maxSMBBasalMinutes,
                    value: preferences.maxSMBBasalMinutes,
                    settable: self
                ),
                Field(
                    displayName: "Max UAM SMB Basal Minutes",
                    keypath: \.maxUAMSMBBasalMinutes,
                    value: preferences.maxUAMSMBBasalMinutes,
                    settable: self
                ),
                Field(
                    displayName: "SMB Interval",
                    keypath: \.smbInterval,
                    value: preferences.smbInterval,
                    settable: self
                ),
                Field(
                    displayName: "Bolus Increment",
                    keypath: \.bolusIncrement,
                    value: preferences.bolusIncrement,
                    settable: self
                ),
                Field(
                    displayName: "Insulin Peak Time",
                    keypath: \.insulinPeakTime,
                    value: preferences.insulinPeakTime,
                    settable: self
                ),
                Field(
                    displayName: "Carbs Req Threshold",
                    keypath: \.carbsReqThreshold,
                    value: preferences.carbsReqThreshold,
                    settable: self
                ),
                Field(
                    displayName: "Noisy CGM Target Multiplier",
                    keypath: \.noisyCGMTargetMultiplier,
                    value: preferences.noisyCGMTargetMultiplier,
                    settable: self
                )
            ]
        }

        func onSet<T>(_ keypath: WritableKeyPath<Preferences, T>, value: T) {
            preferences[keyPath: keypath] = value
            save()
        }

        func save() {
            provider.savePreferences(preferences)
        }
    }
}
