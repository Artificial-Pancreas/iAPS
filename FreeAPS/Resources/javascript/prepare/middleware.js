
function generate(iob, currenttemp, glucose, profile, autosens = null, meal = null, microbolusAllowed = false, reservoir = null, clock = new Date(), dynamicVariables) {
    var clock = new Date();
    var string = "";
    
    try {
        string = middleware(iob, currenttemp, glucose, profile, autosens, meal, reservoir, clock, dynamicVariables) || "";
    } catch (error) {
        console.log("Invalid middleware: " + error);
        string = String(error);
    };
        
    if (profile.tddAdjBasal && dynamicVariables.average_total_data != 0) {
        profile.tdd_factor = Math.round((dynamicVariables.weightedAverage / dynamicVariables.average_total_data) * 100) / 100;
    }
                                         
    if (profile.useNewFormula && profile.temptargetSet && (profile.high_temptarget_raises_sensitivity || profile.exercise_mode || dynamicVariables.isEnabled) && profile.min_bg >= 118) {
            profile.useNewFormula = false;
            console.log("Dynamic ISF disabled due to an active exercise ");
    }
                                         
    if (profile && string != "") {
        profile.mw = string;
        console.log("Middleware reason: " + string);
    }
        
    return profile;
}
