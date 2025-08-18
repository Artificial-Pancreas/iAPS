export function invoke(input, call) {
  try {
    const result = call(input)
    return JSON.stringify(result)
  } catch (e) {
    console.log("INVOKE ERROR: ", e.toString(), e)
    return JSON.stringify({
      script_error: e.toString()
    })
  }
}


export function round(value, digits) {
  if (! digits) { digits = 0; }
  var scale = Math.pow(10, digits);
  return Math.round(value * scale) / scale;
}

export function exercising(profile, dynamicVariables) {
  // One of two exercise settings (they share the same purpose).
  if (profile.high_temptarget_raises_sensitivity || profile.exercise_mode || dynamicVariables.isEnabled) {
    // Turn dynISF off when using a temp target >= 118 (6.5 mol/l) and if an exercise setting is enabled.
    if (profile.min_bg >= 118) {
      return true
    }
  }
  return false
}

export function disableSMBs(dynamicVariables, now) {
  if (dynamicVariables.smbIsOff) {
    // smbIsAlwaysOff=true means "SMB are scheduled, NOT always off"
    if (!dynamicVariables.smbIsAlwaysOff) { return true; }

    var start = dynamicVariables.start;
    var end = dynamicVariables.end;
    var hour = now.getHours();

    if (start <= end) {
      return hour >= start && hour <= end;
    } else {
      return hour >= start || hour <= end;
    }
  }
  return false
}
