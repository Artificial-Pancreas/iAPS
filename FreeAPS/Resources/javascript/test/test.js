/*

 Made for testing the OpenAPSManager
 
 To run search in Xcode for:  "For testing replace with:"
 You need to uncomment and comment one line in two files to change to this javaScript instead of normal determine-basal.js
 
*/
var autoISFMessages = [];
var autoISFReasons = [];

var test = function test(glucose_status, currenttemp, iob_data, profile, autosens_data, meal_data, tempBasalFunctions, microBolusAllowed, reservoir_data, currentTime) {

    //Prepare IOB data
    const iobArray = iob_data;
    if (typeof(iob_data.length) && iob_data.length > 1) {
        iob_data = iobArray[0];
    }
    
    addReason("Test");

    // Processed data. Change or add when needed
    const deliverAt = new Date();
    const basal = round(profile.current_basal, 2);
    const systemTime = new Date();
    const bgTime = new Date(glucose_status.date);
    const minAgo = round( (systemTime - bgTime) / 60 / 1000 ,1);
    const bg = glucose_status.glucose;
    const noise = glucose_status.noise;
    const sens = profile.sens;
    const max_iob = profile.max_iob;
    const iob = iob_data.iob;
    const target_bg = profile.min_bg;
    const minDelta = Math.min(glucose_status.delta, glucose_status.short_avgdelta);
    const minAvgDelta = Math.min(glucose_status.short_avgdelta, glucose_status.long_avgdelta);
    const maxDelta = Math.max(glucose_status.delta, glucose_status.short_avgdelta, glucose_status.long_avgdelta);
    const bgi = round(( -iob_data.activity * sens * 5 ), 2);
    const roundSMBTo = 1 / profile.bolus_increment;
    
    //Configure your testing variables. Change whatever data
    const insulinReq = 3;
    const carbsReq = 0;
    const rate = 0;
    const duration = 30;
    
    // The microBolus and the maxBolus algorithms for SMBs. Same as in oref0 but condensed.
    const maxBolus = round(profile.current_basal * profile.maxSMBBasalMinutes * 30 / 60, 1);
    let microbolus = Math.floor(Math.max(Math.min(insulinReq * profile.smb_delivery_ratio, maxBolus, max_iob - iob), 0) * roundSMBTo)/roundSMBTo;
    
    var rT = {}; //short for requestedTemp
    rT = {
        'temp': 'absolute'
        , 'bg': bg
        , 'tick': ''
        , 'eventualBG': 150
        , 'insulinReq': insulinReq
        , 'carbsReq': carbsReq
        , 'reservoir' : reservoir_data
        , 'deliverAt' : deliverAt
        , 'sensitivityRatio' : autosens_data.ratio
        , 'rate': rate
        , 'duration': duration
        , 'deliverAt': deliverAt
        , 'ISF': sens
        , 'CR': profile.carb_ratio
        , 'COB': meal_data.mealCOB
        , 'IOB': iob
        , 'target_bg': convert_bg(target_bg, profile)
        , 'error': ''
    };
    
    addMessage("; Testing OpenAPS Manager ");
    
    if (microbolus > 0) {
        rT.units = microbolus;
        addMessage("Microbolusing: " + microbolus + "U ");
    }

    // Predictions are empty. Add Whatever algorithm or values to see in iAPS
    var COBpredBGs = [];
    var IOBpredBGs = [];
    var UAMpredBGs = [];
    var ZTpredBGs = [];
    COBpredBGs.push(bg);
    IOBpredBGs.push(bg);
    ZTpredBGs.push(bg);
    UAMpredBGs.push(bg);
    rT.predBGs = {};
    rT.predBGs.IOB = IOBpredBGs;
    rT.predBGs.ZT = ZTpredBGs;
    rT.predBGs.COB = COBpredBGs;
    rT.predBGs.UAM = UAMpredBGs;
    
    // Reasons
    rT.reason = autoISFReasons.join(", ") + autoISFMessages.join(". ");
    
    // To skip tempBasalFunctions uncomment below
    // return rT
    
    return tempBasalFunctions.setTempBasal(rT.rate, rT.duration, profile, rT, currenttemp);
};

// Rounds value to 'digits' decimal places
function round(value, digits) {
    if (! digits) { digits = 0; }
    var scale = Math.pow(10, digits);
    return Math.round(value * scale) / scale;
}

function convert_bg(value, profile) {
    if (profile.out_units === "mmol/L") {
        return round(value * 0.0555, 1);
    }
    else {
        return Math.round(value);
    }
}

function addMessage(s) {
    autoISFMessages.push(s)
}

function addReason(s) {
    autoISFReasons.push(s)
}
