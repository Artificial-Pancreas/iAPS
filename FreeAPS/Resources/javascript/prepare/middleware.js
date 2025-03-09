
function generate(iob, currenttemp, glucose, profile, autosens = null, meal = null, microbolusAllowed = false, reservoir = null, clock = new Date()) {
    var clock = new Date();
    var string = "";
    
    try {
        string = middleware(iob, currenttemp, glucose, profile, autosens, meal, reservoir, clock) || "";
    } catch (error) {
        console.log("Invalid middleware: " + error);
        string = String(error);
    };
                                          
    profile.old_cr = profile.carb_ratio;
    
    if (profile.dynamicVariables.useNewFormula && profile.temptargetSet && (profile.high_temptarget_raises_sensitivity || profile.exercise_mode || profile.dynamicVariables.isEnabled) && profile.min_bg >= 118) {
            profile.useNewFormula = false;
            console.log("Dynamic ISF disabled due to an active exercise ");
    }
                                         
    if (profile && string != "") {
        profile.mw = string;
        console.log("Middleware reason: " + string);
    }
        
    return profile;
}
