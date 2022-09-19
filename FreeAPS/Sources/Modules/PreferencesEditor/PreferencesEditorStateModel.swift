import Foundation
import SwiftUI

extension PreferencesEditor {
    final class StateModel: BaseStateModel<Provider>, PreferencesSettable { private(set) var preferences = Preferences()
        @Published var unitsIndex = 1
        @Published var allowAnnouncements = false
        @Published var insulinReqFraction: Decimal = 2.0
        @Published var skipBolusScreenAfterCarbs = false
        @Published var displayHR = false

        @Published var sections: [FieldSection] = []

        override func subscribe() {
            preferences = provider.preferences

            subscribeSetting(\.allowAnnouncements, on: $allowAnnouncements) { allowAnnouncements = $0 }
            subscribeSetting(\.insulinReqFraction, on: $insulinReqFraction) { insulinReqFraction = $0 }
            subscribeSetting(\.displayHR, on: $displayHR) { displayHR = $0 }
            subscribeSetting(\.skipBolusScreenAfterCarbs, on: $skipBolusScreenAfterCarbs) { skipBolusScreenAfterCarbs = $0 }

            subscribeSetting(\.units, on: $unitsIndex.map { $0 == 0 ? GlucoseUnits.mgdL : .mmolL }) {
                unitsIndex = $0 == .mgdL ? 0 : 1
            } didSet: { [weak self] _ in
                self?.provider.migrateUnits()
            }

            // MARK: - Main fields

            let mainFields = [
                Field(
                    displayName: "Insulin curve",
                    type: .insulinCurve(keypath: \.curve),
                    infoText: "Insulin curve info",
                    settable: self
                ),
                Field(
                    displayName: "Max IOB",
                    type: .decimal(keypath: \.maxIOB),
                    infoText: NSLocalizedString(
                        "Max IOB is the maximum amount of insulin on board from all sources – both basal (or SMB correction) and bolus insulin – that your loop is allowed to accumulate to treat higher-than-target BG. Unlike the other two OpenAPS safety settings (max_daily_safety_multiplier and current_basal_safety_multiplier), max_iob is set as a fixed number of units of insulin. As of now manual boluses are NOT limited by this setting. \n\n To test your basal rates during nighttime, you can modify the Max IOB setting to zero while in Closed Loop. This will enable low glucose suspend mode while testing your basal rates settings\n\n(Tip from https://www.loopandlearn.org/freeaps-x/#open-loop).",
                        comment: "Max IOB"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Max COB",
                    type: .decimal(keypath: \.maxCOB),
                    infoText: NSLocalizedString(
                        "This defaults maxCOB to 120 because that’s the most a typical body can absorb over 4 hours. (If someone enters more carbs or stacks more; OpenAPS will just truncate dosing based on 120. Essentially, this just limits AMA as a safety cap against weird COB calculations due to fluky data.)",
                        comment: "Max COB"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Max Daily Safety Multiplier",
                    type: .decimal(keypath: \.maxDailySafetyMultiplier),
                    infoText: NSLocalizedString(
                        "This is an important OpenAPS safety limit. The default setting (which is unlikely to need adjusting) is 3. This means that OpenAPS will never be allowed to set a temporary basal rate that is more than 3x the highest hourly basal rate programmed in a user’s pump, or, if enabled, determined by autotune.",
                        comment: "Max Daily Safety Multiplier"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Current Basal Safety Multiplier",
                    type: .decimal(keypath: \.currentBasalSafetyMultiplier),
                    infoText: NSLocalizedString(
                        "This is another important OpenAPS safety limit. The default setting (which is also unlikely to need adjusting) is 4. This means that OpenAPS will never be allowed to set a temporary basal rate that is more than 4x the current hourly basal rate programmed in a user’s pump, or, if enabled, determined by autotune.",
                        comment: "Current Basal Safety Multiplier"
                    ),
                    settable: self
                ),

                Field(
                    displayName: "Autosens Max",
                    type: .decimal(keypath: \.autosensMax),
                    infoText: NSLocalizedString(
                        "This is a multiplier cap for autosens (and autotune) to set a 20% max limit on how high the autosens ratio can be, which in turn determines how high autosens can adjust basals, how low it can adjust ISF, and how low it can set the BG target.",
                        comment: "Autosens Max"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Autosens Min",
                    type: .decimal(keypath: \.autosensMin),
                    infoText: NSLocalizedString(
                        "The other side of the autosens safety limits, putting a cap on how low autosens can adjust basals, and how high it can adjust ISF and BG targets.",
                        comment: "Autosens Min"
                    ),
                    settable: self
                )
            ]

            // MARK: - SMB fields

            let dynamicISF = [
                Field(
                    displayName: "Enable Dynamic ISF",
                    type: .boolean(keypath: \.enableChris),
                    infoText: NSLocalizedString(
                        "Change ISF with every loop cycle. New ISF will be based on current BG, TDD if insulin (past 24 hours or a weighted average) and an Adjustment Factor (default is 1). Dynamic ISF and CR ratios will be limited by your autosens.min/max limits. Dynamic ratio replaces the autosens.ratio: New ISF = Static ISF / Dynamic ratio",
                        comment: "Enable Dynamic ISF"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Enable Dynamic CR",
                    type: .boolean(keypath: \.enableDynamicCR),
                    infoText: NSLocalizedString(
                        "Use Dynamic CR. The dynamic ratio will be used also for CR: New CR = CR / Dynamic ratio. When using toghether with a high Insulin Fraction (>2), the recommended bolus for meals could get too high.",
                        comment: "Use Dynamic CR together with Dynamic ISF"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Adjustment Factor",
                    type: .decimal(keypath: \.adjustmentFactor),
                    infoText: NSLocalizedString(
                        "Adjust Dynamic ratios by a constant. Default is 1. Higher than 1 => lower ISF",
                        comment: "Adjust Dynamic ISF constant"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Use Logarithmic Formula",
                    type: .boolean(keypath: \.useNewFormula),
                    infoText: NSLocalizedString(
                        "New Logarithmic Formula. More aggressive at lower and normal BG and less aggressive at really high BG. Use a lower AF (compared to Original Formula) when using the Logaritmic Formula. ",
                        comment: "Use Logarithmic Formula"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Weighted Average of TDD. Weight of past 24 hours:",
                    type: .decimal(keypath: \.weightPercentage),
                    infoText: NSLocalizedString(
                        "Has to be > 0 and <= 1.\nDefault is 0.65 (65 %) * past 24 hours. The rest will be from 7 days TDD average (0.35). To only use past 24 hours, set this to 1.\nTo avoid sudden fluctuations, an average of past 2 hours of TDD calc is used as past 24 hours TDD.",
                        comment: "Weight of past 24 hours of TDD"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Adjust basal",
                    type: .boolean(keypath: \.tddAdjBasal),
                    infoText: NSLocalizedString(
                        "Enable adjustment of basal based on the ratio of 24 h : 7 day average TDD",
                        comment: "Enable adjustment of basal based on the ratio of 24 h : 7 day average TDD"
                    ),
                    settable: self
                )
            ]

            let smbFields = [
                Field(
                    displayName: "Enable SMB Always",
                    type: .boolean(keypath: \.enableSMBAlways),
                    infoText: NSLocalizedString(
                        "Defaults to false. When true, always enable supermicrobolus (unless disabled by high temptarget).",
                        comment: "Enable SMB Always"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Max Delta-BG Threshold SMB",
                    type: .decimal(keypath: \.maxDeltaBGthreshold),
                    infoText: NSLocalizedString(
                        "Defaults to 0.2 (20%). Maximum positiv %change of BG level to use SMB, above that will disable SMB. Hardcoded cap of 40%. For UAM fully-closed-loop 30% is advisable. Observe in log and popup (maxDelta 27 > 20% of BG 100 - disabling SMB!).",
                        comment: "Max Delta-BG Threshold"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Enable SMB With COB",
                    type: .boolean(keypath: \.enableSMBWithCOB),
                    infoText: NSLocalizedString(
                        "This enables supermicrobolus (SMB) while carbs on board (COB) are positive.",
                        comment: "Enable SMB With COB"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Enable SMB With Temptarget",
                    type: .boolean(keypath: \.enableSMBWithTemptarget),
                    infoText: NSLocalizedString(
                        "This enables supermicrobolus (SMB) with eating soon / low temp targets. With this feature enabled, any temporary target below 100mg/dL, such as a temp target of 99 (or 80, the typical eating soon target) will enable SMB.",
                        comment: "Enable SMB With Temptarget"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Enable SMB After Carbs",
                    type: .boolean(keypath: \.enableSMBAfterCarbs),
                    infoText: NSLocalizedString(
                        "Defaults to false. When true, enables supermicrobolus (SMB) for 6h after carbs, even with 0 carbs on board (COB).",
                        comment: "Enable SMB After Carbs"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Allow SMB With High Temptarget",
                    type: .boolean(keypath: \.allowSMBWithHighTemptarget),
                    infoText: NSLocalizedString(
                        "Defaults to false. When true, allows supermicrobolus (if otherwise enabled) even with high temp targets.",
                        comment: "Allow SMB With High Temptarget"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Enable UAM",
                    type: .boolean(keypath: \.enableUAM),
                    infoText: NSLocalizedString(
                        "With this option enabled, the SMB algorithm can recognize unannounced meals. This is helpful, if you forget to tell FreeAPS X about your carbs or estimate your carbs wrong and the amount of entered carbs is wrong or if a meal with lots of fat and protein has a longer duration than expected. Without any carb entry, UAM can recognize fast glucose increasments caused by carbs, adrenaline, etc, and tries to adjust it with SMBs. This also works the opposite way: if there is a fast glucose decreasement, it can stop SMBs earlier.",
                        comment: "Enable UAM"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Max SMB Basal Minutes",
                    type: .decimal(keypath: \.maxSMBBasalMinutes),
                    infoText: NSLocalizedString(
                        "Defaults to start at 30. This is the maximum minutes of basal that can be delivered as a single SMB with uncovered COB. This gives the ability to make SMB more aggressive if you choose. It is recommended that the value is set to start at 30, in line with the default, and if you choose to increase this value, do so in no more than 15 minute increments, keeping a close eye on the effects of the changes. It is not recommended to set this value higher than 90 mins, as this may affect the ability for the algorithm to safely zero temp. It is also recommended that pushover is used when setting the value to be greater than default, so that alerts are generated for any predicted lows or highs.",
                        comment: "Max SMB Basal Minutes"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Max UAM SMB Basal Minutes",
                    type: .decimal(keypath: \.maxUAMSMBBasalMinutes),
                    infoText: NSLocalizedString(
                        "Defaults to start at 30. This is the maximum minutes of basal that can be delivered by UAM as a single SMB when IOB exceeds COB. This gives the ability to make UAM more or less aggressive if you choose. It is recommended that the value is set to start at 30, in line with the default, and if you choose to increase this value, do so in no more than 15 minute increments, keeping a close eye on the effects of the changes. Reducing the value will cause UAM to dose less insulin for each SMB. It is not recommended to set this value higher than 60 mins, as this may affect the ability for the algorithm to safely zero temp. It is also recommended that pushover is used when setting the value to be greater than default, so that alerts are generated for any predicted lows or highs.",
                        comment: "Max UAM SMB Basal Minutes"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "SMB DeliveryRatio",
                    type: .decimal(keypath: \.smbDeliveryRatio),
                    infoText: NSLocalizedString(
                        "Default value: 0.5 This is another key OpenAPS safety cap, and specifies what share of the total insulin required can be delivered as SMB. Increase this experimental value slowly and with caution.",
                        comment: "SMB DeliveryRatio"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "SMB Interval",
                    type: .decimal(keypath: \.smbInterval),
                    infoText: NSLocalizedString("Minimum duration in minutes between two enacted SMBs", comment: "SMB Interval"),
                    settable: self
                ),
                Field(
                    displayName: "Bolus Increment",
                    type: .decimal(keypath: \.bolusIncrement),
                    infoText: NSLocalizedString(
                        "Smallest SMB / SMB increment in oref0. Minimum amount for Medtronic pumps is 0.1 U, whereas for Omnipod it’s 0.05 U. The default value is 0.1.",
                        comment: "Bolus Increment"
                    ),
                    settable: self
                )
            ]

            // MARK: - Targets fields

            let targetSettings = [
                Field(
                    displayName: "High Temptarget Raises Sensitivity",
                    type: .boolean(keypath: \.highTemptargetRaisesSensitivity),
                    infoText: NSLocalizedString(
                        "Defaults to false. When set to true, raises sensitivity (lower sensitivity ratio) for temp targets set to >= 111. Synonym for exercise_mode. The higher your temp target above 110 will result in more sensitive (lower) ratios, e.g., temp target of 120 results in sensitivity ratio of 0.75, while 140 results in 0.6 (with default halfBasalTarget of 160).",
                        comment: "High Temptarget Raises Sensitivity"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Low Temptarget Lowers Sensitivity",
                    type: .boolean(keypath: \.lowTemptargetLowersSensitivity),
                    infoText: NSLocalizedString(
                        "Defaults to false. When set to true, can lower sensitivity (higher sensitivity ratio) for temptargets <= 99. The lower your temp target below 100 will result in less sensitive (higher) ratios, e.g., temp target of 95 results in sensitivity ratio of 1.09, while 85 results in 1.33 (with default halfBasalTarget of 160).",
                        comment: "Low Temptarget Lowers Sensitivity"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Sensitivity Raises Target",
                    type: .boolean(keypath: \.sensitivityRaisesTarget),
                    infoText: NSLocalizedString(
                        "When true, raises BG target when autosens detects sensitivity",
                        comment: "Sensitivity Raises Target"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Resistance Lowers Target",
                    type: .boolean(keypath: \.resistanceLowersTarget),
                    infoText: NSLocalizedString(
                        "Defaults to false. When true, will lower BG target when autosens detects resistance",
                        comment: "Resistance Lowers Target"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Advanced Target Adjustments",
                    type: .boolean(keypath: \.advTargetAdjustments),
                    infoText: NSLocalizedString(
                        "This feature was previously enabled by default but will now default to false (will NOT be enabled automatically) in oref0 0.6.0 and beyond. (There is no need for this with 0.6.0). This feature lowers oref0’s target BG automatically when current BG and eventualBG are high. This helps prevent and mitigate high BG, but automatically switches to low-temping to ensure that BG comes down smoothly toward your actual target. If you find this behavior too aggressive, you can disable this feature. If you do so, please let us know so we can better understand what settings work best for everyone.",
                        comment: "Advanced Target Adjustments"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Exercise Mode",
                    type: .boolean(keypath: \.exerciseMode),
                    infoText: NSLocalizedString(
                        "Defaults to false. When true, > 105 mg/dL high temp target adjusts sensitivityRatio for exercise_mode. Synonym for high_temptarget_raises_sensitivity",
                        comment: "Exercise Mode"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Half Basal Exercise Target",
                    type: .decimal(keypath: \.halfBasalExerciseTarget),
                    infoText: NSLocalizedString(
                        "Set to a number, e.g. 160, which means when temp target is 160 mg/dL and exercise_mode=true, run 50% basal at this level (120 = 75%; 140 = 60%). This can be adjusted, to give you more control over your exercise modes.",
                        comment: "Half Basal Exercise Target"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Wide BG Target Range",
                    type: .boolean(keypath: \.wideBGTargetRange),
                    infoText: NSLocalizedString(
                        "Defaults to false, which means by default only the low end of the pump’s BG target range is used as OpenAPS target. This is a safety feature to prevent too-wide targets and less-optimal outcomes. Therefore the higher end of the target range is used only for avoiding bolus wizard overcorrections. Use wide_bg_target_range: true to force neutral temps over a wider range of eventualBGs.",
                        comment: "Wide BG Target Range"
                    ),
                    settable: self
                )
            ]

            // MARK: - Other fields

            let otherSettings = [
                Field(
                    displayName: "Rewind Resets Autosens",
                    type: .boolean(keypath: \.rewindResetsAutosens),
                    infoText: NSLocalizedString(
                        "This feature, enabled by default, resets the autosens ratio to neutral when you rewind your pump, on the assumption that this corresponds to a probable site change. Autosens will begin learning sensitivity anew from the time of the rewind, which may take up to 6 hours. If you usually rewind your pump independently of site changes, you may want to consider disabling this feature.",
                        comment: "Rewind Resets Autosens"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Use Custom Peak Time",
                    type: .boolean(keypath: \.useCustomPeakTime),
                    infoText: NSLocalizedString(
                        "Defaults to false. Setting to true allows changing insulinPeakTime", comment: "Use Custom Peak Time"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Insulin Peak Time",
                    type: .decimal(keypath: \.insulinPeakTime),
                    infoText: NSLocalizedString(
                        "Time of maximum blood glucose lowering effect of insulin, in minutes. Beware: Oref assumes for ultra-rapid (Lyumjev) & rapid-acting (Fiasp) curves minimal (35 & 50 min) and maximal (100 & 120 min) applicable insulinPeakTimes. Using a custom insulinPeakTime outside these bounds will result in issues with FreeAPS-X, longer loop calculations and possible red loops.",
                        comment: "Insulin Peak Time"
                    ),
                    settable: self
                ),
//                Field(
//                    displayName: "Carbs Req Threshold",
//                    type: .decimal(keypath: \.carbsReqThreshold),
//                    infoText: NSLocalizedString(
//                        "Grams of carbsReq to trigger a pushover. Defaults to 1 (for 1 gram of carbohydrate). Can be increased if you only want to get Pushover for carbsReq at X threshold.",
//                        comment: "Carbs Req Threshold"
//                    ),
//                    settable: self
//                ),
                Field(
                    displayName: "Skip Neutral Temps",
                    type: .boolean(keypath: \.skipNeutralTemps),
                    infoText: NSLocalizedString(
                        "Defaults to false, so that FreeAPS X will set temps whenever it can, so it will be easier to see if the system is working, even when you are offline. This means FreeAPS X will set a “neutral” temp (same as your default basal) if no adjustments are needed. This is an old setting for OpenAPS to have the options to minimise sounds and notifications from the 'rig', that may wake you up during the night.",
                        comment: "Skip Neutral Temps"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Unsuspend If No Temp",
                    type: .boolean(keypath: \.unsuspendIfNoTemp),
                    infoText: NSLocalizedString(
                        "Many people occasionally forget to resume / unsuspend their pump after reconnecting it. If you’re one of them, and you are willing to reliably set a zero temp basal whenever suspending and disconnecting your pump, this feature has your back. If enabled, it will automatically resume / unsuspend the pump if you forget to do so before your zero temp expires. As long as the zero temp is still running, it will leave the pump suspended.",
                        comment: "Unsuspend If No Temp"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Suspend Zeros IOB",
                    type: .boolean(keypath: \.suspendZerosIOB),
                    infoText: NSLocalizedString(
                        "Default is false. Any existing temp basals during times the pump was suspended will be deleted and 0 temp basals to negate the profile basal rates during times pump is suspended will be added.",
                        comment: "Suspend Zeros IOB"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Bolus Snooze DIA Divisor",
                    type: .decimal(keypath: \.bolusSnoozeDIADivisor),
                    infoText: NSLocalizedString(
                        "Bolus snooze is enacted after you do a meal bolus, so the loop won’t counteract with low temps when you’ve just eaten. The example here and default is 2; so a 3 hour DIA means that bolus snooze will be gradually phased out over 1.5 hours (3DIA/2).",
                        comment: "Bolus Snooze DIA Divisor"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Min 5m Carbimpact",
                    type: .decimal(keypath: \.min5mCarbimpact),
                    infoText: NSLocalizedString(
                        "This is a setting for default carb absorption impact per 5 minutes. The default is an expected 8 mg/dL/5min. This affects how fast COB is decayed in situations when carb absorption is not visible in BG deviations. The default of 8 mg/dL/5min corresponds to a minimum carb absorption rate of 24g/hr at a CSF of 4 mg/dL/g.",
                        comment: "Min 5m Carbimpact"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Autotune ISF Adjustment Fraction",
                    type: .decimal(keypath: \.autotuneISFAdjustmentFraction),
                    infoText: NSLocalizedString(
                        "The default of 0.5 for this value keeps autotune ISF closer to pump ISF via a weighted average of fullNewISF and pumpISF. 1.0 allows full adjustment, 0 is no adjustment from pump ISF.",
                        comment: "Autotune ISF Adjustment Fraction"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Remaining Carbs Fraction",
                    type: .decimal(keypath: \.remainingCarbsFraction),
                    infoText: NSLocalizedString(
                        "This is the fraction of carbs we’ll assume will absorb over 4h if we don’t yet see carb absorption.",
                        comment: "Remaining Carbs Fraction"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Remaining Carbs Cap",
                    type: .decimal(keypath: \.remainingCarbsCap),
                    infoText: NSLocalizedString(
                        "This is the amount of the maximum number of carbs we’ll assume will absorb over 4h if we don’t yet see carb absorption.",
                        comment: "Remaining Carbs Cap"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Noisy CGM Target Multiplier",
                    type: .decimal(keypath: \.noisyCGMTargetMultiplier),
                    infoText: NSLocalizedString(
                        "Defaults to 1.3. Increase target by this amount when looping off raw/noisy CGM data",
                        comment: "Noisy CGM Target Multiplier"
                    ),
                    settable: self
                )
            ]

            let autoISF = [
                Field(
                    displayName: "Enable AutoISF",
                    type: .boolean(keypath: \.autoisf),
                    infoText: NSLocalizedString(
                        "Defaults to false. Adapt ISF when glucose is stuck at high levels, only works without COB.\n\nRead up on:\nhttps://github.com/ga-zelle/autoISF/tree/2.8.2",
                        comment: "Enable AutoISF"
                    ),
                    settable: self
                )
            ]

            let autoISFsettings = [
                Field(
                    displayName: "Enable Floating Carbs",
                    type: .boolean(keypath: \.floatingcarbs),
                    infoText: NSLocalizedString(
                        "Defaults to false. If true, then dose slightly more aggressively by using all entered carbs for calculating COBpredBGs. This avoids backing off too quickly as COB decays. Even with this option, oref0 still switches gradually from using COBpredBGs to UAMpredBGs proportionally to how many carbs are left as COB. Summary: use all entered carbs in the future for predBGs & don't decay them as COB, only once they are actual.",
                        comment: "Floating Carbs"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Enable AutoISF with COB",
                    type: .boolean(keypath: \.enableautoISFwithCOB),
                    infoText: NSLocalizedString(
                        "Enables autoISF not just for UAM, but also with COB\n\nRead up on:\nhttps://github.com/ga-zelle/autoISF/tree/2.8.2_dev_parabola",
                        comment: "Enable autoISF with COB"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Enable BG acceleartion in AutoISF2.2",
                    type: .boolean(keypath: \.enableBGacceleration),
                    infoText: NSLocalizedString(
                        "Enables the BG acceleration adaptiions for autoISF\n\nRead up on:\nhttps://github.com/ga-zelle/autoISF/tree/2.8.2dev_ai2.2",
                        comment: "Enable BG accel in autoISF"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "AutoISF HourlyMaxChange",
                    type: .decimal(keypath: \.autoISFhourlyChange),
                    infoText: NSLocalizedString(
                        "Defaults to false. Rate at which autoISF grows per hour assuming bg is twice target. When value = 1.0, ISF is reduced to 50% after 1 hour of BG at 2x target.",
                        comment: "AutoISF HourlyMaxChange"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "AutoISF Max",
                    type: .decimal(keypath: \.autoISFmax),
                    infoText: NSLocalizedString(
                        "Multiplier cap on how high the autoISF ratio can be and therefore how low it can adjust ISF.",
                        comment: "AutoISF Max"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "SMB Max RangeExtension",
                    type: .decimal(keypath: \.smbMaxRangeExtension),
                    infoText: NSLocalizedString(
                        "Default value: 1. This is another key OpenAPS safety cap, and specifies by what factor you can exceed the regular 120 maxSMB/maxUAM minutes. Increase this experimental value slowly and with caution. Available only when autoISF is enabled.",
                        comment: "SMB Max RangeExtension"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "SMB DeliveryRatio BG Range",
                    type: .decimal(keypath: \.smbDeliveryRatioBGrange),
                    infoText: NSLocalizedString(
                        "Default value: 0, Sensible is bteween 40 and 120. The linearly increasing SMB delivery ratio is mapped to the glucose range [target_bg, target_bg+bg_range]. At target_bg the SMB ratio is smb_delivery_ratio_min, at target_bg+bg_range it is smb_delivery_ratio_max. With 0 the linearly increasing SMB ratio is disabled and the fix smb_delivery_ratio is used.",
                        comment: "SMB DeliveryRatio BG Range"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "SMB DeliveryRatio BG Minimum",
                    type: .decimal(keypath: \.smbDeliveryRatioMin),
                    infoText: NSLocalizedString(
                        "Default value: 0.5 This is the lower end of a linearly increasing SMB Delivery Ratio rather than the fix value above in SMB DeliveryRatio.",
                        comment: "SMB DeliveryRatio Minimum"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "SMB DeliveryRatio BG Maximum",
                    type: .decimal(keypath: \.smbDeliveryRatioMax),
                    infoText: NSLocalizedString(
                        "Default value: 0.5 This is the higher end of a linearly increasing SMB Delivery Ratio rather than the fix value above in SMB DeliveryRatio.",
                        comment: "SMB DeliveryRatio Minimum"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "ISF weight while BG accelerates",
                    type: .decimal(keypath: \.bgAccelISFweight),
                    infoText: NSLocalizedString(
                        "Default value: 0. This is the weight applied while glucose accelerates and which strengthens ISF. With 0 this contribution is effectively disabled. 0.15 might be a good starting point.",
                        comment: "ISF acceleration weight"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "ISF weight while BG decelerates",
                    type: .decimal(keypath: \.bgBrakeISFweight),
                    infoText: NSLocalizedString(
                        "Default value: 0. This is the weight applied while glucose decelerates and which weakens ISF. With 0 this contribution is effectively disabled. 0.15 might be a good starting point.",
                        comment: "ISF decceleration weight"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "AutoISF Min",
                    type: .decimal(keypath: \.autoISFmin),
                    infoText: NSLocalizedString(
                        "This is a multiplier cap for autoISF to set a limit on how low the autoISF ratio can be, which in turn determines how high it can adjust ISF.",
                        comment: "AutoISF Min"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "ISF weight for higher BG's",
                    type: .decimal(keypath: \.higherISFrangeWeight),
                    infoText: NSLocalizedString(
                        "Default value: 0.0 This is the weight applied to the polygon which adapts ISF if glucose is above target. With 0.0 the effect is effectively disabled.",
                        comment: "ISF high BG weight"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "ISF weight for lower BG's",
                    type: .decimal(keypath: \.lowerISFrangeWeight),
                    infoText: NSLocalizedString(
                        "Default value: 0.0 This is the weight applied to the polygon which adapts ISF if glucose is below target. With 0.0 the effect is effectively disabled.",
                        comment: "ISF low BG weight"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "ISF weight for higher BG deltas",
                    type: .decimal(keypath: \.deltaISFrangeWeight),
                    infoText: NSLocalizedString(
                        "Default value: 0.0 This is the weight applied to the polygon which adapts ISF higher deltas. With 0.0 the effect is effectively disabled.",
                        comment: "ISF higher delta BG weight"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Enable always postprandial ISF adaption",
                    type: .boolean(keypath: \.postMealISFalways),
                    infoText: NSLocalizedString(
                        "Enable the postprandial ISF adaptation all the time regardless of when the last meal was taken.",
                        comment: "Enable postprandial ISF always"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "ISF weight for postprandial BG rise",
                    type: .decimal(keypath: \.postMealISFweight),
                    infoText: NSLocalizedString(
                        "Default value: 0 This is the weight applied to the linear slope while glucose rises and  which adapts ISF. With 0 this contribution is effectively disabled.",
                        comment: "ISF postprandial weight"
                    ),
                    settable: self
                ),
                Field(
                    displayName: "Duration ISF postprandial adaption",
                    type: .decimal(keypath: \.postMealISFduration),
                    infoText: NSLocalizedString(
                        "Default value: 3 This is the duration in hours how long after a meal the effect will be active. Oref will delete carb timing after 10 hours latest no matter what you enter.",
                        comment: "ISF postprandial change duration"
                    ),
                    settable: self
                )
            ]

            sections = [
                FieldSection(
                    displayName: NSLocalizedString("OpenAPS main settings", comment: "OpenAPS main settings"), fields: mainFields
                ),
                FieldSection(
                    displayName: NSLocalizedString("Dynamic settings", comment: "Dynamic settings"),
                    fields: dynamicISF
                ),
                FieldSection(
                    displayName: NSLocalizedString("OpenAPS SMB settings", comment: "OpenAPS SMB settings"), fields: smbFields
                ),
                FieldSection(
                    displayName: NSLocalizedString("OpenAPS targets settings", comment: "OpenAPS targets settings"),
                    fields: targetSettings
                ),
                FieldSection(
                    displayName: NSLocalizedString("OpenAPS other settings", comment: "OpenAPS other settings"),
                    fields: otherSettings
                ),
                FieldSection(
                    displayName: NSLocalizedString("Use Auto ISF", comment: "Switch on/off experimental stuff"),
                    fields: autoISF
                ),
                FieldSection(
                    displayName: NSLocalizedString(
                        "Auto ISF Settings. Forget about these if Auto ISF is toggled off",
                        comment: "AutoISF Settings"
                    ),
                    fields: autoISFsettings
                )
            ]
        }

        func set<T>(_ keypath: WritableKeyPath<Preferences, T>, value: T) {
            preferences[keyPath: keypath] = value
            save()
        }

        func get<T>(_ keypath: WritableKeyPath<Preferences, T>) -> T {
            preferences[keyPath: keypath]
        }

        func save() {
            provider.savePreferences(preferences)
        }
    }
}
