
function generate(iob, currenttemp, glucose, profile, autosens = null, meal = null, microbolusAllowed = false, reservoir = null, clock = new Date(), dynamicVariables) {
    var clock = new Date();
    var string = "";
    
    try {
        string = middleware(iob, currenttemp, glucose, profile, autosens, meal, reservoir, clock, dynamicVariables) || "";
        
        if (profile && string != "") {
            profile.mw = string
        }
        return profile;
    } catch (error) {
        console.log("Invalid middleware: " + error);
    };
    
    return profile;
}
