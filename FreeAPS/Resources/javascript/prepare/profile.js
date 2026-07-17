// from OREF0_DIST_PATH
const oref0_profile = require('oref0/profile/index.js')

/*
*   {
*     preferences: Preferences
*     pump_settings: PumpSettings
*     bg_targets: BGTargets
*     basal_profile: [BasalProfileEntry]
*     isf: InsulinSensitivities
*     carb_ratio: CarbRatios
*     temp_targets: [TempTarget]
*     model: String
*     autotune: Autotune?
*     freeaps: FreeAPSSettings
*     dynamic_variables: DynamicVariables
*     settings: FreeAPSSettings
*     clock: Date
*   }
* */
module.exports = (iaps_input) => {

    const pumpsettings_data = iaps_input.pump_settings
    const bgtargets_data = iaps_input.bg_targets
    const isf_data = iaps_input.isf
    const basalprofile_data = iaps_input.basal_profile
    const preferences_input = iaps_input.preferences
    const carbratio_input = iaps_input.carb_ratio
    const temptargets_input = iaps_input.temp_targets
    const model_input = iaps_input.model
    const autotune_input  = iaps_input.autotune
    const freeaps_data = iaps_input.freeaps
    const dynamicVariables_input = iaps_input.dynamic_variables
    const settings_input = iaps_input.settings
    const clock = new Date(Date.parse(iaps_input.clock))

    if (bgtargets_data.units !== 'mg/dL') {
        if (bgtargets_data.units === 'mmol/L') {
            for (let i = 0, len = bgtargets_data.targets.length; i < len; i++) {
                bgtargets_data.targets[i].high = bgtargets_data.targets[i].high * 18;
                bgtargets_data.targets[i].low = bgtargets_data.targets[i].low * 18;
            }
            bgtargets_data.units = 'mg/dL';
        } else {
            throw new Error('BG Target data is expected to be expressed in mg/dL or mmol/L. Found '+ bgtargets_data.units);
        }
    }

    if (isf_data.units !== 'mg/dL') {
        if (isf_data.units === 'mmol/L') {
            for (var i = 0, len = isf_data.sensitivities.length; i < len; i++) {
                isf_data.sensitivities[i].sensitivity = isf_data.sensitivities[i].sensitivity * 18;
            }
            isf_data.units = 'mg/dL';
        } else {
            throw new Error('ISF is expected to be expressed in mg/dL or mmol/L. Found '+ isf_data.units);
        }
    }

    let autotune_data = autotune_input ?? {};

    let temptargets_data = temptargets_input ?? {};

    let freeaps = freeaps_data ?? {};

    let model_data = model_input?.replace(/"/gi, '') ?? null;

    let carbratio_data = { };
    if (carbratio_input) {
        let errors = [ ];
        if (!(carbratio_input.schedule && carbratio_input.schedule[0].start && carbratio_input.schedule[0].ratio)) {
          errors.push("Carb ratio data should have an array called schedule with a start and ratio fields.");
        }
        if (carbratio_input.units !== 'grams' && carbratio_input.units !== 'exchanges')  {
          errors.push("Carb ratio should have units field set to 'grams' or 'exchanges'.");
        }
        if (errors.length) {
          throw new Error(errors.join(' '));
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

    const iaps = settings_input ?? {};

    const dynamicVariables = dynamicVariables_input ?? {};

    let tdd_factor = { };
    let set_basal = false;
    let basal_rate = { };
    let old_isf = { };
    let aisf = { };
    let old_cr = { };
    let old_basal = { };
    let microbolusAllowed = { };

    let inputs = { };
    //add all preferences to the inputs
    for (const pref in preferences) {
      if (preferences.hasOwnProperty(pref)) {
        inputs[pref] = preferences[pref];
      }
    }

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
    inputs.tddFactor = tdd_factor;
    inputs.set_basal = set_basal;
    inputs.basal_rate = basal_rate;
    inputs.old_isf = old_isf;
    inputs.old_cr = old_cr;
    inputs.old_basal = old_basal;
    inputs.iaps = iaps;
    inputs.aisf = aisf;
    inputs.microbolusAllowed = microbolusAllowed;
    inputs.dynamicVariables = dynamicVariables;

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
        oref0_profile.defaults(),
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
            threshold_setting: 65,
            iaps: false,
            dynamicVariables: false
        }
    )

    const logs = { err: '', stdout: '', return_val: 0 };
    const profile = oref0_profile(logs, inputs, defaults, clock.toISOString());
    if (logs.err.length > 0) {
        console.error(logs.err);
    }
    if (logs.stdout.length > 0) {
        console.error(logs.stdout);
    }

    if (typeof profile !== 'object') {
        throw new Error("Failed to build a profile object.");
    }

    return profile;
}
