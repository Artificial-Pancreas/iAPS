function exportDefaults () {
    return freeaps.displayedDefaults();
}

function generate(preferences, pumpsettings_data, bgtargets_data, basalprofile_data, isf_data, carbratio_data, temptargets_data, model_data, autotune_data) {
    var inputs = { };
        //add all preferences to the inputs
        for (var pref in preferences) {
          if (preferences.hasOwnProperty(pref)) {
            inputs[pref] = preferences[pref];
          }
        }

        //make sure max_iob is set or default to 0
        inputs.max_iob = inputs.max_iob || 0;

        //set these after to make sure nothing happens if they are also set in preferences
        inputs.settings = pumpsettings_data;
        inputs.targets = bgtargets_data;
        inputs.basals = basalprofile_data;
        inputs.isf = isf_data;
        inputs.carbratio = carbratio_data;
        inputs.temptargets = temptargets_data;
        inputs.model = model_data;
        inputs.autotune = autotune_data;

        if (autotune_data) {
            if (autotune_data.basalprofile) { inputs.basals = autotune_data.basalprofile; }
            if (autotune_data.isfProfile) { inputs.isf = autotune_data.isfProfile; }
            if (autotune_data.carb_ratio) { inputs.carbratio.schedule[0].ratio = autotune_data.carb_ratio; }
        }

        return freeaps(inputs);
}
