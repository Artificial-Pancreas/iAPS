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
module.exports = (iaps_input) => {
  let oref0_inputs = {
    history: iaps_input.pump_history
    , history24: null
    , profile: iaps_input.profile
    , clock: new Date(Date.parse(iaps_input.clock))
  }

  if (iaps_input.autosens) {
    oref0_inputs.autosens = iaps_input.autosens
  }

  // TODO: this should happen in profile prepare

  // Adjust for eventual Overrides
  const dynamicVariables = oref0_inputs.profile.dynamicVariables || { } ;

  if (dynamicVariables.useOverride) {
    if (dynamicVariables.useOverride && dynamicVariables.overridePercentage != 100 && dynamicVariables.basal) {
      oref0_inputs.profile.basalprofile.forEach( basal => basal.rate *= (dynamicVariables.overridePercentage / 100))
    }
  }

  return oref0_iob(oref0_inputs)
}
