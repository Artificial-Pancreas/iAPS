
function generate(iob, currenttemp, glucose, profile, autosens = null, meal = null, microbolusAllowed = false, reservoir = null, clock = new Date(), dynamicVariables) {
    var clock = new Date();
    var string = "";
    
    try {
        string = middleware(iob, currenttemp, glucose, profile, autosens, meal, reservoir, clock, dynamicVariables) || "";
        
        if (profile && string != "") {
            profile.mw = string
        }
        
        if (profile.tddAdjBasal && dynamicVariables.average_total_data != 0) {
            profile.tdd_factor = Math.round((dynamicVariables.weightedAverage / dynamicVariables.average_total_data) * 100) / 100;
        }
        
        return profile;
    } catch (error) {
        console.log("Invalid middleware: " + error);
    };
    
    return profile;
}
