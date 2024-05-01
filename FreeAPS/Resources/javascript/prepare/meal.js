//для monitor/meal.json параметры: monitor/pumphistory-24h-zoned.json settings/profile.json monitor/clock-zoned.json monitor/glucose.json settings/basal_profile.json monitor/carbhistory.json

function generate(pumphistory_data, profile_data, clock_data, glucose_data, basalprofile_data, carbhistory = false) {
    if (typeof(profile_data.carb_ratio) === 'undefined' || profile_data.carb_ratio < 0.1) {
        return {"error":"Error: carb_ratio " + profile_data.carb_ratio + " out of bounds"};
    }

    var carb_data = {};
    if (carbhistory) {
        carb_data = carbhistory;
        
        /* A tempory fix to make all iAPS carb equivalents compatible with the Oref0 meal module.
         Unfortunately the Oref0 slows down when there are several carb entries and gets super slow when there are many (like when lots of FPUs). Hence this fix will slow down this module even more */
        carb_data.forEach( carb => carb.created_at = carb.actualDate ? carb.actualDate : carb.created_at);
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

    var recentCarbs = freeaps_meal(inputs);

    if (glucose_data.length < 4) {
        console.error("Not enough glucose data to calculate carb absorption; found:", glucose_data.length);
        recentCarbs.mealCOB = 0;
        recentCarbs.reason = "not enough glucose data to calculate carb absorption";
    }

    return recentCarbs;
}
