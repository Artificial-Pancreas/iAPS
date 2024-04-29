
function generate(iob, currenttemp, glucose, profile, autosens = null, meal = null, microbolusAllowed = false, reservoir = null, clock = new Date(), oref2_variables) {
    var clock = new Date();
    var string = "";
    
    try {
        string = middleware(iob, currenttemp, glucose, profile, autosens, meal, reservoir, clock, oref2_variables) || "";
        
        if (profile && string != "") {
            profile.mw = string
        }
        return profile;
    } catch (error) {
        console.log("Invalid middleware: " + error);
    };
    
    return profile;
}
