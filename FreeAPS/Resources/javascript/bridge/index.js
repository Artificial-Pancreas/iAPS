const autosens = require('prepare/autosens')
const meal = require('prepare/meal')
const iob = require('prepare/iob')
const determine_basal = require('prepare/determine-basal')
const autotune = require('prepare/autotune')
const profile = require('prepare/profile')
const middleware = require('prepare/middleware')
const autoisf = require('autoisf/autoisf')

const invoke = (input, call) => {
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

