// from OREF0_DIST_PATH
const oref0_autosens = require('oref0/determine-basal/autosens.js')

/*
*   {
*     glucose: [GlucoseEntry0],
*     pump_history: [PumpHistoryEvent],
*     basal_profile: [BasalProfileEntry],
*     profile: Profile,
*     carbs: [CarbsEntry],
*     temp_targets: [TempTarget]
*   }
* */
module.exports = (iaps_input) => {
  if (iaps_input.glucose.length < 72) {
    return { "ratio": 1, "error": "not enough glucose data to calculate autosens" };
  }

  const detection_inputs = {
    iob_inputs: {
      history: iaps_input.pump_history,
      profile: iaps_input.profile
    },
    carbs: iaps_input.carbs,
    glucose_data: iaps_input.glucose,
    basalprofile: iaps_input.basal_profile,
    temptargets: iaps_input.temp_targets
  }

  detection_inputs.deviations = 96
  const ratio8h = oref0_autosens(detection_inputs)
  detection_inputs.deviations = 288
  const ratio24h = oref0_autosens(detection_inputs)
  const lowestRatio = ratio8h.ratio < ratio24h.ratio ? ratio8h : ratio24h


  return lowestRatio;
}
