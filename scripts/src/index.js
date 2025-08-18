const invoke = require('./utils').invoke

const autosens = require('./autosens')
const meal = require('./meal')
const iob = require('./iob')
const determineBasal = require('./determine-basal')
const autotune = require('./autotune')
const profile = require('./profile')
const middleware = require('./middleware')
const autoisf = require('./autoisf')

const iaps = {

  oref0: {

    autosens(iapsInput) {
      return invoke(iapsInput, autosens)
    },

    meal(iapsInput) {
      return invoke(iapsInput, meal)
    },

    iob(iapsInput) {
      return invoke(iapsInput, iob)
    },

    determine_basal(iapsInput) {
      return invoke(iapsInput, determineBasal)
    },

    autotune(iapsInput) {
      return invoke(iapsInput, autotune)
    },

    profile(iapsInput) {

    },

  }, // end oref0

  profile(iapsInput) {
    return invoke(iapsInput, profile)
  },

  middleware(iapsInput) {
    return invoke(iapsInput, middleware)
  },

  autoisf(iapsInput) {
    return invoke(iapsInput, autoisf)
  },

}

// const _consoleLog = (message) => {
//   window.webkit.messageHandlers.consoleLog.postMessage(message.join(" "));
// }
//
// window.addEventListener('error', function(event) {
//   window.webkit.messageHandlers.scriptError.postMessage("[JAVASCRIPT][GLOBAL ERROR]: " + event.message + " at " + event.filename + ":" + event.lineno);
// });

module.exports = iaps;

/// --------------
