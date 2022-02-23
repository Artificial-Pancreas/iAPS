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
    var logBasal = "";
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
    //  Calculate basals delivered with scheduled basal rates or Autotuned basal rates.
    //  Check for 0 temp basals with 0 min duration. Take that timestamp and compare to next enacted temp basal. The difference should be duration of current scheduled basal (which can be retrieved from profile.json). This is for when ending a manual temp basal and (perhaps) continueing in open loop.
    //  Also check for temp basals with a real duration < (next.basal.timestamp - orig.basal.timestamp). This is a temp basal that completes. Then calculate (following.basal.timestamp - next.basal.timestamp)h * the basal rate scheduled at that time.
    ///
    var scheduledBasalInsulin = 0;
    for (let i = 0; i < pumphistory.length; i++) {
        // Check for 0 temp basals with 0 min duration.
        if (pumphistory[i]['duration (min)'] == 0) {
            let time1 = new Date(pumphistory[i].timestamp);
            let time2 = time1;
            let j = i;
            do {
                j--;
                if (pumphistory[j]._type == "TempBasal" && j >= 0) {
                    time2 = new Date(pumphistory[j].timestamp);
                    break;
                }
            } while (j >= 0);
            // duration of current scheduled basal
            let basDuration = (time2 - time1) / 36e5;
            if (basDuration > 0) {
                let hour = time1.getHours();
                let minutes = time1.getMinutes();
                let seconds = "00";
                string = "" + hour + ":" + minutes + ":" + seconds;
                let basalScheduledRate = 0;
                for (let k = 0; k < profile.basalprofile.length; k++) {
                    if (profile.basalprofile[k].start = string) {
                        basalScheduledRate = profile.basalprofile[k].rate;
                        // This is the scheduled insulin amount delivered after ending a manual temp basal and (perhaps) when continuing in open loop or if disconnected
                        scheduledBasalInsulin += basalScheduledRate * basDuration;
                        break;
                    } else if (profile.basalprofile[k].start < string && profile.basalprofile[k+1].start > string){
                            basalScheduledRate = profile.basalprofile[k].rate;
                            scheduledBasalInsulin += basalScheduledRate * basDuration;
                            break;
                    }
                }
            }
        }
        
        // Check for temp basals that completes
        if (pumphistory[i]._type == "TempBasal") {
            let time1 = new Date(pumphistory[i].timestamp);
            let time2 = time1;
            for (let m = i; m < pumphistory.length; m--) {
                if (pumphistory[m]._type == "TempBasal") {
                    let time2 = new Date(pumphistory[m].timestamp);
                    break;
                }
            }
            let basDuration = (time2 - time1) / 36e5;
            if ((pumphistory[i-1]['duration (min)'] / 60 ) < basDuration) {
                let timeOrig = new Date(pumphistory[i-1].timestamp);
                for (let l = i-1; l < pumphistory.length; l++) {
                    if (pumphistory[l]._type == "TempBasal") {
                        let timeNext = new Date(timeOrig = pumphistory[l].timestamp);
                        break;
                    }
                }
                let durationOfSheduledBasal = (timeNext - timeOrig) / 36e5;
                let hour = time1.getHours();
                let minutes = time1.getMinutes();
                let seconds = "00";
                let string = "" + hour + ":" + minutes + ":" + seconds;
                let basalScheduledRate = 0;
                for (let k = 0; k < profile.basalprofile.length; k++) {
                    if (profile.basalprofile[k].start = string) {
                        basalScheduledRate = profile.basalprofile[k].rate;
                        // This is the scheduled insulin amount delivered after a fully completed temp basal
                        scheduledBasalInsulin += basalScheduledRate * basDuration;
                        break;
                    } else if (profile.basalprofile[k].start < string && profile.basalprofile[k+1].start > string){
                        basalScheduledRate = basalScheduledRate = profile.basalprofile[k].rate;
                        // This is the scheduled insulin amount delivered after a fully completed temp basal
                        scheduledBasalInsulin += basalScheduledRate * basDuration;
                        break;
                      }
                }
            }
        }
    }
    
    TDD += scheduledBasalInsulin
    logBasal = ". Delivered scheduled basal rate insulin: " + scheduledBasalInsulin.toPrecision(5);
                           
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
        return log + logTDD + logBasal;
        
    } else { return "Chris' formula is off." }
}
