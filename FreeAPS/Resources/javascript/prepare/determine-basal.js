//для enact/smb-suggested.json параметры: monitor/iob.json monitor/temp_basal.json monitor/glucose.json settings/profile.json settings/autosens.json --meal monitor/meal.json --microbolus --reservoir monitor/reservoir.json
var printLog = function(...args) {};
var process = { stderr: { write: printLog } };


function generate(iob_data, currenttemp, glucose_data, profile, autosens_input = false, meal_input = false, microbolus = false, reservoir_input = false){
    var glucose_status = freeaps_glucoseGetLast(glucose_data);
    var autosens_data = null;

    if (autosens_input) {
        autosens_data = autosens_input;
    }

    var reservoir_data = null;
    if (reservoir_input) {
        reservoir_data = reservoir_input;
    }

    var meal_data = { };
    if (meal_input) {
        meal_data = meal_input;
    }

    return freeaps_determineBasal(glucose_status, currenttemp, iob_data, profile, autosens_data, meal_data, freeaps_basalSetTemp, microbolus, reservoir_data, null);
}
