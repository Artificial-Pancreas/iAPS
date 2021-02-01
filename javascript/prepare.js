//var require = function(arg) {
//    return function(basal, profile) { return basal; };
//};

var exports = {};
var module = {
    exports: {}
};
var freeaps = {
    log: ""
};

freeaps.print = function(...args) {
    args.forEach(element => freeaps.log += JSON.stringify(element) + " ");
    freeaps.log += "\n";
}

var process = { stderr: { write: freeaps.print } };
var console = { log: freeaps.print, error: freeaps.print };
