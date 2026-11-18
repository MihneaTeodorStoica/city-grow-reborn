// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihnea Teodor Stoica
// Shared by QML and the Node VM tests; never executes imported text.
var schema = {
    Preset: {type:'string', value:'Original', choices:['Original','Aurora','Ember','Monochrome','Custom']},
    BackgroundMode: {type:'string', value:'solid', choices:['solid','gradient','image']},
    BackgroundColor: {type:'color', value:'#000000'},
    BackgroundColor2: {type:'color', value:'#101827'},
    BackgroundImage: {type:'file', value:''},
    Palette: {type:'string', value:'original', choices:['original','aurora','ember','monochrome','custom']},
    CustomColors: {type:'colors', value:'["#66e3c4","#76a9fa","#bb9af7","#e0af68"]'},
    HueOffset: {type:'int', value:0, min:0, max:359},
    Scale: {type:'int', value:3, min:1, max:16},
    LineWidth: {type:'double', value:2, min:0.5, max:8},
    FillCity: {type:'bool', value:true},
    FillOpacity: {type:'double', value:0.25, min:0, max:1},
    GrowthSpeed: {type:'double', value:1, min:0.1, max:8},
    InitialBranches: {type:'int', value:3, min:1, max:32},
    BranchProbability: {type:'double', value:0.15, min:0, max:0.5},
    StraightProbability: {type:'double', value:0.12, min:0, max:1},
    Density: {type:'double', value:1, min:0.1, max:1},
    Seed: {type:'int', value:1, min:0, max:2147483647},
    RandomizeEachCycle: {type:'bool', value:true},
    EndMode: {type:'string', value:'reverse', choices:['reverse','clear','hold']},
    CycleDelay: {type:'double', value:1, min:0, max:300},
    VisibilityMode: {type:'string', value:'adaptive', choices:['adaptive','always']},
    Paused: {type:'bool', value:false},
    MaxFps: {type:'int', value:15, min:1, max:30},
    PartialFps: {type:'int', value:5, min:1, max:30},
    CheckDisplayPower: {type:'bool', value:true},
    DisplayPowerInterval: {type:'int', value:5, min:1, max:30}
};
var presetKeys = ['Palette','HueOffset','Scale','LineWidth','FillCity','FillOpacity','GrowthSpeed','InitialBranches','BranchProbability','StraightProbability','Density','EndMode','CycleDelay'];
function defaults() {
    var result = {};
    Object.keys(schema).forEach(function(key) { result[key] = schema[key].value; });
    return result;
}
function preset(name) {
    var result = {}, base = defaults();
    presetKeys.forEach(function(key) { result[key] = base[key]; });
    if (name === 'Aurora') {
        result.Palette = 'aurora'; result.GrowthSpeed = 0.6; result.InitialBranches = 4; result.BranchProbability = 0.10;
    } else if (name === 'Ember') {
        result.Palette = 'ember'; result.GrowthSpeed = 1.2; result.InitialBranches = 5; result.StraightProbability = 0.18;
    } else if (name === 'Monochrome') {
        result.Palette = 'monochrome'; result.GrowthSpeed = 0.5; result.LineWidth = 1.5; result.FillCity = false; result.BranchProbability = 0.08;
    } else if (name !== 'Original') {
        return null;
    }
    result.Preset = name;
    return result;
}
function localImage(value) {
    return value === '' || (/^file:\/\/\//.test(value) && !/[\u0000-\u001f?#]/.test(value));
}
function validateValue(key, value) {
    var rule = schema[key];
    if (!rule) return 'Unknown setting: ' + key;
    if (rule.type === 'bool') return typeof value === 'boolean' ? '' : key + ' must be boolean';
    if (rule.type === 'int' || rule.type === 'double') {
        if (typeof value !== 'number' || !isFinite(value) || value < rule.min || value > rule.max || (rule.type === 'int' && Math.floor(value) !== value))
            return key + ' is outside its allowed range';
        return '';
    }
    if (typeof value !== 'string') return key + ' must be a string';
    if (rule.choices && rule.choices.indexOf(value) < 0) return key + ' has an unsupported value';
    if (rule.type === 'color' && !/^#[0-9a-fA-F]{6}$/.test(value)) return key + ' requires an opaque #RRGGBB color';
    if (rule.type === 'file' && !localImage(value)) return 'BackgroundImage requires a local file URL';
    if (rule.type === 'colors') {
        try {
            var colors = JSON.parse(value);
            if (!Array.isArray(colors) || colors.length < 2 || colors.length > 8 || !colors.every(function(c) { return typeof c === 'string' && /^#[0-9a-fA-F]{6}$/.test(c); }))
                return 'CustomColors requires 2–8 opaque #RRGGBB colors';
        } catch (e) { return 'CustomColors is not a JSON color array'; }
    }
    return '';
}
function parseRecipe(text) {
    function fail(message) { return {ok:false, settings:null, error:message}; }
    if (typeof text !== 'string' || text.length > 65536) return fail('Recipe exceeds 64KiB');
    var bytes = 0;
    for (var i = 0; i < text.length; ++i) {
        var c = text.charCodeAt(i);
        bytes += c < 128 ? 1 : c < 2048 ? 2 : c >= 0xd800 && c <= 0xdbff && i + 1 < text.length && text.charCodeAt(i+1) >= 0xdc00 && text.charCodeAt(i+1) <= 0xdfff ? (++i, 4) : 3;
        if (bytes > 65536) return fail('Recipe exceeds 64KiB');
    }
    var recipe;
    try { recipe = JSON.parse(text); } catch (e) { return fail('Invalid JSON'); }
    if (!recipe || Array.isArray(recipe) || typeof recipe !== 'object' || recipe.version !== 1) return fail('Unsupported recipe version');
    if (Object.keys(recipe).some(function(key) { return key !== 'version' && key !== 'settings'; })) return fail('Unknown recipe field');
    var values = recipe.settings;
    if (!values || typeof values !== 'object' || Array.isArray(values)) return fail('Missing settings object');
    var keys = Object.keys(values), required = Object.keys(schema), result = {};
    for (i = 0; i < keys.length; ++i) {
        var key = keys[i];
        if (!Object.prototype.hasOwnProperty.call(schema,key)) return fail('Unknown setting: ' + key);
        var error = validateValue(key, values[key]);
        if (error) return fail(error);
        result[key] = values[key];
    }
    if (keys.length !== required.length) return fail('Recipe must contain every documented setting');
    return {ok:true, settings:result, error:''};
}
function exportRecipe(settings) {
    var result = {};
    Object.keys(schema).forEach(function(key) { result[key] = settings[key]; });
    var text = JSON.stringify({version:1, settings:result}, null, 2);
    var checked = parseRecipe(text);
    if (!checked.ok) throw new Error(checked.error);
    return text;
}
