function middleware(iob, currenttemp, glucose, profile, autosens, meal, reservoir, clock, pumphistory) {
     
    // This middleware only works if you have added pumphistory to middleware in FreeAPS X code (my pumphistory branch).
    const BG = glucose[0].glucose;
    // Change to false to turn off Chris Wilson's formula
    var chrisFormula = true;
    var TDD = 0.0;
    const minLimitChris = profile.autosens_min;
    const maxLimitChris = profile.autosens_max;
    const adjustmentFactor = 1;
    // Your current target, lower limit
    const currentMinTarget = profile.min_bg;
    var exerciseSetting = false;
    var log = "";
    var logTDD = "";
    var current = 0;
    // If you have not set this to 0.05 in FAX settings (Omnipod), this will be set to 0.1 in code.
    var minimalDose = profile.bolus_increment;
    var insulin = 0.00;
    var incrementsRaw = 0.00;
    var incrementsRounded = 0.00;
    var quota = 0;
    
    if (profile.high_temptarget_raises_sensitivity == true || profile.exercise_mode == true) {
        exerciseSetting = true;
    }
    
    // Turn off Chris' formula (and AutoISF) when using a temp target >= 118 (6.5 mol/l) and if an exercise setting is enabled.
    // If using AutoISF uncomment the profile.use_autoisf = false
    if (currentMinTarget >= 118 && exerciseSetting == true) {
        // profile.use_autoisf = false;
        chrisFormula = false;
        log = "Chris' formula off due to a high temp target/exercising. Current min target: " + currentMinTarget;
    }

    // Calculate TDD --------------------------------------
    //Bolus:
    for (let i = 0; i < pumphistory.length; i++) {
        if (pumphistory[i]._type == "Bolus") {
            // Bolus delivered
            TDD += pumphistory[i].amount;
        }
    }

    // Temp basals:
    for (let j = 1; j < pumphistory.length; j++) {
            if (pumphistory[j]._type == "TempBasal" && pumphistory[j].rate > 0) {
                current = j;
                quota = pumphistory[j].rate;
                var duration = pumphistory[j-1]['duration (min)'] / 60;
                var origDur = duration;
                var pastTime = new Date(pumphistory[j-1].timestamp);
                // If temp basal hasn't yet ended, use now as end date for calculation
                do {
                    j--;
                    if (j <= 0) {
                        var morePresentTime =  new Date();
                        break;
                    } else if (pumphistory[j]._type == "TempBasal" || pumphistory[j]._type == "PumpSuspend") {
                        var morePresentTime = new Date(pumphistory[j].timestamp);
                        break;
                      }
                }
                while (j >= 0);
                  
                
                var diff = (morePresentTime - pastTime) / 36e5;
                if (diff < origDur) {
                    duration = diff;
                }
                insulin = quota * duration;
            
                // Account for smallest possible pump dosage
                if (minimalDose != 0.05) {
                    minimalDose = 0.1;
                }
                incrementsRaw = insulin / minimalDose;
                if (incrementsRaw >= 1) {
                    incrementsRounded = Math.floor(incrementsRaw);
                    insulin = incrementsRounded * minimalDose;
                } else { insulin = 0}
            
                // Add temp basal delivered to TDD
                TDD += insulin;
                j = current;
            }
    }
    logTDD = ". TDD past 24h is: " + TDD.toPrecision(3) + " U";
    // ----------------------------------------------------
      
    // Chris' formula:
    if (chrisFormula == true && TDD > 0) {
        var newRatio = profile.sens / (277700 / (adjustmentFactor  * TDD * BG));
        log = "New ratio using Chris' formula is " + newRatio.toPrecision(3) + " with ISF: " + (profile.sens / newRatio).toPrecision(3) + " (" + ((profile.sens / newRatio) * 0.0555).toPrecision(3) + " mmol/l/U)";

        // Respect autosens.max and autosens.min limits
        if (newRatio > maxLimitChris) {
            newRatio = maxLimitChris;
            log = "Chris' formula hit limit by autosens_max setting: " + maxLimitChris + ". ISF: " + (profile.sens / newRatio).toPrecision(3) + " (" + ((profile.sens / newRatio) * 0.0555).toPrecision(3) + " mmol/l/U)";
        } else if (newRatio < minLimitChris) {
            newRatio = minLimitChris;
            log = "Chris' formula hit limit by autosens_min setting: " + minLimitChris + ". ISF: " + (profile.sens / newRatio).toPrecision(3) + " (" + ((profile.sens / newRatio) * 0.0555).toPrecision(3) + " mmol/l/U)";
          }

        // Set the new ratio
        autosens.ratio = newRatio;
        return log + logTDD;
        
    } else { return "Chris' formula is disabled." }
}
