function generate(pumphistory_data, profile_data, basalprofile_data, clock_data, carb_data, glucose_data) {
    var inputs = {
        history: pumphistory_data,
        profile: profile_data,
        basalprofile: basalprofile_data,
        clock: clock_data,
        carbs: carb_data,
        glucose: glucose_data
    };

    var recentCarbs = freeaps(inputs);

    if (glucose_data.length < 36) {
        console.error("Not enough glucose data to calculate carb absorption; found:", glucose_data.length);
        recentCarbs.mealCOB = 0;
        recentCarbs.reason = "not enough glucose data to calculate carb absorption";
    }

    return recentCarbs;
}
