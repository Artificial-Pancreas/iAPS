const invoke = require('./native-bridge')

const autosens = require('./autosens')
const meal = require('./meal')
const iob = require('./iob')
const determine_basal = require('./determine-basal')
const autotune = require('./autotune')
const profile = require('./profile')
const middleware = require('./middleware')
const autoisf = require('./autoisf')

const iaps = {

  invoke(functionName, iapsInput) {
    switch (functionName) {
      case 'autosens':
        return invoke(iapsInput, autosens)
      case 'meal':
        return invoke(iapsInput, meal)
      case 'iob':
        return invoke(iapsInput, iob)
      case 'determine_basal':
        return invoke(iapsInput, determine_basal)
      case 'autotune':
        return invoke(iapsInput, autotune)
      case 'profile':
        return invoke(iapsInput, profile)
      case 'middleware':
        return invoke(iapsInput, middleware)
      case 'autoisf':
        return invoke(iapsInput, autoisf)

      default:
        return JSON.stringify({
          script_error: `unknown function: ${functionName}`
        })
    }
  }

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

