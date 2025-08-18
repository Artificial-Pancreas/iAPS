// from OREF0_DIST_PATH
const oref0_determineBasal = require('oref0/determine-basal/determine-basal.js')
const oref0_basalFunctions = require('oref0/basal-set-temp.js')
const oref0_glucoseGetLast = require('oref0/glucose-get-last.js')

const round = require('./utils').round
const disableSMBs = require('./utils').disableSMBs

/*
*   {
*     glucose: [GlucoseEntry0],
*     current_temp: TempBasal,
*     iob: [IOBItem],
*     profile: Profile,
*     autosens: Autosens?,
*     meal: RecentCarbs,
*     microbolus_allowed: Bool,
*     reservoir: Double,
*     pump_history: [PumpHistoryEvent], // TODO pump_history not used
*     clock: Date
*   }
* */
module.exports = (iaps_input) => {
  const iob = iaps_input.iob
  const currenttemp = iaps_input.current_temp
  const glucose = iaps_input.glucose
  const profile = iaps_input.profile
  const autosens_data = iaps_input.autosens ?? null
  const meal_data = iaps_input.meal
  let microbolusAllowed = iaps_input.microbolus_allowed
  const reservoir_data = iaps_input.reservoir
  // const pumpHistory = iaps_input.pump_history

  const clock = new Date(Date.parse(iaps_input.clock));

  const dynamicVariables = profile.dynamicVariables ?? { };

  // Overrides
  if (dynamicVariables.useOverride) {
    const factor = dynamicVariables.overridePercentage / 100;
    if (factor != 1) {
      // Basal has already been adjusted in prepare/profile.js
      console.log("Override active (" + factor + "), basal: (" + profile.current_basal + ")")
      // ISF and CR
      if (dynamicVariables.isfAndCr) {
        profile.sens /= factor;
        profile.carb_ratio =  round(profile.carb_ratio / factor, 1);
        console.log("Override Active, " + dynamicVariables.overridePercentage + "%");
      } else {
        if (dynamicVariables.cr) {
          profile.carb_ratio =  round(profile.carb_ratio / factor, 1);
          console.log("Override Active, CR: " + profile.old_cr + " → " + profile.carb_ratio);
        }
        if (dynamicVariables.isf) {
          profile.sens /= factor;
          if (profile.out_units == 'mmol/L') {
            console.log("Override Active, ISF: " + profile.old_isf + " → " + Math.round(profile.sens * 0.0555 * 10) / 10);
          } else {
            console.log("Override Active, ISF: " + profile.old_isf + " → " + profile.sens);
          }
        }
      }
    }
    // SMB Minutes
    if (dynamicVariables.advancedSettings && dynamicVariables.smbMinutes !== profile.maxSMBBasalMinutes) {
      console.log("SMB Max Minutes - setting overriden from " + profile.maxSMBBasalMinutes + " to " + dynamicVariables.smbMinutes);
      profile.maxSMBBasalMinutes = dynamicVariables.smbMinutes;
    }
    // UAM Minutes
    if (dynamicVariables.advancedSettings && dynamicVariables.uamMinutes !== profile.maxUAMSMBBasalMinutes) {
      console.log("UAM Max Minutes - setting overriden from " + profile.maxUAMSMBBasalMinutes + " to " + dynamicVariables.uamMinutes);
      profile.maxUAMSMBBasalMinutes = dynamicVariables.uamMinutes;
    }
    //Target
    if (dynamicVariables.overrideTarget != 0 && dynamicVariables.overrideTarget != 6 && !profile.temptargetSet) {
      profile.min_bg = dynamicVariables.overrideTarget;
      profile.max_bg = profile.min_bg;
      console.log("Override Active, new glucose target: " + dynamicVariables.overrideTarget);
    }

    //SMBs
    if (disableSMBs(dynamicVariables, clock)) {
      microbolusAllowed = false;
      console.error("SMBs disabled by Override");
    }

    // Max IOB
    if (dynamicVariables.advancedSettings && dynamicVariables.overrideMaxIOB) {
      profile.max_iob = dynamicVariables.maxIOB;
      console.log("Override Active, new maxIOB: " + profile.max_iob);
    }
  }

  // Half Basal Target
  if (dynamicVariables.isEnabled) {
    profile.half_basal_exercise_target = dynamicVariables.hbt;
    console.log("Temp Target active, half_basal_exercise_target: " + dynamicVariables.hbt);
  }

  // Dynamic ISF
  if (profile.useNewFormula) {
    dynisf(profile, autosens_data, dynamicVariables, glucose);
  }

  var glucose_status = oref0_glucoseGetLast(glucose)

  // Auto ISF
  if (profile.iaps.autoisf) {
    autosens_data.ratio = profile.aisf;
    console.log("Auto ISF ratio: " + autosens_data.ratio);
    if (microbolusAllowed && !profile.microbolusAllowed) {
      microbolusAllowed = false;
      console.log("SMBs disabled by Auto ISF layer");
    }
  }

  // In case Basal Rate been set in middleware or B30
  if (profile.set_basal && profile.basal_rate) {
    console.log("Basal Rate set by middleware or B30 to " + profile.basal_rate + " U/h.");
  }

  /* For testing, replace with:
  return test(glucose_status, currenttemp, iob, profile, autosens_data, meal_data, freeaps_basalSetTemp, microbolusAllowed, reservoir_data, clock); */

  return oref0_determineBasal(glucose_status, currenttemp, iob, profile, autosens_data, meal_data, oref0_basalFunctions, microbolusAllowed, reservoir_data, clock);
}
