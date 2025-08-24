// from OREF0_DIST_PATH
const oref0_iob = require('oref0/iob/index.js')

/*
*   {
*     pump_history: [PumpHistoryEvent],
*     profile: Profile,
*     clock: Date,
*     autosens: Autosens?
*   }
* */
module.exports = ({ pump_history, profile, clock, autosens }) => {
    let inputs = {
      history: pump_history
      , history24: null
      , profile: profile
      , clock: new Date(Date.parse(clock))
    }

    if (autosens) {
      inputs.autosens = autosens
    }

    // Adjust for eventual Overrides
    const dynamicVariables = profile.dynamicVariables || {} ;

    if (dynamicVariables.useOverride) {
      if (dynamicVariables.useOverride && dynamicVariables.overridePercentage != 100 && dynamicVariables.basal) {
        inputs.profile.basalprofile.forEach( basal => basal.rate *= (dynamicVariables.overridePercentage / 100))
      }
    }

    return oref0_iob(inputs)
}
