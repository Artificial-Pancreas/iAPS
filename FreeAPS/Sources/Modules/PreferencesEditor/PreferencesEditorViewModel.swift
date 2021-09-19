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
        @Published var skipBolusScreenAfterCarbs = false

        @Published var decimalFields: [Field<Decimal>] = []
        @Published var boolFields: [Field<Bool>] = []
        @Published var insulinCurveField = Field<InsulinCurve>(
            displayName: "Insulin curve",
            keypath: \.curve,
            value: .rapidActing,
            infoText: "Insulin curve info"
        )

        override func subscribe() {
            preferences = provider.preferences
            unitsIndex = settingsManager.settings.units == .mgdL ? 0 : 1
            allowAnnouncements = settingsManager.settings.allowAnnouncements
            insulinCurveField.value = preferences.curve
            insulinCurveField.settable = self
            insulinReqFraction = settingsManager.settings.insulinReqFraction ?? 0.7
            skipBolusScreenAfterCarbs = settingsManager.settings.skipBolusScreenAfterCarbs ?? false

            $unitsIndex
                .removeDuplicates()
                .sink { [weak self] index in
                    self?.settingsManager.settings.units = index == 0 ? .mgdL : .mmolL
                    self?.provider.migrateUnits()
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

            $skipBolusScreenAfterCarbs
                .removeDuplicates()
                .sink { [weak self] skip in
                    self?.settingsManager.settings.skipBolusScreenAfterCarbs = skip
                }
                .store(in: &lifetime)

            boolFields = [
                Field(
                    displayName: "Rewind Resets Autosens",
                    keypath: \.rewindResetsAutosens,
                    value: preferences.rewindResetsAutosens,
                    infoText: NSLocalizedString(
                        "This feature, enabled by default, resets the autosens ratio to neutral when you rewind your pump, on the assumption that this corresponds to a probable site change. Autosens will begin learning sensitivity anew from the time of the rewind, which may take up to 6 hours. If you usually rewind your pump independently of site changes, you may want to consider disabling this feature.",
                        comment: "Rewind Resets Autosens"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "High Temptarget Raises Sensitivity",
                    keypath: \.highTemptargetRaisesSensitivity,
                    value: preferences.highTemptargetRaisesSensitivity,
                    infoText: NSLocalizedString(
                        "Defaults to false. When set to true, raises sensitivity (lower sensitivity ratio) for temp targets set to >= 111. Synonym for exercise_mode. The higher your temp target above 110 will result in more sensitive (lower) ratios, e.g., temp target of 120 results in sensitivity ratio of 0.75, while 140 results in 0.6 (with default halfBasalTarget of 160).",
                        comment: "High Temptarget Raises Sensitivity"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Low Temptarget Lowers Sensitivity",
                    keypath: \.lowTemptargetLowersSensitivity,
                    value: preferences.lowTemptargetLowersSensitivity,
                    infoText: NSLocalizedString(
                        "Defaults to false. When set to true, can lower sensitivity (higher sensitivity ratio) for temptargets <= 99. The lower your temp target below 100 will result in less sensitive (higher) ratios, e.g., temp target of 95 results in sensitivity ratio of 1.09, while 85 results in 1.33 (with default halfBasalTarget of 160).",
                        comment: "Low Temptarget Lowers Sensitivity"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Sensitivity Raises Target",
                    keypath: \.sensitivityRaisesTarget,
                    value: preferences.sensitivityRaisesTarget,
                    infoText: NSLocalizedString(
                        "When true, raises BG target when autosens detects sensitivity",
                        comment: "Sensitivity Raises Target"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Resistance Lowers Target",
                    keypath: \.resistanceLowersTarget,
                    value: preferences.resistanceLowersTarget,
                    infoText: NSLocalizedString(
                        "Defaults to false. When true, will lower BG target when autosens detects resistance",
                        comment: "Resistance Lowers Target"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Advanced Target Adjustments",
                    keypath: \.advTargetAdjustments,
                    value: preferences.advTargetAdjustments,
                    infoText: NSLocalizedString(
                        "This feature was previously enabled by default but will now default to false (will NOT be enabled automatically) in oref0 0.6.0 and beyond. (There is no need for this with 0.6.0). This feature lowers oref0’s target BG automatically when current BG and eventualBG are high. This helps prevent and mitigate high BG, but automatically switches to low-temping to ensure that BG comes down smoothly toward your actual target. If you find this behavior too aggressive, you can disable this feature. If you do so, please let us know so we can better understand what settings work best for everyone.",
                        comment: "Advanced Target Adjustments"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Exercise Mode",
                    keypath: \.exerciseMode,
                    value: preferences.exerciseMode,
                    infoText: NSLocalizedString(
                        "Defaults to false. When true, > 105 mg/dL high temp target adjusts sensitivityRatio for exercise_mode. Synonym for high_temptarget_raises_sensitivity",
                        comment: "Exercise Mode"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Wide BG Target Range",
                    keypath: \.wideBGTargetRange,
                    value: preferences.wideBGTargetRange,
                    infoText: NSLocalizedString(
                        "Defaults to false, which means by default only the low end of the pump’s BG target range is used as OpenAPS target. This is a safety feature to prevent too-wide targets and less-optimal outcomes. Therefore the higher end of the target range is used only for avoiding bolus wizard overcorrections. Use wide_bg_target_range: true to force neutral temps over a wider range of eventualBGs.",
                        comment: "Wide BG Target Range"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Skip Neutral Temps",
                    keypath: \.skipNeutralTemps,
                    value: preferences.skipNeutralTemps,
                    infoText: NSLocalizedString(
                        "Defaults to false, so that FreeAPS X will set temps whenever it can, so it will be easier to see if the system is working, even when you are offline. This means FreeAPS X will set a “neutral” temp (same as your default basal) if no adjustments are needed. This is an old setting for OpenAPS to have the options to minimise sounds and notifications from the 'rig', that may wake you up during the night.",
                        comment: "Skip Neutral Temps"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Unsuspend If No Temp",
                    keypath: \.unsuspendIfNoTemp,
                    value: preferences.unsuspendIfNoTemp,
                    infoText: NSLocalizedString(
                        "Many people occasionally forget to resume / unsuspend their pump after reconnecting it. If you’re one of them, and you are willing to reliably set a zero temp basal whenever suspending and disconnecting your pump, this feature has your back. If enabled, it will automatically resume / unsuspend the pump if you forget to do so before your zero temp expires. As long as the zero temp is still running, it will leave the pump suspended.",
                        comment: "Unsuspend If No Temp"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Enable UAM",
                    keypath: \.enableUAM,
                    value: preferences.enableUAM,
                    infoText: NSLocalizedString(
                        "With this option enabled, the SMB algorithm can recognize unannounced meals. This is helpful, if you forget to tell AndroidAPS about your carbs or estimate your carbs wrong and the amount of entered carbs is wrong or if a meal with lots of fat and protein has a longer duration than expected. Without any carb entry, UAM can recognize fast glucose increasments caused by carbs, adrenaline, etc, and tries to adjust it with SMBs. This also works the opposite way: if there is a fast glucose decreasement, it can stop SMBs earlier.",
                        comment: "Enable UAM"
                    ),
                    settable: self
                ),
                /*
                    Field(
                        displayName: "A52 Risk Enable",
                        keypath: \.a52RiskEnable,
                        value: preferences.a52RiskEnable,
                    infoText: NSLocalizedString("Defaults to false. Using the pump bolus wizard to enter carbs will prevent SMBs from being enabled for COB as long as those carbs are active. Using the pump bolus wizard will prevent SMBs from being enabled for up to 6 hours by the “after carbs” or “always” preferences. If anyone wants to get around that, they can add A52_risk_enable (with the capital A) to preferences and set it to “true” to acknowledge and intentionally use that approach, which we know leads to increased A52 errors.\n\n(the recommended method for using SMBs is to enter carbs via NS and easy bolus any desired up-front insulin (generally less than the full amount that would be recommended by the bolus wizard) and then let SMB fill in the rest as it is safe to do so. For situations where the bolus wizard is preferred, such as for carb entry by inexperienced caregivers, or for offline use, we feel that it is safer for OpenAPS to disable SMBs and fall back to AMA until the next meal. In addition to reducing the risk of A52 errors, disabling SMBs when the bolus wizard is in use leads to more predictable AMA behavior (instead of SMB zero-temping) for untrained caregivers in an environment that is usually more prone to walk-away pump communication issues.)", comment: "A52 Risk Enable"),
                    settable: self
                     ),*/
                Field(
                    displayName: "Enable SMB With COB",
                    keypath: \.enableSMBWithCOB,
                    value: preferences.enableSMBWithCOB,
                    infoText: NSLocalizedString(
                        "This enables supermicrobolus (SMB) while carbs on board (COB) are positive.",
                        comment: "Enable SMB With COB"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Enable SMB With Temptarget",
                    keypath: \.enableSMBWithTemptarget,
                    value: preferences.enableSMBWithTemptarget,
                    infoText: NSLocalizedString(
                        "This enables supermicrobolus (SMB) with eating soon / low temp targets. With this feature enabled, any temporary target below 100mg/dL, such as a temp target of 99 (or 80, the typical eating soon target) will enable SMB.",
                        comment: "Enable SMB With Temptarget"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Enable SMB Always",
                    keypath: \.enableSMBAlways,
                    value: preferences.enableSMBAlways,
                    infoText: NSLocalizedString(
                        "Defaults to false. When true, always enable supermicrobolus (unless disabled by high temptarget).",
                        comment: "Enable SMB Always"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Enable SMB After Carbs",
                    keypath: \.enableSMBAfterCarbs,
                    value: preferences.enableSMBAfterCarbs,
                    infoText: NSLocalizedString(
                        "Defaults to false. When true, enables supermicrobolus (SMB) for 6h after carbs, even with 0 carbs on board (COB).",
                        comment: "Enable SMB After Carbs"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Allow SMB With High Temptarget",
                    keypath: \.allowSMBWithHighTemptarget,
                    value: preferences.allowSMBWithHighTemptarget,
                    infoText: NSLocalizedString(
                        "Defaults to false. When true, allows supermicrobolus (if otherwise enabled) even with high temp targets.",
                        comment: "Allow SMB With High Temptarget"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Use Custom Peak Time",
                    keypath: \.useCustomPeakTime,
                    value: preferences.useCustomPeakTime,
                    infoText: NSLocalizedString(
                        "Defaults to false. Setting to true allows changing insulinPeakTime", comment: "Use Custom Peak Time"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Suspend Zeros IOB",
                    keypath: \.suspendZerosIOB,
                    value: preferences.suspendZerosIOB,
                    infoText: NSLocalizedString(
                        "Many people occasionally forget to resume / unsuspend their pump after reconnecting it. If you’re one of them, and you are willing to reliably set a zero temp basal whenever suspending and disconnecting your pump, this feature has your back. If enabled, it will automatically resume / unsuspend the pump if you forget to do so before your zero temp expires. As long as the zero temp is still running, it will leave the pump suspended.",
                        comment: "Suspend Zeros IOB"
                    ),
                    settable: self
                )
            ]
            decimalFields = [
                Field(
                    displayName: "Max IOB",
                    keypath: \.maxIOB,
                    value: preferences.maxIOB,
                    infoText: NSLocalizedString(
                        "Max IOB is the maximum amount of insulin on board from all sources – basal, SMBs and bolus insulin – that your loop is allowed to accumulate to treat higher-than-target BG. Unlike the other two OpenAPS safety settings (Max Daily Safety Multiplier and Current Basal Safety Multiplier), Max IOB is set as a fixed number of units of insulin. As of now manual boluses are NOT limited by this setting. \n\n To test your basal rates during nighttime, you can modify the Max IOB setting to zero while in Closed Loop. This will enable low glucose suspend mode while testing your basal rates settings\n\n(Tip from https://www.loopandlearn.org/freeaps-x/#open-loop).",
                        comment: "Max IOB"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Max Daily Safety Multiplier",
                    keypath: \.maxDailySafetyMultiplier,
                    value: preferences.maxDailySafetyMultiplier,
                    infoText: NSLocalizedString(
                        "This is an important OpenAPS safety limit. The default setting (which is unlikely to need adjusting) is 3. This means that OpenAPS will never be allowed to set a temporary basal rate that is more than 3x the highest hourly basal rate programmed in a user’s pump, or, if enabled, determined by autotune.",
                        comment: "Max Daily Safety Multiplier"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Current Basal Safety Multiplier",
                    keypath: \.currentBasalSafetyMultiplier,
                    value: preferences.currentBasalSafetyMultiplier,
                    infoText: NSLocalizedString(
                        "This is another important OpenAPS safety limit. The default setting (which is also unlikely to need adjusting) is 4. This means that OpenAPS will never be allowed to set a temporary basal rate that is more than 4x the current hourly basal rate programmed in a user’s pump, or, if enabled, determined by autotune.",
                        comment: "Current Basal Safety Multiplier"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Autosens Max",
                    keypath: \.autosensMax,
                    value: preferences.autosensMax,
                    infoText: NSLocalizedString(
                        "This is a multiplier cap for autosens (and autotune) to set a 20% max limit on how high the autosens ratio can be, which in turn determines how high autosens can adjust basals, how low it can adjust ISF, and how low it can set the BG target.",
                        comment: "Autosens Max"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Autosens Min",
                    keypath: \.autosensMin,
                    value: preferences.autosensMin,
                    infoText: NSLocalizedString(
                        "The other side of the autosens safety limits, putting a cap on how low autosens can adjust basals, and how high it can adjust ISF and BG targets.",
                        comment: "Autosens Min"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Half Basal Exercise Target",
                    keypath: \.halfBasalExerciseTarget,
                    value: preferences.halfBasalExerciseTarget,
                    infoText: NSLocalizedString(
                        "Set to a number, e.g. 160, which means when temp target is 160 mg/dL and exercise_mode=true, run 50% basal at this level (120 = 75%; 140 = 60%). This can be adjusted, to give you more control over your exercise modes.",
                        comment: "Half Basal Exercise Target"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Max COB",
                    keypath: \.maxCOB,
                    value: preferences.maxCOB,
                    infoText: NSLocalizedString(
                        "This defaults maxCOB to 120 because that’s the most a typical body can absorb over 4 hours. (If someone enters more carbs or stacks more; OpenAPS will just truncate dosing based on 120. Essentially, this just limits AMA as a safety cap against weird COB calculations due to fluky data.)",
                        comment: "Max COB"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Bolus Snooze DIA Divisor",
                    keypath: \.bolusSnoozeDIADivisor,
                    value: preferences.bolusSnoozeDIADivisor,
                    infoText: NSLocalizedString(
                        "Bolus snooze is enacted after you do a meal bolus, so the loop won’t counteract with low temps when you’ve just eaten. The example here and default is 2; so a 3 hour DIA means that bolus snooze will be gradually phased out over 1.5 hours (3DIA/2).",
                        comment: "Bolus Snooze DIA Divisor"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Min 5m Carbimpact",
                    keypath: \.min5mCarbimpact,
                    value: preferences.min5mCarbimpact,
                    infoText: NSLocalizedString(
                        "This is a setting for default carb absorption impact per 5 minutes. The default is an expected 8 mg/dL/5min. This affects how fast COB is decayed in situations when carb absorption is not visible in BG deviations. The default of 8 mg/dL/5min corresponds to a minimum carb absorption rate of 24g/hr at a CSF of 4 mg/dL/g.",
                        comment: "Min 5m Carbimpact"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Autotune ISF Adjustment Fraction",
                    keypath: \.autotuneISFAdjustmentFraction,
                    value: preferences.autotuneISFAdjustmentFraction,
                    infoText: NSLocalizedString(
                        "The default of 0.5 for this value keeps autotune ISF closer to pump ISF via a weighted average of fullNewISF and pumpISF. 1.0 allows full adjustment, 0 is no adjustment from pump ISF.",
                        comment: "Autotune ISF Adjustment Fraction"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Remaining Carbs Fraction",
                    keypath: \.remainingCarbsFraction,
                    value: preferences.remainingCarbsFraction,
                    infoText: NSLocalizedString(
                        "This is the fraction of carbs we’ll assume will absorb over 4h if we don’t yet see carb absorption.",
                        comment: "Remaining Carbs Fraction"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Remaining Carbs Cap",
                    keypath: \.remainingCarbsCap,
                    value: preferences.remainingCarbsCap,
                    infoText: NSLocalizedString(
                        "This is the amount of the maximum number of carbs we’ll assume will absorb over 4h if we don’t yet see carb absorption.",
                        comment: "Remaining Carbs Cap"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Max SMB Basal Minutes",
                    keypath: \.maxSMBBasalMinutes,
                    value: preferences.maxSMBBasalMinutes,
                    infoText: NSLocalizedString(
                        "Defaults to start at 30. This is the maximum minutes of basal that can be delivered as a single SMB with uncovered COB. This gives the ability to make SMB more aggressive if you choose. It is recommended that the value is set to start at 30, in line with the default, and if you choose to increase this value, do so in no more than 15 minute increments, keeping a close eye on the effects of the changes. It is not recommended to set this value higher than 90 mins, as this may affect the ability for the algorithm to safely zero temp. It is also recommended that pushover is used when setting the value to be greater than default, so that alerts are generated for any predicted lows or highs.",
                        comment: "Max SMB Basal Minutes"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Max UAM SMB Basal Minutes",
                    keypath: \.maxUAMSMBBasalMinutes,
                    value: preferences.maxUAMSMBBasalMinutes,
                    infoText: NSLocalizedString(
                        "Defaults to start at 30. This is the maximum minutes of basal that can be delivered by UAM as a single SMB when IOB exceeds COB. This gives the ability to make UAM more or less aggressive if you choose. It is recommended that the value is set to start at 30, in line with the default, and if you choose to increase this value, do so in no more than 15 minute increments, keeping a close eye on the effects of the changes. Reducing the value will cause UAM to dose less insulin for each SMB. It is not recommended to set this value higher than 60 mins, as this may affect the ability for the algorithm to safely zero temp. It is also recommended that pushover is used when setting the value to be greater than default, so that alerts are generated for any predicted lows or highs.",
                        comment: "Max UAM SMB Basal Minutes"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "SMB Interval",
                    keypath: \.smbInterval,
                    value: preferences.smbInterval,
                    infoText: NSLocalizedString("Minimum duration in minutes between two enacted SMBs", comment: "SMB Interval"),
                    settable: self
                ),
                Field(
                    displayName: "Bolus Increment",
                    keypath: \.bolusIncrement,
                    value: preferences.bolusIncrement,
                    infoText: NSLocalizedString("Smallest possible bolus amount", comment: "Bolus Increment"),
                    settable: self
                ),
                Field(
                    displayName: "Insulin Peak Time",
                    keypath: \.insulinPeakTime,
                    value: preferences.insulinPeakTime,
                    infoText: NSLocalizedString(
                        "Maximun blood glucose lowering effect of insulin, in minutes",
                        comment: "Insulin Peak Time"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Carbs Req Threshold",
                    keypath: \.carbsReqThreshold,
                    value: preferences.carbsReqThreshold,
                    infoText: NSLocalizedString(
                        "Grams of carbsReq to trigger a pushover. Defaults to 1 (for 1 gram of carbohydrate). Can be increased if you only want to get Pushover for carbsReq at X threshold.",
                        comment: "Carbs Req Threshold"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Noisy CGM Target Multiplier",
                    keypath: \.noisyCGMTargetMultiplier,
                    value: preferences.noisyCGMTargetMultiplier,
                    infoText: NSLocalizedString("Nothing here yet...", comment: "Noisy CGM Target Multiplier"),
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
