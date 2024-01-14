// FOR: enact/smb-suggested.json
// PARAMETERS: monitor/iob.json monitor/temp_basal.json monitor/glucose.json settings/profile.json settings/autosens.json --meal monitor/meal.json --microbolus --reservoir monitor/reservoir.json

function generate(iob, currenttemp, glucose, profile, autosens = null, meal = null, microbolusAllowed = false, reservoir = null, clock = new Date(), pump_history, preferences, basalProfile, oref2_variables) {
    
    let middleware_was_used = "";

    try {
        const middlewareReason = middleware(iob, currenttemp, glucose, profile, autosens, meal, reservoir, clock, pump_history, preferences, basalProfile, oref2_variables);
        middleware_was_used = middlewareReason || "Nothing changed";
        console.log("Middleware reason: " + middleware_was_used);
    } catch (error) {
        console.error("Invalid middleware: " + error);
    }

    const glucose_status = freeaps_glucoseGetLast(glucose);

    return freeaps_determineBasal(glucose_status, currenttemp, iob, profile, autosens, meal || {}, freeaps_basalSetTemp, microbolusAllowed, reservoir, clock, pump_history || {}, preferences, basalProfile || {}, oref2_variables || {}, middleware_was_used);
}
