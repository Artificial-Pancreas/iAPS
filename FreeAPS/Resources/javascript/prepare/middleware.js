/*
*   {
*     middleware_fn: String,
*     glucose: [GlucoseEntry0],
*     current_temp: TempBasal,
*     iob: [IOBEntry],
*     profile: Profile,
*     autosens: Autosens?,
*     meal: RecentCarbs,
*     microbolus_allowed: Bool,
*     reservoir: Double,
*     clock: Date
*
*     middleware_fn - a reference to the user function
*   }
* */
module.exports = (iaps_input) => {
    var clock = new Date(Date.parse(iaps_input.clock));
    var string = "";
    let profile = iaps_input.profile

    profile.old_basal = profile.current_basal;

    const factor = profile.dynamicVariables.overridePercentage / 100;
    if (factor != 1 && profile.dynamicVariables.useOverride && profile.dynamicVariables.basal) {
        profile.current_basal *= factor;
        console.error("Override profile.current_basal to " + profile.current_basal);
    }

    try {
        eval(iaps_input.middleware_fn);
        // the above eval should definde the middleware function
        string = middleware(
          iaps_input.iob,
          iaps_input.current_temp,
          iaps_input.glucose,
          profile,
          iaps_input.autosens,
          iaps_input.meal,
          iaps_input.reservoir,
          clock
        ) ?? ''

    } catch (error) {
        console.log("Invalid middleware: " + error);
        string = String(error);
    }

    profile.old_cr = profile.carb_ratio;

    if (profile.dynamicVariables.useNewFormula && profile.temptargetSet && (profile.high_temptarget_raises_sensitivity || profile.exercise_mode || profile.dynamicVariables.isEnabled) && profile.min_bg >= 118) {
            profile.useNewFormula = false;
            console.log("Dynamic ISF disabled due to an active exercise ");
    }

    if (typeof string == 'string' && string !== "") {
        profile.mw = string;
        console.log("Middleware reason: " + string);
    }

    return profile;
}
