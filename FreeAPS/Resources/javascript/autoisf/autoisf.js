function generate(profile, autosens, dynamicVariables, glucose, microbolusAllowed, meal, clock, iob, pumpHistory, currenttemp) {
    clock = new Date();

    const autosens_data = autosens ? autosens : null;
    
    var meal_data = {};
    
    if (meal) {
        meal_data = meal;
    }
    
    // Auto ISF
    const glucose_status = getLastGlucose(glucose);
    aisf(profile, autosens_data, dynamicVariables, glucose_status, microbolusAllowed, meal_data, clock, iob, pumpHistory, currenttemp);
    
    return profile
}

let autoISFMessages = []
let autoISFReasons = []

function addMessage(s) {
    autoISFMessages.push(s)
}

function addReason(s) {
    autoISFReasons.push(s)
}

function aisf(profile, autosens_data, dynamicVariables, glucose_status, microbolusAllowed, meal_data, currentTime, iob, pumpHistory, currenttemp) {
    autoISFMessages = [];
    autoISFReasons = [];

    // Turn Auto ISF off when exercising and an exercise setting is enabled, like with dynamic ISF.
    if (exercising(profile, dynamicVariables)) {
        profile.iaps.autoisf = false;
        return
    } else {
        console.log("Starting Auto ISF.");
    }

    // AIMI B30
    if (profile.iaps.use_B30) {
        aimi(profile, pumpHistory, dynamicVariables, glucose_status);
    }
    
    // Auto ISF ratio
    const ratio = aisf_ratio(profile, glucose_status, meal_data, currentTime, autosens_data, 100);
    profile.old_isf = convert_bg(profile.sens, profile);
    profile.aisf = round(ratio, 2);
    
    if (ratio === autosens_data.ratio) {
        addMessage("Auto ISF = Autosens");
    }
    
    // Change the SMB ratio, when applicable
    profile.smb_delivery_ratio = round(determine_varSMBratio(profile, glucose_status.glucose), 2);

    profile.autoISFstring = autoISFMessages.join(". ") + ".";
    profile.autoISFreasons = autoISFReasons.join(", ");

    console.log("End autoISF");
}

function interpolate(xdata, profile, type) { // interpolate ISF behaviour based on polygons defining nonlinear functions defined by value pairs
    const polyX_bg = [50, 60, 80, 90, 100, 110, 150, 180, 200];
    const polyY_bg = [-0.5, -0.5, -0.3, -0.2, 0.0, 0.0, 0.5, 0.7, 0.7];
    const polyX_delta = [2, 7, 12, 16, 20];
    const polyY_delta = [0.0, 0.0, 0.4, 0.7, 0.7];

    let polyX
    let polyY
    if (type === "bg") {
        polyX = polyX_bg;
        polyY = polyY_bg;
    } else if (type === "delta") {
        polyX = polyX_delta;
        polyY = polyY_delta;
    }
    const polymax = polyX.length-1;
    let step = polyX[0];
    let sVal = polyY[0];
    let stepT= polyX[polymax];
    let sValold = polyY[polymax];

    let newVal = 1;
    let lowVal = 1;
    let topVal = 1;
    let lowX = 1;
    let topX = 1;
    let myX = 1;
    let lowLabl = step;

    if (step > xdata) {
        // extrapolate backwards
        stepT = polyX[1];
        sValold = polyY[1];
        lowVal = sVal;
        topVal = sValold;
        lowX = step;
        topX = stepT;
        myX = xdata;
        newVal = lowVal + (topVal - lowVal) / (topX - lowX) * (myX - lowX);
    } else if (stepT < xdata) {
        // extrapolate forwards
        step   = polyX[polymax-1];
        sVal   = polyY[polymax-1];
        lowVal = sVal;
        topVal = sValold;
        lowX = step;
        topX = stepT;
        myX = xdata;
        newVal = lowVal + (topVal - lowVal) / (topX - lowX) * (myX - lowX);
    } else {
        // interpolate
        for (var i=0; i <= polymax; i++) {
            step = polyX[i];
            sVal = polyY[i];
            if (step === xdata) {
                newVal = sVal;
                break;
            } else if (step > xdata) {
                topVal = sVal;
                lowX= lowLabl;
                myX = xdata;
                topX= step;
                newVal = lowVal + (topVal - lowVal) / (topX - lowX) * (myX - lowX);
                break;
            }
            lowVal = sVal;
            lowLabl= step;
        }
    }
    if (xdata > 100) {
        newVal *= profile.iaps.higherISFrangeWeight;
    } else {
        newVal *= profile.iaps.lowerISFrangeWeight;
    }
    return newVal
}

function aisf_ratio(profile, glucose_status, meal_data, currentTime, autosens_data, normalTarget) {
    // The glucose-get-last-autoisf.js parameters
    const parabola_fit_minutes = glucose_status.dura_p;
    const parabola_fit_last_delta = glucose_status.delta_pl;
    const parabola_fit_next_delta = glucose_status.delta_pn;
    const parabola_fit_correlation = glucose_status.r_squ;
    const bg_acce = glucose_status.bg_acceleration;
    const parabola_fit_a0 = glucose_status.a_0;
    const parabola_fit_a1 = glucose_status.a_1;
    const parabola_fit_a2 = glucose_status.a_2;
    const dura05 = glucose_status.dura_ISF_minutes;
    const avg05  = glucose_status.dura_ISF_average;
    const bg_off = profile.min_bg + 10 - glucose_status.glucose;

    let sens_modified = false;
    let autoISFsens = profile.sens;
    const sensitivityRatio = autosens_data.ratio;

    const target_bg = profile.min_bg;
    
    // The Auto ISF ratios
    let acce_ISF = 1;
    let acce_weight = 1;
    let bg_ISF = 1;
    let pp_ISF = 1;
    let dura_ISF = 1;
    let final_ISF = 1;
    
    // Log the glucose-get-last-autoisf.js output
    console.log("AutoISF bg_acceleration: " + round(bg_acce, 2) + ", PF-minutes: " + parabola_fit_minutes + ", PF-corr: " + round(parabola_fit_correlation, 4) + ", PF-nextDelta: " + convert_bg(parabola_fit_next_delta, profile) + ", PF-lastDelta: " + convert_bg(parabola_fit_last_delta, profile) +  ", regular Delta: " + convert_bg(glucose_status.delta, profile));
    console.error(glucose_status.pp_debug);
    
    if (!profile.iaps.enableBGacceleration) {
        console.error("AutoISF BG acceleration adaption disabled in Preferences");
        addMessage("Auto ISF BG acceleration adaption disabled");
    } else {
        // Calculate acce_ISF from bg acceleration and adapt ISF accordingly
        addMessage("bg_acce: " + round(bg_acce, 2));
        if (parabola_fit_a2 !== 0 && parabola_fit_correlation >= 0.9) {
            let minmax_delta = - parabola_fit_a1 / 2 / parabola_fit_a2 * 5; // back from 5min block to 1 min
            const minmax_value = round(parabola_fit_a0 - minmax_delta * minmax_delta / 25 * parabola_fit_a2, 1);
            minmax_delta = round(minmax_delta, 1);
            if (minmax_delta > 0 && bg_acce < 0) {
                console.log("Parabolic fit: predicts a max of " + convert_bg(minmax_value,profile) + ", in about " + Math.abs(minmax_delta) + " min");
                addMessage("Parabolic fit prediction of max " + convert_bg(minmax_value, profile) + " in " + Math.abs(minmax_delta) + " min");
            } else if (minmax_delta > 0 && bg_acce > 0) {
                console.log("Parabolic fit: predicts a min of " + convert_bg(minmax_value,profile) + ", in about " + Math.abs(minmax_delta) + " min");
                addMessage("Parabolic fit prediction of min " + convert_bg(minmax_value, profile) + " in about " + Math.abs(minmax_delta) + " min");
                if (minmax_delta <= 30 && minmax_value < target_bg) {   // start braking
                    acce_weight = -profile.iaps.bgBrakeISFweight;
                    console.log("Parabolic fit: predicts BG below target soon, applying bgBrake ISF weight of " + -acce_weight);
                    addMessage("Parabolic fit: BG below target soon, BG brake of " + -acce_weight);
                }
            } else if (minmax_delta < 0 && bg_acce < 0) {
                console.log("Parabolic fit: saw max of " + convert_bg(minmax_value,profile) + ", about " + Math.abs(minmax_delta) + "min ago");
            } else if (minmax_delta < 0 && bg_acce > 0) {
                console.log("Parabolic fit: saw min of " + convert_bg(minmax_value,profile) + ", about " + Math.abs(minmax_delta) + "min ago");
            }
        }
        if (parabola_fit_correlation < 0.9) {
            console.log("Parabolic fit: acce_ISF bypassed, as correlation, " + round(parabola_fit_correlation, 2) + ", is too low");
            addMessage("Acce_ISF bypassed: correlation " + round(parabola_fit_correlation, 2) + " is too low");
        } else {
            const fit_share = 10 * (parabola_fit_correlation - 0.9);  // 0 at correlation 0.9, 1 at 1.00
            let cap_weight = 1;  // full contribution above target
            if (acce_weight === 1 && glucose_status.glucose < profile.target_bg) {  // below target acce goes towards target
                if (bg_acce > 0) {
                    if (bg_acce>1) {
                        cap_weight = 0.5;  // halve the effect below target
                    }
                    acce_weight = profile.iaps.bgBrakeISFweight;
                } else if (bg_acce < 0) {
                    acce_weight = profile.iaps.bgAccelISFweight;
                }
            } else if (acce_weight === 1) {  // above target acce goes away from target
                if (bg_acce < 0) {
                    acce_weight = profile.iaps.bgBrakeISFweight;
                } else if (bg_acce > 0) {
                    acce_weight = profile.iaps.bgAccelISFweight;
                }
            }
            acce_ISF = 1 + bg_acce * cap_weight * acce_weight * fit_share;
            if (acce_ISF < 0) {
                acce_ISF = 0.1; //no negative acce_ISF ratios
            }
            console.error("Acceleration ISF adaptation is " + round(acce_ISF, 2));
            
            if (acce_ISF !== 1) {
                sens_modified = true;
                console.log("Parabolic fit, acce-ISF: " + round(acce_ISF, 2));
                addMessage("Parabolic fit, acce-ISF: " + round(acce_ISF, 2));
            }
        }
    }

    bg_ISF = 1 + interpolate(100 - bg_off, profile, "bg");
    console.log("BG_ISF adaptation: " + round(bg_ISF, 2));
    let liftISF = 1;

    if (bg_ISF < 1) {
        liftISF = Math.min(bg_ISF, acce_ISF);
        if (acce_ISF > 1) {
            liftISF = bg_ISF * acce_ISF;
            console.log("BG-ISF adaptation lifted to " + round(liftISF, 2) + ", as BG accelerates already");
            addMessage("BG-ISF adaptation lifted to " + round(liftISF, 2) + " as BG accelerates already");
        } else {
            console.log("liftISF: " + round(liftISF, 2) + "(minimal)");
            addMessage("liftISF: " + round(liftISF, 2) + "(minimal)");
        }
        final_ISF = withinISFlimits(liftISF, sensitivityRatio, profile, normalTarget);
        autoISFsens = Math.min(720, round(profile.sens / final_ISF, 1));
        console.log("Final ratio: " + round(final_ISF,2)  + ", final ISF: " + convert_bg(profile.sens, profile) + "\u2192" + convert_bg(autoISFsens, profile));
        
        // iAPS pop-up reasons
        reasons(profile, acce_ISF, bg_ISF, dura_ISF, pp_ISF, liftISF);
        
        return round(final_ISF,2);
    } else if (bg_ISF > 1) {
        sens_modified = true;
        console.log("BG-ISF adaption ratio: " + round(bg_ISF, 2));
    }

    let bg_delta = glucose_status.delta;
    let systemTime = new Date();
    
    if (currentTime) {
        systemTime = new Date(currentTime);
    }
    const deltaType = 'pp';
    
    if (bg_off > 0) {
        console.error(deltaType + "pp_ISF adaptation bypassed as average glucose < " + target_bg + "+10");
        addMessage("pp_ISF adaptation bypassed: average glucose < " + target_bg + "+10. ");
    } else if (glucose_status.short_avgdelta < 0) {
        console.error(deltaType + "pp_ISF adaptation bypassed as no rise or too short lived");
        addMessage("pp_ISF adaptation bypassed: no rise or too short lived");
    } else {
        pp_ISF = 1 + Math.max(0, bg_delta * profile.iaps.postMealISFweight);
        console.log("Post Prandial ISF adaptation is " + round(pp_ISF, 2));
        addMessage("Post Prandial ISF adaptation: " + round(pp_ISF, 2));
        if (pp_ISF !== 1) {
            sens_modified = true;
        }
    }
    const weightISF = profile.iaps.autoISFhourlyChange;  // Specify factor directly; use factor 0 to shut autoISF OFF
    if (dura05 < 10) {
        console.error("dura_ISF bypassed; BG is only " + dura05 + " min at level " + convert_bg(avg05, profile));
        addMessage("Dura ISF bypassed: BG is only " + dura05 + " min at level " + convert_bg(avg05, profile));
    } else if (avg05 <= target_bg * 1.05) { // Don't use dura below target and don't treat glucose near target as a plateaued glucose (fix)
        console.error("dura_ISF bypassed. Avg. glucose " + convert_bg(avg05, profile) + " below target " + convert_bg(target_bg * 1.05, profile));
        addMessage("Dura ISF bypassed: avg. glucose " + convert_bg(avg05, profile) + " below target " + convert_bg(target_bg * 1.05, profile));
    } else {
        // Fight the resistance at high glucose levels
        const dura05_weight = dura05 / 60;
        const avg05_weight = weightISF / target_bg;
        dura_ISF += dura05_weight * avg05_weight * (avg05 - target_bg);
        sens_modified = true;
        console.log("Duration: " + dura05 + ", Avg: " + convert_bg(avg05, profile) + ", dura-ISF ratio: " + round(dura_ISF, 2));
        console.log("dura_ISF adaptation is " + round(dura_ISF, 2) + " because ISF " + convert_bg(profile.sens, profile) + " did not do it for " + round(dura05, 1) + " min");
        addMessage(("Dura ISF adaptation: " + round(dura_ISF, 2) + " because ISF " + convert_bg(profile.sens, profile) + " did not do it for " + round(dura05, 1) + " min"));
    }
    
    // Reasons for iAPS pop-up
    reasons(profile, acce_ISF, bg_ISF, dura_ISF, pp_ISF, liftISF);
    
    if (sens_modified) {
        liftISF = Math.max(dura_ISF, bg_ISF, acce_ISF, pp_ISF);
        console.log("autoISF adaption ratios:");
        console.log("acce " + round(acce_ISF, 2));
        console.log("bg " + round(bg_ISF, 2));
        console.log("dura " + round(dura_ISF, 2));
        console.log("pp " + round(pp_ISF, 2));
    
        if (acce_ISF < 1) {
            console.log("Strongest autoISF factor " + round(liftISF, 2) + " weakened to " + round(liftISF*acce_ISF, 2) + " as bg decelerates already");
            addMessage("Strongest autoISF factor " + round(liftISF, 2) + " weakened to " + round(liftISF * acce_ISF, 2) + " as bg decelerates already");
            liftISF *= acce_ISF; // brakes on for otherwise stronger or stable ISF
        }
        final_ISF = withinISFlimits(liftISF, sensitivityRatio, profile, 100);
        autoISFsens = round(final_ISF, 2);
        console.log("Auto ISF: new Ratio: " + round(final_ISF, 2) + ", final ISF: " + convert_bg(profile.sens, profile) + "\u2192" + convert_bg(autoISFsens, profile));
        
        return round(final_ISF, 2)
    }
    console.log("autoISF does not modify");
    addMessage("Auto ISF does not modify");
    return 1
}

function determine_varSMBratio(profile, bg) {
    const target_bg = profile.min_bg;
    
    if (!profile.iaps.autoisf) {
        console.log("autoISF disabled, don't adjust SMB Delivery Ratio");
        return 0.5;
    }
    let smb_delivery_ratio_bg_range = profile.iaps.smbDeliveryRatioBGrange;
    if (smb_delivery_ratio_bg_range < 10) {
        smb_delivery_ratio_bg_range /= 0.0555;
    }
    const fix_SMB = profile.smb_delivery_ratio;
    const lower_SMB = Math.min(profile.iaps.smbDeliveryRatioMin, profile.iaps.smbDeliveryRatioMax);
    const higher_SMB = Math.max(profile.iaps.smbDeliveryRatioMin, profile.iaps.smbDeliveryRatioMax);
    const higher_bg = target_bg + smb_delivery_ratio_bg_range;
    let new_SMB = fix_SMB;

    if (smb_delivery_ratio_bg_range > 0) {
        new_SMB = lower_SMB + (higher_SMB - lower_SMB) * (bg - target_bg) / smb_delivery_ratio_bg_range;
        new_SMB = Math.max(lower_SMB, Math.min(higher_SMB, new_SMB));  // cap if outside target_bg--higher_bg
    }
    
    if (smb_delivery_ratio_bg_range === 0) { // deactivated in Auto ISF setting
        return fix_SMB;
    }
    if (bg <= target_bg) {
        console.error("SMB delivery ratio limited by minimum value " + round(lower_SMB, 2));
        return lower_SMB;
    }
    if (bg >= higher_bg) {
        console.error("SMB delivery ratio limited by maximum value " + round(higher_SMB, 2));
        return higher_SMB;
    }
    
    console.error("SMB delivery ratio set to interpolated value " + round(new_SMB, 2));
    return new_SMB
}

function withinISFlimits(liftISF, sensitivityRatio, profile, normalTarget) {
    let origin_sens = " " + profile.sens;
    console.log("check ratio " + round(liftISF, 2) + " against autoISF min: " + profile.autosens_min + " and autoISF max: " + profile.autosens_max);
    
    if (liftISF < profile.autosens_min) {
        console.log("Weakest autoISF factor " + round(liftISF, 2) + " limited by autoISF_min " + profile.autosens_min);
        addMessage("Weakest autoISF factor " + round(liftISF, 2) + " limited by autoISF_min " + profile.autosens_min);
        liftISF = profile.autosens_min;
    } else if (liftISF > profile.autosens_max) {
        console.log("Strongest autoISF factor " + round(liftISF, 2) + " limited by autoISF_max " + profile.autosens_max);
        addMessage("Strongest autoISF factor " + round(liftISF, 2) + " limited by autoISF_max " + profile.autosens_max);
        liftISF = profile.autosens_max;
    }
    let final_ISF = 1;
    // SensitivityRatio = Autosens ratio
    if (liftISF >= 1) {
        final_ISF = Math.max(liftISF, sensitivityRatio);
        if (liftISF >= sensitivityRatio) {
            origin_sens = ""; // autoISF dominates
        }
    } else {
        final_ISF = Math.min(liftISF, sensitivityRatio);
        if (liftISF <= sensitivityRatio) {
            origin_sens = "";  // autoISF dominates
        }
    }
    console.log("final ISF factor " + round(final_ISF,2) + origin_sens);
    return final_ISF
}

function convert_bg(value, profile) {
    if (profile.out_units === "mmol/L") {
        return round(value * 0.0555, 1);
    }
    else {
        return Math.round(value);
    }
}
    
function round(value, digits) {
    if (! digits) { digits = 0; }
    const scale = Math.pow(10, digits);
    return Math.round(value * scale) / scale;
}

function exercising(profile, dynamicVariables) {
    // One of two exercise settings (they share the same purpose).
    if (profile.high_temptarget_raises_sensitivity || profile.exercise_mode || dynamicVariables.isEnabled) {
        // Turn dynISF off when using a temp target >= 118 (6.5 mol/l) and if an exercise setting is enabled.
        if (profile.min_bg >= 118 || (dynamicVariables.useOverride && dynamicVariables.overrideTarget >= 118)) {
            profile.autoISFreasons = "Auto ISF disabled";
            profile.autoISFstring = "Disabled by exercise";
            console.log(profile.autoISFreasons);
            return true;
        }
    }
    return false
}

// AIMI B30
function aimi(profile, pumpHistory, dynamicVariables, glucose_status) {
    let isActive = false;
    let rate = profile.current_basal;
    const duration = profile.iaps.b30_duration;
    let iTime = duration + 1;

    const iTime_Start_Bolus = profile.iaps.iTime_Start_Bolus;
    const b30targetLevel = profile.iaps.iTime_target;
    const b30upperLimit = profile.iaps.b30upperLimit;
    const b30upperdelta = profile.iaps.b30upperdelta;
    const b30factor = profile.iaps.b30factor;
    let B30TTset = false;
    let PHlastBolus = 0;
    let PHlastBolusAge = 0;
        
    // Bolus age and bolus limit
    for (let i = 0; i < pumpHistory.length; i++) {
        if (pumpHistory[i]._type === "Bolus" && pumpHistory[i].amount > iTime_Start_Bolus) {
            let PHBolusTime = new Date(pumpHistory[i].timestamp);
            let currentDate = new Date();
            PHlastBolusAge = round( (currentDate - PHBolusTime) / 36e5 * 60, 1);
            PHlastBolus = pumpHistory[i].amount;
            break;
        }
    }

    // Ues when target set either by a TT or a profile override
    if ((profile.temptargetSet || (dynamicVariables.useOverride && dynamicVariables.overrideTarget > 6)) && (profile.min_bg <= b30targetLevel || dynamicVariables.overrideTarget <= b30targetLevel)) {
        B30TTset = true;
    }

    let B30lastbolusAge = PHlastBolusAge;
    // let LastManualBolus = PHlastBolus; // unused
    
    if (B30lastbolusAge === 0) {
        B30lastbolusAge = 1;
    }
    
    if (B30lastbolusAge <= duration && B30TTset) {
        iTime = B30lastbolusAge;
        isActive = true;
        
        if (glucose_status.delta <= b30upperdelta && glucose_status.glucose < b30upperLimit) {
            isActive = false;
            console.log("B30 deactivated by high glucose");
        }
    }
    
    if (B30TTset && isActive && iTime <= duration) {
        rate *= b30factor;
        profile.set_basal = true;
        profile.basal_rate = round(rate, 2);
        
        console.log("B30 iTime is running. iTime remaining: " + round((duration - iTime), 1) + "min");
        addMessage("B30 iTime remaining: " + round((duration - iTime), 1) + "min");
        addReason("AIMI B30 active");
        console.log("AIMI B30 enabled with Target (TT or Override).");
        console.log("AIMI B30 Suggested Basal Rate: " + profile.basal_rate + " U/h.");
    }
}

// Reasons for iAPS pop-up
function reasons(profile, acce_ISF, bg_ISF, dura_ISF, pp_ISF, liftISF) {
    addReason("acce: " + round(acce_ISF, 2));
    addReason("bg: " + round(bg_ISF, 2));
    addReason("dura: " + round(dura_ISF, 2));
    addReason("pp: " + round(pp_ISF, 2));
}
