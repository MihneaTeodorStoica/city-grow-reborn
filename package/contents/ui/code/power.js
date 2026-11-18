// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Mihnea Teodor Stoica

// kscreen-doctor reports one line per output, e.g.
// "dpms mode for screen DP-2: on". Anything unrecognized stays unknown;
// in particular, a failed or incomplete probe must not pause an output.
function parseDisplayPower(text, expectedOutputs) {
    var states = Object.create(null);
    var conflicted = Object.create(null);
    var lines = String(text || "").split(/\r?\n/);
    var matched = false;
    for (var i = 0; i < lines.length; ++i) {
        var match = /^\s*dpms mode for screen (.+?):\s*(.*?)\s*$/i.exec(lines[i]);
        if (!match) continue;
        matched = true;
        var name = match[1].trim();
        var mode = match[2].toLowerCase();
        var state = mode === "on" || mode === "off" ? mode : "unknown";
        if (Object.prototype.hasOwnProperty.call(states, name) && states[name] !== state)
            conflicted[name] = true;
        states[name] = conflicted[name] ? "unknown" : state;
    }
    var unknownOutputs = [];
    var expected = expectedOutputs || [];
    for (var j = 0; j < expected.length; ++j) {
        var output = String(expected[j]);
        if (!Object.prototype.hasOwnProperty.call(states, output)) states[output] = "unknown";
        if (states[output] === "unknown" && unknownOutputs.indexOf(output) < 0)
            unknownOutputs.push(output);
    }
    var warning = !matched || unknownOutputs.length > 0;
    var names = Object.keys(states);
    for (var k = 0; k < names.length; ++k)
        if (states[names[k]] === "unknown") warning = true;
    return { states: states, unknownOutputs: unknownOutputs, warning: warning };
}
