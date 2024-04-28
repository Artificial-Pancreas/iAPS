//для enact/smb-suggested.json параметры: monitor/iob.json monitor/temp_basal.json monitor/glucose.json settings/profile.json settings/autosens.json --meal monitor/meal.json --microbolus --reservoir monitor/reservoir.json

function generate(iob, currenttemp, glucose, profile, autosens = null, meal = null, microbolusAllowed = true, reservoir = null, clock, oref2_variables) {
    
    // Needs to be updated here due to time format).
    clock = new Date()
    
    var glucose_status = freeaps_glucoseGetLast(glucose);
    var autosens_data = null;

    if (autosens) {
        autosens_data = autosens;
    }
    
    var reservoir_data = null;
    if (reservoir) {
        reservoir_data = reservoir;
    }

    var meal_data = {};
    if (meal) {
        meal_data = meal;
    }
    
    // Overrides
    if (oref2_variables && oref2_variables.useOverride) {
        const factor = oref2_variables.overridePercentage / 100;
        if (factor != 1) {
            // Basal
            profile.current_basal *= factor;
            // ISF and CR
            if (oref2_variables.isfAndCr) {
                profile.sense /= factor;
                carbRatio /= factor;
            } else {
                if (oref2_variables.cr) { profile.carbRatio /= factor; }
                if (oref2_variables.isf) { profile.sens /= factor; }
            }
            console.log("Override Active, " + oref2_variables.overridePercentage + "%");
        }
            // SMB Minutes
        if (oref2_variables.advancedSettings && oref2_variables.smbMinutes !== profile.maxSMBBasalMinutes) {
            console.log("SMB Max Minutes - setting overriden from " + profile.maxSMBBasalMinutes + " to " + oref2_variables.smbMinutes);
            profile.maxSMBBasalMinutes = oref2_variables.smbMinutes;
        }
        // UAM Minutes
        if (oref2_variables.advancedSettings && oref2_variables.uamMinutes !== profile.maxUAMSMBBasalMinutes) {
            console.log("UAM Max Minutes - setting overriden from " + profile.maxUAMSMBBasalMinutes + " to " + oref2_variables.uamMinutes);
            profile.maxUAMSMBBasalMinutes = oref2_variables.uamMinutes;
        }
            //Target
        if (oref2_variables.overrideTarget != 0 && oref2_variables.overrideTarget != 6 && !profile.temptargetSet) {
            profile.min_bg = oref2_variables.overrideTarget;
            profile.max_bg = profile.min_bg;
            console.log("Override Active, new glucose target: " + oref2_variables.overrideTarget);
        }
        
            //SMBs
        if (disableSMBs(oref2_variables)) {
            microbolusAllowed = false;
            console.error("SMBs disabled by Override");
        }
        
        // Max IOB
        if (oref2_variables.advancedSettings && oref2_variables.maxIOB !== profile.maxIOB) {
            profile.max_iob = oref2_variables.maxIOB;
            console.log("Override Active, new maxIOB: " + profile.max_iob);
        }
    }
    
    // Half Basal Target
    if (oref2_variables.isEnabled) {
        profile.half_basal_exercise_target = oref2_variables.hbt;
        console.log("Temp Target active, half_basal_exercise_target: " + oref2_variables.hbt);
    }
    
    // Dynamic ISF
    if (profile.useNewFormula) {
        dynisf(profile, autosens_data, oref2_variables, glucose);
    } else { console.log("Dynamic ISF disabled in settings."); }
    
    return freeaps_determineBasal(glucose_status, currenttemp, iob, profile, autosens_data, meal_data, freeaps_basalSetTemp, microbolusAllowed, reservoir_data, clock);
}

// The Dynamic ISF layer
function dynisf(profile, autosens_data, oref2_variables, glucose) {
    var dynISFenabled = true;
    // One of two exercise settings (they share the same purpose).
    var exerciseSetting = false;
    if (profile.highTemptargetRaisesSensitivity || profile.exerciseMode || oref2_variables.isEnabled) {
        exerciseSetting = true;
    }
        
    const target = profile.min_bg;
        
    // Turn dynISF off when using a temp target >= 118 (6.5 mol/l) and if an exercise setting is enabled.
    if (target >= 118 && exerciseSetting) {
        //dynISFenabled = false;
        console.log("Dynamic ISF disabled due to a high temp target/exercise.");
        return;
    }

    // In case the autosens.min/max limits are reversed:
    const autosens_min = Math.min(profile.autosens_min, profile.autosens_max);
    const autosens_max = Math.max(profile.autosens_min, profile.autosens_max);

    // Turn off when autosens.min = autosens.max etc.
    if (autosens_max == autosens_min || autosens_max < 1 || autosens_min > 1) {
        console.log("Dynamic ISF disabled due to current autosens settings");
        return;
    }

    // Insulin curve
    const curve = profile.curve;
    const ipt = profile.insulinPeakTime;
    const ucpk = profile.useCustomPeakTime;
    var insulinFactor = 55 // deafult (120-65)
    var insulinPA = 65 // default (Novorapid/Novolog)

    switch (curve) {
    case "rapid-acting":
        insulinPA = 65;
        break;
    case "ultra-rapid":
        insulinPA = 50;
        break;
    }
        
    if (ucpk) {
        insulinFactor = 120 - ipt;
        console.log("Custom insulinpeakTime set to: " + ipt + ", " + "insulinFactor: " + insulinFactor);
    } else {
        insulinFactor = 120 - insulinPA;
        console.log("insulinFactor set to : " + insulinFactor);
    }

    // Use a weighted TDD average
    var tdd = 0;
    const weighted_average = oref2_variables.weightedAverage;
    const weightPercentage = oref2_variables.weigthPercentage;
    const average14 = oref2_variables.average_total_data;

    if (weightPercentage > 0 && weighted_average > 0) {
        tdd = weighted_average;
        console.log("Using a weighted TDD average: " + weighted_average);
    } else {
        console.log("Dynamic ISF disabled. Not enough TDD data.");
        return;
    }

    // Account for TDD of insulin. Compare last 2 hours with total data (up to 10 days)
    const tdd_factor = weighted_average / average14; // weighted average TDD / total data average TDD
    
    const enable_sigmoid = profile.sigmoid;
    var newRatio = 1;

    const sensitivity = profile.sens;
    const adjustmentFactor = profile.adjustmentFactor;
    
    var BG = 100;
        if (glucose.length > 0) {
        BG = glucose[0].glucose;
    }

    if (dynISFenabled && !(enable_sigmoid)) {
        const power = BG / insulinFactor + 1;
        newRatio = round(sensitivity * adjustmentFactor * tdd * Math.log(power) / 1800, 2);
        console.log("Dynamic ISF enabled. Dynamic Ratio (Logarithmic formula): " + newRatio);
    }

    // Sigmoid Function
    if (dynISFenabled && enable_sigmoid) {
        const autosens_interval = autosens_max - autosens_min;
        // Blood glucose deviation from set target (the lower BG target) converted to mmol/l to fit current formula.
        console.log("autosens_interval: " + autosens_interval);
        const bg_dev = (BG - target) * 0.0555;
        var max_minus_one = autosens_max - 1;
        // Avoid division by 0
        if (autosens_max == 1) {
            max_minus_one = autosens_max + 0.01 - 1;
        }
        // Makes sigmoid factor(y) = 1 when BG deviation(x) = 0.
        const fix_offset = (Math.log10(1/max_minus_one-autosens_min/max_minus_one) / Math.log10(Math.E));
        //Exponent used in sigmoid formula
        const exponent = bg_dev * adjustmentFactor * tdd_factor + fix_offset;
        // The sigmoid function
        const sigmoid_factor = autosens_interval / (1 + Math.exp(-exponent)) + autosens_min;
        newRatio = round(sigmoid_factor, 2);
    }

    // Respect autosens.max and autosens.min limitLogs
    if (newRatio > autosens_max) {
        console.log(", Dynamic ISF limited by autosens_max setting to: " + autosens_max + ", from: " + newRatio);
        newRatio = autosens_max;
    } else if (newRatio < autosens_min) {
        console.log("Dynamic ISF limited by autosens_min setting to: " + autosens_min + ", from: " + newRatio);
        newRatio = autosens_min;
    }

    // Dynamic CR
    var cr = profile.carb_ratio;
    if (profile.enableDynamicCR) {
        cr /= newRatio;
        profile.carb_ratio = round(cr, 1);
        console.log(". Dynamic CR enabled, Dynamic CR: " + profile.carb_ratio + " g/U.");
    }

    // Dyhamic ISF
    const isf = round(profile.sens / newRatio, 1);
    autosens_data.ratio = newRatio;
    if (enable_sigmoid) {
        console.log("Dynamic ISF enabled. Dynamic Ratio (Sigmoid function): " + newRatio + ". New ISF = " + isf + " mg/dl / " + round(0.0555 * isf, 1) + " mmol/l.");
    }

    // Basal Adjustment
    if (profile.tddAdjBasal && dynISFenabled) {
        profile.current_basal *= tdd_factor;
        console.log("Dynamic ISF. Basal adjusted with TDD factor: " + round(tdd_factor, 1));
    }
}

function round(value, digits) {
    if (! digits) { digits = 0; }
    var scale = Math.pow(10, digits);
    return Math.round(value * scale) / scale;
}

function disableSMBs(oref2_variables) {
    if (oref2_variables.smbIsOff) {
        if (!oref2_variables.smbIsAlwaysOff) {
            return true;
        }
        const hour = new Date().getHours();
        if (oref2_variables.end < oref2_variables.start && hour < 24 && hour > oref2_variables.start) {
            oref2_variables.end += 24;
        }
        if (hour >= oref2_variables.start && hour <= oref2_variables.end) {
            return true;
        }
        if (oref2_variables.end < oref2_variables.start && hour < oref2_variables.end) {
            return true;
        }
    }
    return false
}
