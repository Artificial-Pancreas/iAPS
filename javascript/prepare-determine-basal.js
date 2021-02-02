var freeapsLog = ""
var printLog = function(...args) {
    args.forEach(element => freeapsLog.log += JSON.stringify(element) + " ");
    freeapsLog += "\n";
}

tempBasalFunctions = freeaps;

var process = { stderr: { write: printLog } };
var console = { log: freeaps.print, error: printLog };
