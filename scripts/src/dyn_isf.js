const round = require('./utils').round
const exercising = require('./utils').exercising

// The Dynamic ISF layer
function dynisf(profile, autosens_data, dynamicVariables, glucose) {
  console.log("Starting dynamic ISF layer.");
  var dynISFenabled = true;

  //Turn off when Auto ISF is used
  if (profile.iaps.autoisf) {
    console.log("Dynamic ISF disabled due to Auto ISF.");
    return;
  }

  // Turn dynISF off when using a temp target >= 118 (6.5 mol/l) and if an exercise setting is enabled.
  if (exercising(profile, dynamicVariables)) {
    console.log("Dynamic ISF disabled due to a high temp target/exercise.");
    return;
  }

  const target = profile.min_bg;

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
  const weighted_average = dynamicVariables.weightedAverage;
  const weightPercentage = dynamicVariables.weigthPercentage;
  const average14 = dynamicVariables.average_total_data;

  if (weightPercentage > 0 && weighted_average > 0) {
    tdd = weighted_average;
    console.log("Using a weighted TDD average: " + weighted_average);
  } else {
    console.log("Dynamic ISF disabled. Not enough TDD data.");
    return;
  }

  // Account for TDD of insulin. Compare last 2 hours with total data (up to 10 days)
  var tdd_factor = weighted_average / average14; // weighted average TDD / total data average TDD

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
    console.log(", Dynamic ISF limited by autosens_min setting to: " + autosens_min + ", from: " + newRatio);
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
}
