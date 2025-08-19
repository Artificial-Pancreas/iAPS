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
module.exports = ({ glucose, pump_history, basal_profile, profile, carbs, temp_targets }) => {
    if (glucose.length < 72) {
      return { "ratio": 1, "error": "not enough glucose data to calculate autosens" };
    }
    const iob_inputs = {
      history: pump_history,
      profile
    };

    var detection_inputs = {
      iob_inputs,
      carbs,
      glucose_data: glucose,
      basalprofile: basal_profile,
      temptargets: temp_targets
    }

    detection_inputs.deviations = 96
    var ratio8h = oref0_autosens(detection_inputs)
    detection_inputs.deviations = 288
    var ratio24h = oref0_autosens(detection_inputs)

    return ratio8h.ratio < ratio24h.ratio ? ratio8h : ratio24h
}
