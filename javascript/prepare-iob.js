function generate(pumphistory_data, profile_data, clock_data, autosens_data, pumphistory_24_data) {
    var inputs = {
        history: pumphistory_data,
        history24: pumphistory_24_data,
        profile: profile_data,
        clock: clock_data
    };
    if (autosens_data)  {
        inputs.autosens = autosens_data;
    }

    return freeaps(inputs);
}

