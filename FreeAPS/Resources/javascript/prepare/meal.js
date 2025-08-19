// from OREF0_DIST_PATH
const oref0_meal = require('oref0/meal/index.js')

/*
*   {
*     pump_history: [PumpHistoryEvent],
*     profile: Profile,
*     basal_profile: [BasalProfileEntry],
*     clock: Date,
*     carbs: [CarbsEntry],
*     glucose: [GlucoseEntry0],
*     for_bolus_view: CarbsEntry*
*   }
* */
module.exports = (iaps_input) => {
    const pumphistory_data = iaps_input.pump_history
    const profile_data = iaps_input.profile
    const clock_data = new Date(Date.parse(iaps_input.clock))
    const glucose_data = iaps_input.glucose
    const basalprofile_data = iaps_input.basal_profile
    const carbhistory = iaps_input.carbs
    const bolus_data = iaps_input.for_bolus_view

    if (typeof(profile_data.carb_ratio) === 'undefined' || profile_data.carb_ratio < 0.1) {
        return {"error":"Error: carb_ratio " + profile_data.carb_ratio + " out of bounds"};
    }

    var carb_data = {};
    if (carbhistory) {
        /* Debug option to neglect all carbs */
        if (!profile_data.iaps.noCarbs) {
            carb_data = carbhistory;
            // Eventual Temporary data used only in bolus View
            if (bolus_data && bolus_data.carbs > 0) {
                console.log("Carb entries: " + carb_data.unshift(bolus_data));
            }
            /* A fix to make all iAPS carb equivalents compatible with the Oref0 meal module. */
            carb_data.forEach( carb => carb.created_at = carb.actualDate ? carb.actualDate : carb.created_at);
            carb_data.forEach( carb => console.log("Carb entry " + carb.created_at + ", carbs: " + carb.carbs + ", entered by: " + carb.enteredBy ));
            carb_data = carb_data.filter((carb) => carb.carbs >= 1);
            carb_data.sort((a, b) => b.created_at - a.created_at);
        }
    }

    if (typeof basalprofile_data[0] === 'undefined') {
        return { "error":"Error: bad basalprofile_data: " + JSON.stringify(basalprofile_data) };
    }

    var inputs = {
      history: pumphistory_data
    , profile: profile_data
    , basalprofile: basalprofile_data
    , clock: clock_data
    , carbs: carb_data
    , glucose: glucose_data
    };

    var recentCarbs = oref0_meal(inputs);

    if (glucose_data.length < 4) {
        console.error("Not enough glucose data to calculate carb absorption; found:", glucose_data.length);
        recentCarbs.mealCOB = 0;
        recentCarbs.reason = "not enough glucose data to calculate carb absorption";
    }

    return recentCarbs;
}
