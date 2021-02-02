var printLog = function(...args) {};
var process = { stderr: { write: printLog } };

function generate(pumphistory_data, profile_data, carb_data, glucose_data, basalprofile, temptarget_data) {
    var iob_inputs = {
        history: pumphistory_data,
        profile: profile_data
    };

    var detection_inputs = {
        iob_inputs: iob_inputs,
        carbs: carb_data,
        glucose_data: glucose_data,
        basalprofile: basalprofile,
        temptargets: temptarget_data
    };
    detection_inputs.deviations = 96;
    var ratio8h = freeaps(detection_inputs);
    detection_inputs.deviations = 288;
    var ratio24h = freeaps(detection_inputs);
    return ratio8h.ratio < ratio24h.ratio ? ratio8h : ratio24h
}
