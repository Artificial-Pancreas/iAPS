//для monitor/iob.json параметры: monitor/pumphistory-24h-zoned.json settings/profile.json monitor/clock-zoned.json settings/autosens.json

function generate(pumphistory_data, profile_data, clock_data, autosens_data = null) {
    var inputs = {
        history: pumphistory_data
        , history24: null
        , profile: profile_data
        , clock: clock_data
    };

      if (autosens_data) {
        inputs.autosens = autosens_data;
      }
    
    // Adjust for eventual Overrides
    const dynamicVariables = profile_data.dynamicVariables || { } ;
        
    if (dynamicVariables.useOverride) {
        if (dynamicVariables.useOverride && dynamicVariables.overridePercentage != 100 && dynamicVariables.basal) {
            profile_data.basalprofile.forEach( basal => basal.rate *= (dynamicVariables.overridePercentage / 100));
        }
    }
    
    return freeaps_iob(inputs);
}
