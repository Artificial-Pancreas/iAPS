var require = function(arg) { return function(basal, profile) { return basal; }; };
var module = {};
var logError = "";
var process = { stderr: { write: console.log } };
var freeaps = {};
