//для pumpprofile.json параметры: settings/settings.json settings/bg_targets.json settings/insulin_sensitivities.json settings/basal_profile.json preferences.json settings/carb_ratios.json settings/temptargets.json settings/model.json
//для profile.json параметры: settings/settings.json settings/bg_targets.json settings/insulin_sensitivities.json settings/basal_profile.json preferences.json settings/carb_ratios.json settings/temptargets.json settings/model.json settings/autotune.json

function generate(pumpsettings_data, bgtargets_data, isf_data, basalprofile_data, preferences_input = false, carbratio_input = false, temptargets_input = false, model_input = false, autotune_input = false, freeaps_data, dynamicVariables, settings_input) {
    if (bgtargets_data.units !== 'mg/dL') {
        if (bgtargets_data.units === 'mmol/L') {
            for (var i = 0, len = bgtargets_data.targets.length; i < len; i++) {
                bgtargets_data.targets[i].high = bgtargets_data.targets[i].high * 18;
                bgtargets_data.targets[i].low = bgtargets_data.targets[i].low * 18;
            }
            bgtargets_data.units = 'mg/dL';
        } else {
            return { "error" : 'BG Target data is expected to be expressed in mg/dL or mmol/L. Found '+ bgtargets_data.units };
        }
    }
    
    if (isf_data.units !== 'mg/dL') {
        if (isf_data.units === 'mmol/L') {
            for (var i = 0, len = isf_data.sensitivities.length; i < len; i++) {
                isf_data.sensitivities[i].sensitivity = isf_data.sensitivities[i].sensitivity * 18;
            }
            isf_data.units = 'mg/dL';
        } else {
            return { "error" : 'ISF is expected to be expressed in mg/dL or mmol/L. Found '+ isf_data.units };
        }
    }

    var autotune_data = { };
    if (autotune_input) {
        autotune_data = autotune_input;
    }

    var temptargets_data = { };
    if (temptargets_input) {
        temptargets_data = temptargets_input;
    }
    
    var freeaps = { };
    if (freeaps_data) {
        freeaps = freeaps_data;
    }

    var model_data = { };
    if (model_input) {
        model_data = model_input.replace(/"/gi, '');
    }

    var carbratio_data = { };
    if (carbratio_input) {
        var errors = [ ];
        if (!(carbratio_input.schedule && carbratio_input.schedule[0].start && carbratio_input.schedule[0].ratio)) {
          errors.push("Carb ratio data should have an array called schedule with a start and ratio fields.");
        }
        if (carbratio_input.units !== 'grams' && carbratio_input.units !== 'exchanges')  {
          errors.push("Carb ratio should have units field set to 'grams' or 'exchanges'.");
        }
        if (errors.length) {
          return { "error" : errors.join(' ') };
        }
        carbratio_data = carbratio_input;
    }

    var preferences = { };
    if (preferences_input) {
        preferences = preferences_input;
        if (preferences.curve === "rapid-acting") {
            if (preferences.useCustomPeakTime) {
                preferences.insulinPeakTime =
                Math.max(50, Math.min(preferences.insulinPeakTime, 120));
            } else { preferences.insulinPeakTime = 75; }
        } 
        else if (preferences.curve === "ultra-rapid") {
            if (preferences.useCustomPeakTime) {
                preferences.insulinPeakTime =
                Math.max(35, Math.min(preferences.insulinPeakTime, 100));
            } else { preferences.insulinPeakTime = 55; }
        }
    }
    
    var iaps = { };
    if (settings_input) {
        iaps = settings_input;
    }
    
    var tdd_factor = { };
    var set_basal = false;
    var basal_rate = { };
    var old_isf = { };
    var aisf = { };
    var old_cr = { };
    var microbolusAllowed = { };
    
    var inputs = { };
    //add all preferences to the inputs
    for (var pref in preferences) {
      if (preferences.hasOwnProperty(pref)) {
        inputs[pref] = preferences[pref];
      }
    }
    
    inputs.max_iob = inputs.max_iob || 0;
    //set these after to make sure nothing happens if they are also set in preferences
    inputs.settings = pumpsettings_data;
    inputs.targets = bgtargets_data;
    
    if (dynamicVariables.useOverride && dynamicVariables.overridePercentage != 100) {
        basalprofile_data.forEach( basal => basal.rate *= (dynamicVariables.overridePercentage / 100));
        console.log("Override basal IOB");
    }
    
    inputs.basals = basalprofile_data;
    inputs.isf = isf_data;
    inputs.carbratio = carbratio_data;
    inputs.temptargets = temptargets_data;
    inputs.model = model_data;
    inputs.autotune = autotune_data;
    inputs.tddFactor = tdd_factor;
    inputs.set_basal = set_basal;
    inputs.basal_rate = basal_rate;
    inputs.old_isf = old_isf;
    inputs.old_cr = old_cr;
    inputs.iaps = iaps;
    inputs.aisf = aisf;
    inputs.microbolusAllowed = microbolusAllowed;
    
    if (autotune_data) {
        if (autotune_data.basalprofile) { inputs.basals = autotune_data.basalprofile; }
        if (!freeaps.onlyAutotuneBasals) {
            if (autotune_data.isfProfile) { inputs.isf = autotune_data.isfProfile; }
            if (autotune_data.carb_ratio) { inputs.carbratio.schedule[0].ratio = autotune_data.carb_ratio; }
        }
    }

    // merge oref0 defaults with iAPS ones
    const defaults = Object.assign(
        {},
        freeaps_profile.defaults(),
        {
            type: 'iAPS', // attribute to override defaults
            // +++++ iAPS settings
            // smb_delivery_ratio: included in the current oref0 PR (https://github.com/openaps/oref0/pull/1465/files)
            smb_delivery_ratio: 0.5,
            adjustmentFactor: 1,
            useNewFormula: false,
            enableDynamicCR: false,
            sigmoid: false,
            weightPercentage: 0.65,
            // threshold_setting: temporary fix to test thomasvargiu/iAPS#original-oref0 branch before build.
            // We can remove it after merged and after build the new original bundles
            // because it's included in the current oref0 PR (https://github.com/openaps/oref0/pull/1465/files)
            // currently (2024-08-09) this settings probably doesn't work in the current iAPS main/dev branch
            threshold_setting: 60,
            iaps: false
        }
    )

    var logs = { err: '', stdout: '', return_val: 0 };
    var profile = freeaps_profile(logs, inputs, defaults);
    if (logs.err.length > 0) {
        console.error(logs.err);
    }
    if (logs.stdout.length > 0) {
        console.error(logs.stdout);
    }

    if (typeof profile !== 'object') {
        return;
    }

    return profile;
}
