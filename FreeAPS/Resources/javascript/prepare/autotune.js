// from OREF0_DIST_PATH
const oref0_autotunePrep = require('oref0/autotune-prep/index.js')
const oref0_autotuneCore = require('oref0/autotune/index.js')

/*
* Full autotune - calls prep and then core
*   {
*     pump_history: [PumpHistoryEvent],
*     profile: Profile,
*     glucose: [GlucoseEntry0],
*     pump_profile: Profile,
*     carbs: [CarbsEntry],
*     categorize_uam_as_basal: Bool,
*     tune_insulin_curve: Bool,
*     previous_autotune_result: Profile,
*   }
* */
module.exports = (iaps_input) => {
  const prepped = autotune_prep(
    iaps_input.pump_history,
    iaps_input.profile,
    iaps_input.glucose,
    iaps_input.pump_profile,
    iaps_input.carbs,
    iaps_input.categorize_uam_as_basal,
    iaps_input.tune_insulin_curve
  )
  return autotune_core(
    prepped,
    iaps_input.previous_autotune_result,
    iaps_input.pump_profile
  )
}

function autotune_prep(pumphistory_data, profile_data, glucose_data, pumpprofile_data, carb_data, categorize_uam_as_basal, tune_insulin_curve) {
  if (typeof(profile_data.carb_ratio) === 'undefined' || profile_data.carb_ratio < 0.1) {
    if (typeof(pumpprofile_data.carb_ratio) === 'undefined' || pumpprofile_data.carb_ratio < 0.1) {
      console.log('{ "carbs": 0, "mealCOB": 0, "reason": "carb_ratios ' + profile_data.carb_ratio + ' and ' + pumpprofile_data.carb_ratio + ' out of bounds" }');
      return console.error("Error: carb_ratios " + profile_data.carb_ratio + ' and ' + pumpprofile_data.carb_ratio + " out of bounds");
    } else {
      profile_data.carb_ratio = pumpprofile_data.carb_ratio;
    }
  }

  // get insulin curve from pump profile that is maintained
  profile_data.curve = pumpprofile_data.curve;

  // Pump profile has an up to date copy of useCustomPeakTime from preferences
  // If the preferences file has useCustomPeakTime use the previous autotune dia and PeakTime.
  // Otherwise, use data from pump profile.
  if (!pumpprofile_data.useCustomPeakTime) {
    profile_data.dia = pumpprofile_data.dia;
    profile_data.insulinPeakTime = pumpprofile_data.insulinPeakTime;
  }

  // Always keep the curve value up to date with what's in the user preferences
  profile_data.curve = pumpprofile_data.curve;

  // Have to sort history - NS sort doesn't account for different zulu and local timestamps
  pumphistory_data.sort( function( firstValue, secondValue ) {
    try {
      var a = new Date(firstValue.timestamp);
      var b = new Date(secondValue.timestamp);
      return b.getTime() - a.getTime();
    } catch(e) {
      return 0;
    }
  } );

  /* A temporary fix to make all iAPS carb equivalents compatible with the Oref0 meal module. */
  carb_data.forEach( carb => carb.created_at = carb.actualDate ? carb.actualDate : carb.created_at);
  carb_data.forEach( carb => console.log("Carb entry " + carb.created_at + ", carbs: " + carb.carbs + ", entered by: " + carb.enteredBy ));
  carb_data = carb_data.filter((carb) => carb.carbs >= 1);
  carb_data.sort((a, b) => b.created_at - a.created_at);

  /* oref0 autotune-prep module expects the timestamp to be in the created_at field */
  pumphistory_data.forEach( entry => entry.created_at = entry.timestamp );

  inputs = {
    history: pumphistory_data
    , profile: profile_data
    , pumpprofile: pumpprofile_data
    , carbs: carb_data
    , glucose: glucose_data
    , categorize_uam_as_basal: categorize_uam_as_basal
    , tune_insulin_curve: tune_insulin_curve
  };

  return oref0_autotunePrep(inputs);
}

function autotune_core(prepped_glucose_data,previous_autotune_data,pumpprofile_data) {
  if (!pumpprofile_data.useCustomPeakTime) {
    previous_autotune_data.dia = pumpprofile_data.dia;
    previous_autotune_data.insulinPeakTime = pumpprofile_data.insulinPeakTime;
  };

  // Always keep the curve value up to date with what's in the user preferences
  previous_autotune_data.curve = pumpprofile_data.curve;

  inputs = {
    preppedGlucose: prepped_glucose_data
    , previousAutotune: previous_autotune_data
    , pumpProfile: pumpprofile_data
  };

  return oref0_autotuneCore(inputs);
}
