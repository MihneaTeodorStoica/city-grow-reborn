// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Mihnea Teodor Stoica

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

function loadSource(relativePath) {
    const filename = path.resolve(__dirname, '..', relativePath);
    const context = vm.createContext({});
    vm.runInContext(fs.readFileSync(filename, 'utf8'), context, { filename });
    return context;
}

const coverage = loadSource('kwin-script/contents/code/coverage.js');
const power = loadSource('package/contents/ui/code/power.js');
const area = { x: 0, y: 0, width: 100, height: 100 };
const desktop = { id: 'desktop-one' };

function windowAt(rectangle, overrides = {}) {
    return {
        normalWindow: true,
        dialog: false,
        desktopWindow: false,
        dock: false,
        minimized: false,
        hidden: false,
        opacity: 1,
        activities: [],
        desktops: [],
        frameGeometry: rectangle,
        ...overrides,
    };
}

function classify(windows, output = area, currentDesktop = desktop, activity = 'activity-one') {
    return coverage.coverageForOutput(output, windows, currentDesktop, activity);
}

function plain(value) {
    return JSON.parse(JSON.stringify(value));
}

test('rectangle union merges overlap instead of summing windows', () => {
    assert.equal(coverage.rectangleUnionArea([]), 0);
    assert.equal(coverage.rectangleUnionArea([
        { x: 0, y: 0, width: 50, height: 100 },
        { x: 50, y: 0, width: 50, height: 100 },
    ]), 10000);
    assert.equal(coverage.rectangleUnionArea([
        { x: 0, y: 0, width: 50, height: 100 },
        { x: 0, y: 0, width: 50, height: 100 },
    ]), 5000);
    assert.equal(coverage.rectangleUnionArea([
        { x: 0, y: 0, width: 70, height: 100 },
        { x: 30, y: 0, width: 70, height: 100 },
        { x: 40, y: 40, width: 20, height: 20 },
    ]), 10000);
    assert.equal(coverage.rectangleUnionArea([
        { x: 0, y: 0, width: 10, height: 10 },
        { x: 0, y: 20, width: 10, height: 10 },
        { x: 20, y: 0, width: 10, height: 10 },
    ]), 300);
});

test('adjacent tiled windows cover, identical half windows remain partial', () => {
    assert.equal(classify([
        windowAt({ x: 0, y: 0, width: 50, height: 100 }),
        windowAt({ x: 50, y: 0, width: 50, height: 100 }),
    ]).state, 'covered');
    assert.equal(classify([
        windowAt({ x: 0, y: 0, width: 50, height: 100 }),
        windowAt({ x: 0, y: 0, width: 50, height: 100 }),
    ]).state, 'partial');
});

for (const [percent, state] of [[0, 'visible'], [49, 'visible'], [50, 'partial'],
    [97, 'partial'], [98, 'covered'], [100, 'covered']]) {
    test(`coverage threshold ${percent}% is ${state}`, () => {
        const windows = percent === 0 ? [] : [windowAt({ ...area, width: percent })];
        const result = classify(windows);
        assert.equal(result.state, state);
        assert.equal(result.ratio, percent / 100);
    });
}

test('each axis clips independently to the usable output rectangle', () => {
    const output = { x: 20, y: 30, width: 100, height: 100 };
    assert.equal(classify([windowAt({ x: -100, y: -100, width: 500, height: 500 })], output).ratio, 1);
    assert.equal(classify([windowAt({ x: -30, y: 30, width: 100, height: 100 })], output).ratio, 0.5);
    assert.equal(classify([windowAt({ x: 70, y: 30, width: 100, height: 100 })], output).ratio, 0.5);
    assert.equal(classify([windowAt({ x: 20, y: -20, width: 100, height: 100 })], output).ratio, 0.5);
    assert.equal(classify([windowAt({ x: 20, y: 80, width: 100, height: 100 })], output).ratio, 0.5);
    assert.equal(classify([windowAt({ x: 120, y: 30, width: 10, height: 100 })], output).ratio, 0);
    assert.equal(classify([windowAt({ x: 20, y: 130, width: 100, height: 10 })], output).ratio, 0);
});

test('spanning windows intersect each output, independent of their output property', () => {
    const spanning = windowAt({ x: 50, y: 0, width: 100, height: 100 }, { output: 'left' });
    assert.equal(classify([spanning]).ratio, 0.5);
    assert.equal(classify([spanning], { ...area, x: 100 }, { id: 'desktop-two' }).ratio, 0.5);
});

for (const overrides of [
    { minimized: true },
    { hidden: true },
    { desktopWindow: true },
    { dock: true },
    { normalWindow: false, dialog: false },
    { opacity: 0.998 },
    { opacity: 0 },
    { opacity: NaN },
    { activities: ['activity-two'] },
    { desktops: [{ id: 'desktop-two' }] },
]) {
    test(`ineligible full window does not cover: ${JSON.stringify(overrides)}`, () => {
        assert.equal(classify([windowAt(area, overrides)]).state, 'visible');
    });
}

test('normal/dialog windows and scalar opacity boundary are eligible', () => {
    assert.equal(classify([windowAt(area, { normalWindow: false, dialog: true })]).state, 'covered');
    assert.equal(classify([windowAt(area, { opacity: 0.999 })]).state, 'covered');
});

test('empty memberships mean all; desktop IDs and all-desktop flag match correctly', () => {
    assert.equal(classify([windowAt(area)]).state, 'covered');
    assert.equal(classify([windowAt(area, { desktops: [{ id: desktop.id }] })]).state, 'covered');
    assert.equal(classify([windowAt(area, { desktops: [desktop.id] })]).state, 'covered');
    assert.equal(classify([windowAt(area, { desktops: ['other'], onAllDesktops: true })]).state, 'covered');
    assert.equal(classify([windowAt(area, { activities: ['other', 'activity-one'] })]).state, 'covered');
});

test('invalid usable or eligible-window geometry fails open', () => {
    for (const invalid of [
        { ...area, width: 0 }, { ...area, height: -1 },
        { ...area, x: NaN }, { ...area, y: Infinity },
    ]) {
        assert.equal(classify([windowAt(area)], invalid).state, 'visible');
        const result = classify([windowAt(invalid)]);
        assert.equal(result.state, 'visible');
        assert.equal(result.reason, 'invalid-window');
    }
    assert.equal(classify([
        windowAt({ ...area, width: 0 }, { minimized: true }), windowAt(area),
    ]).state, 'covered');
});

test('candidate count is bounded and never falsely pauses on overflow', () => {
    const half = windowAt({ ...area, width: 50 });
    assert.equal(classify(Array(256).fill(half)).state, 'partial');
    const overflow = classify(Array(257).fill(windowAt(area)));
    assert.equal(overflow.state, 'visible');
    assert.equal(overflow.reason, 'window-limit');
});

test('DPMS parser accepts the observed output and explicit off independently', () => {
    const result = power.parseDisplayPower(
        'dpms mode for screen DP-2: on\ndpms mode for screen eDP-1: off\n', ['DP-2', 'eDP-1']);
    assert.deepEqual(plain(result.states), { 'DP-2': 'on', 'eDP-1': 'off' });
    assert.equal(result.warning, false);
    assert.deepEqual(plain(result.unknownOutputs), []);
});

test('DPMS parser handles harmless whitespace and unrelated diagnostics', () => {
    const result = power.parseDisplayPower(
        'unrelated status message\r\n  dpms mode for screen DP-2: ON  \r\n', ['DP-2']);
    assert.equal(result.states['DP-2'], 'on');
    assert.equal(result.warning, false);
});

test('missing, malformed, or unsupported DPMS output stays unknown, never off', () => {
    for (const text of ['', 'command failed', 'dpms mode for screen DP-2: standby',
        'dpms mode for screen DP-2: off trailing-junk', 'dpms mode for screen DP-2 on']) {
        const result = power.parseDisplayPower(text, ['DP-2']);
        assert.equal(result.states['DP-2'], 'unknown');
        assert.equal(result.warning, true);
        assert.deepEqual(plain(result.unknownOutputs), ['DP-2']);
    }
    const missing = power.parseDisplayPower('dpms mode for screen DP-2: on', ['DP-2', 'eDP-1']);
    assert.equal(missing.states['DP-2'], 'on');
    assert.equal(missing.states['eDP-1'], 'unknown');
    assert.equal(missing.warning, true);
});

test('conflicting duplicate DPMS lines remain unknown even if followed by on', () => {
    const conflict = power.parseDisplayPower(
        'dpms mode for screen DP-2: off\ndpms mode for screen DP-2: on\ndpms mode for screen DP-2: on', ['DP-2']);
    assert.equal(conflict.states['DP-2'], 'unknown');
    assert.equal(conflict.warning, true);
    const repeated = power.parseDisplayPower(
        'dpms mode for screen DP-2: off\ndpms mode for screen DP-2: off', ['DP-2']);
    assert.equal(repeated.states['DP-2'], 'off');
    assert.equal(repeated.warning, false);
});
