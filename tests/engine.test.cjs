// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihnea Teodor Stoica

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const filename = path.join(__dirname, "../package/contents/ui/code/city.js");
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(filename, "utf8"), context, { filename });
vm.runInContext('Math.random = function () { throw new Error("Unseeded randomness"); };', context);
const createEngine = context.createEngine;
const journalNames = [
    "segmentFrom", "segmentTo", "segmentHue", "segmentColor", "segmentMain", "segmentCity", "segmentBranch"
];
const bufferNames = [
    "occupancy", ...journalNames, "segmentActive", "changeIds", "seedCells", "branchActive", "branchCells",
    "branchAges", "branchLives", "branchModes", "branchMain", "branchTurns"
];

function assertChanges(engine, operations, sign = 1) {
    assert.ok(engine.changeCount <= operations);
    assert.ok(engine.changeCount <= engine.changeIds.length);
    for (let i = 0; i < engine.changeCount; ++i) {
        const change = engine.changeIds[i];
        assert.equal(Math.sign(change), sign);
        const id = Math.abs(change) - 1;
        assert.ok(id >= 0 && id < engine.journalCount);
        assert.equal(engine.segmentActive[id], sign > 0 ? 1 : 0);
    }
}

function growUntilStopped(engine, budget = 4096) {
    let operations = 0;
    const bound = (engine.capacity + 32) * (engine.maxBacktrack + 4);
    while (engine.phase === "growing") {
        engine.queueGenerations(200);
        const count = engine.step(budget);
        assert.ok(count > 0 && count <= Math.min(budget, 4096));
        assertChanges(engine, count);
        operations += count;
        assert.ok(operations <= bound, "Growth must have a finite operation bound");
        assert.ok(engine.liveBranchCount <= 256);
        assert.ok(engine.occupiedCount <= engine.densityLimit);
    }
    assert.equal(engine.generationInProgress, false);
    assert.equal(engine.queuedGenerations, 0);
    assert.equal(engine.liveBranchCount, 0);
    return operations;
}

function drainQueued(engine, budget = 64) {
    let operations = 0;
    while (engine.generationInProgress || engine.queuedGenerations > 0) {
        const count = engine.step(budget);
        assert.ok(count > 0 && count <= Math.min(budget, 4096));
        operations += count;
        assert.ok(operations <= (engine.capacity + 32) * 304);
    }
    return operations;
}

function snapshot(engine) {
    const result = {
        columns: engine.columns,
        rows: engine.rows,
        phase: engine.phase,
        nextPhase: engine.nextPhase,
        seed: engine.seed,
        stopReason: engine.stopReason,
        occupiedCount: engine.occupiedCount,
        segmentCount: engine.segmentCount,
        journalCount: engine.journalCount,
        segmentActive: Array.from(engine.segmentActive.subarray(0, engine.journalCount)),
        generationCount: engine.generationCount,
        cycleOperationCount: engine.cycleOperationCount,
        backtrackOperations: engine.backtrackOperations,
        maxBacktrackDepth: engine.maxBacktrackDepth,
        seeds: Array.from(engine.seedCells.subarray(0, engine.seedCount)),
        occupancy: Array.from(engine.occupancy)
    };
    for (const name of journalNames)
        result[name] = Array.from(engine[name].subarray(0, engine.journalCount));
    return result;
}

function assertJournal(engine) {
    const seen = new Uint8Array(engine.capacity);
    const destinations = new Uint8Array(engine.capacity);
    const histories = new Map();
    let active = 0;
    for (let i = 0; i < engine.seedCount; ++i) {
        const cell = engine.seedCells[i];
        assert.ok(cell < engine.capacity);
        assert.equal(seen[cell], 0, "Seeds are claimed uniquely");
        seen[cell] = 1;
    }
    for (let i = 0; i < engine.journalCount; ++i) {
        const from = engine.segmentFrom[i];
        const to = engine.segmentTo[i];
        assert.ok(from < engine.capacity && to < engine.capacity);
        const dx = Math.abs(from % engine.columns - to % engine.columns);
        const dy = Math.abs(Math.floor(from / engine.columns) - Math.floor(to / engine.columns));
        assert.equal(dx + dy, 1, "Each segment is orthogonal without row wrapping");
        if (engine.segmentCount === engine.journalCount)
            assert.equal(seen[from], 1, "A growing source has already been claimed");
        assert.equal(destinations[to], 0, "Every destination has exactly one incoming segment");
        destinations[to] = 1;
        if (engine.segmentActive[i]) {
            assert.equal(seen[to], 0, "A destination never claims a seed");
            seen[to] = 1;
            ++active;
        }
        const root = engine.segmentBranch[i];
        if (!histories.has(root))
            histories.set(root, new Set([root]));
        assert.ok(histories.get(root).has(from), "Backtracking stays within the branch's own history");
        histories.get(root).add(to);
        assert.ok(engine.segmentHue[i] >= 0 && engine.segmentHue[i] <= 255);
        assert.ok(engine.segmentColor[i] >= 0 && engine.segmentColor[i] < 8);
        assert.ok(engine.segmentMain[i] === 0 || engine.segmentMain[i] === 1);
        assert.ok(engine.segmentCity[i] === 0 || engine.segmentCity[i] === 1);
    }
    assert.deepEqual(Array.from(engine.occupancy), Array.from(seen));
    assert.equal(active, engine.segmentCount);
    assert.equal(engine.occupiedCount, engine.segmentCount + engine.seedCount);
    assert.equal(engine.occupancy.reduce((sum, cell) => sum + cell, 0), engine.occupiedCount);
    assert.ok(engine.segmentCount <= engine.capacity);
    assert.ok(engine.peakBranchCount <= 256);
    assert.ok(engine.maxBacktrackDepth <= 300);
}

test("standard JS exposes instance-owned fixed numeric buffers", () => {
    assert.equal(typeof createEngine, "function");
    const engine = createEngine({}, 20, 30);
    const constructors = {
        occupancy: "Uint8Array", segmentFrom: "Uint32Array", segmentTo: "Uint32Array",
        segmentHue: "Uint16Array", segmentColor: "Uint8Array", segmentMain: "Uint8Array",
        segmentCity: "Uint8Array", segmentActive: "Uint8Array", segmentBranch: "Uint32Array", changeIds: "Int32Array"
    };
    for (const [name, constructor] of Object.entries(constructors)) {
        assert.equal(engine[name].constructor.name, constructor);
        assert.equal(engine[name].length, engine.capacity);
        assert.ok(ArrayBuffer.isView(engine[name]));
    }
    assert.equal(engine.branchActive.length, 256);
    assert.equal(engine.branchTurns.length, 256);
    assert.equal(engine.seedCells.length, 32);
    assert.equal(engine.effectiveScale, 3);
    assert.equal(engine.effectiveSpacing, 6);
    assert.equal(engine.branchLives[0], 8000);
    assertJournal(engine);
});

test("zero, subcell, invalid, and 1x1 dimensions are empty and stopped", () => {
    for (const [columns, rows] of [
        [0, 0], [0, 20], [20, 0], [0.9, 10], [-1, 4], [NaN, 4], [Infinity, 4], [1, 1]
    ]) {
        const engine = createEngine({}, columns, rows);
        assert.equal(engine.phase, "finished");
        assert.equal(engine.stopReason, "empty");
        assert.equal(engine.occupiedCount, 0);
        assert.equal(engine.segmentCount, 0);
        assert.equal(engine.seedCount, 0);
        assert.equal(engine.queueGenerations(100), 0);
        assert.equal(engine.step(4096), 0);
        assert.equal(engine.step(0), 0);
        assert.equal(engine.operationCount, 0);
        assert.equal(engine.advancePhase(), false);
        engine.reset(0);
        assert.equal(engine.phase, "finished");
        assert.equal(engine.seed, 0);
        assertJournal(engine);
    }
});

test("1xN and Nx1 reach both axis boundaries and fill without wrapping", () => {
    for (const length of [2, 3, 7, 97]) {
        for (const [columns, rows] of [[1, length], [length, 1]]) {
            const engine = createEngine({
                Seed: 7, InitialBranches: 1, BranchProbability: 0,
                StraightProbability: 0, EndMode: "hold"
            }, columns, rows);
            growUntilStopped(engine, 3);
            assert.equal(engine.phase, "finished");
            assert.equal(engine.stopReason, "density");
            assert.equal(engine.occupiedCount, length);
            assert.equal(engine.segmentCount, length - 1);
            assert.equal(engine.occupancy[0], 1);
            assert.equal(engine.occupancy[length - 1], 1);
            assertJournal(engine);
        }
    }
});

test("all four directions and every corner obey independent x/y bounds", () => {
    const directions = new Set();
    for (const [columns, rows] of [[2, 2], [3, 3], [2, 29], [29, 2]]) {
        for (let seed = 0; seed < 32; ++seed) {
            const engine = createEngine({
                Seed: seed, InitialBranches: 1, BranchProbability: 0,
                StraightProbability: 0, EndMode: "hold"
            }, columns, rows);
            growUntilStopped(engine);
            assert.equal(engine.occupiedCount, columns * rows);
            assertJournal(engine);
            for (let i = 0; i < engine.segmentCount; ++i) {
                const from = engine.segmentFrom[i];
                const to = engine.segmentTo[i];
                directions.add(`${to % columns - from % columns},${Math.floor(to / columns) - Math.floor(from / columns)}`);
            }
            for (const corner of [0, columns - 1, (rows - 1) * columns, columns * rows - 1])
                assert.equal(engine.occupancy[corner], 1);
        }
    }
    assert.deepEqual([...directions].sort(), ["-1,0", "0,-1", "0,1", "1,0"]);
});

test("crowded seed choices and simultaneous branch destinations never collide", () => {
    for (let seed = 0; seed < 16; ++seed) {
        const engine = createEngine({
            Seed: seed, InitialBranches: 32, BranchProbability: 0.5, EndMode: "hold"
        }, 8, 4);
        assert.equal(engine.seedCount, 31);
        assert.equal(new Set(engine.seedCells.subarray(0, engine.seedCount)).size, 31);
        assert.equal(engine.occupiedCount, 31);
        assertJournal(engine);
        growUntilStopped(engine, 1);
        assert.equal(engine.occupiedCount, 32);
        assert.equal(engine.segmentCount, 1);
        assertJournal(engine);
    }
    const engine = createEngine({
        Seed: 123, InitialBranches: 32, BranchProbability: 0.5, EndMode: "hold"
    }, 32, 32);
    growUntilStopped(engine, 31);
    assertJournal(engine);
});

test("capacity is capped by increasing effective scale, including extreme aspect ratios", () => {
    for (const [columns, rows] of [[4096, 4096], [2147483647, 1], [1, 2147483647]]) {
        const engine = createEngine({ Scale: 1 }, columns, rows);
        assert.ok(engine.columns >= 1 && engine.rows >= 1);
        assert.ok(engine.capacity > 0 && engine.capacity <= 262144);
        assert.equal(engine.capacity, engine.columns * engine.rows);
        assert.equal(engine.segmentFrom.length, engine.capacity);
        assert.equal(engine.occupancy.length, engine.capacity);
        assert.ok(engine.effectiveScale > 1 && Number.isFinite(engine.effectiveScale));
        assert.equal(engine.effectiveSpacing, 2 * engine.effectiveScale);
        assert.ok(engine.columns <= columns && engine.rows <= rows);
    }
    const unchanged = createEngine({ Scale: 4 }, 100, 20);
    assert.equal(unchanged.columns, 100);
    assert.equal(unchanged.rows, 20);
    assert.equal(unchanged.effectiveScale, 4);
});

test("identical seed/settings are deterministic across operation and callback budgets", () => {
    const options = {
        Seed: 271828, InitialBranches: 8, BranchProbability: 0.3,
        StraightProbability: 0.2, Density: 0.9, EndMode: "hold"
    };
    const small = createEngine(options, 61, 37);
    const large = createEngine(options, 61, 37);
    const smallOperations = growUntilStopped(small, 1);
    const largeOperations = growUntilStopped(large, 4096);
    assert.equal(smallOperations, largeOperations);
    assert.deepEqual(snapshot(small), snapshot(large));
    assertJournal(small);
});

test("concurrent instances, reconstruction, and reset do not share state or randomness", () => {
    const options = { Seed: 42, InitialBranches: 4, EndMode: "hold" };
    const first = createEngine(options, 37, 29);
    const second = createEngine(options, 37, 29);
    const control = createEngine(options, 37, 29);
    const untouched = snapshot(second);
    for (const name of bufferNames)
        assert.notEqual(first[name], second[name]);
    growUntilStopped(first);
    first.reset(99);
    createEngine(options, 3, 11).reset(3);
    assert.deepEqual(snapshot(second), untouched);
    growUntilStopped(second, 7);
    growUntilStopped(control, 121);
    assert.deepEqual(snapshot(second), snapshot(control));
    options.Seed = 1000;
    options.BranchProbability = 0;
    first.reset(42);
    growUntilStopped(first);
    assert.deepEqual(snapshot(first), snapshot(control), "Options are captured, not reread during reset");
});

test("one-operation budgets preserve the generation snapshot and fairly visit every branch", () => {
    const engine = createEngine({
        Seed: 12, InitialBranches: 32, BranchProbability: 0, StraightProbability: 0, EndMode: "hold"
    }, 256, 256);
    for (let generation = 1; generation <= 8; ++generation) {
        const eligible = [];
        for (let branch = 0; branch < 256; ++branch) {
            if (engine.branchActive[branch])
                eligible.push([branch, engine.branchTurns[branch]]);
        }
        assert.equal(engine.queueGenerations(1), 1);
        assert.equal(engine.step(1), 1);
        assert.equal(engine.generationInProgress, true);
        // A later callback with no new wall-clock generation must retain this one.
        engine.queueGenerations(0);
        let callbacks = 1;
        while (engine.generationCount < generation) {
            assert.equal(engine.step(1), 1);
            assertChanges(engine, 1);
            assert.ok(++callbacks <= 32 * 302);
        }
        for (const [branch, before] of eligible)
            assert.equal(engine.branchTurns[branch], before + 1);
        assert.equal(engine.queuedGenerations, 0);
        assert.equal(engine.generationInProgress, false);
        assert.equal(engine.step(4096), 0);
    }
    assertJournal(engine);
});

test("original generation ordering moves new offshoots immediately but branches them later", () => {
    let engine;
    for (let seed = 0; seed < 16; ++seed) {
        engine = createEngine({
            Seed: seed, InitialBranches: 32, BranchProbability: 0.5,
            StraightProbability: 0, EndMode: "hold"
        }, 256, 256);
        engine.queueGenerations(1);
        drainQueued(engine, 1);
        assert.equal(engine.liveBranchCount, 32, "Seeds do not branch before their first move");
        engine.queueGenerations(1);
        drainQueued(engine, 1);
        if (engine.liveBranchCount > 32)
            break;
    }
    assert.ok(engine.liveBranchCount > 32, "The fixture produces child branches");
    const children = [];
    let offshoots = 0;
    for (let branch = 0; branch < 256; ++branch) {
        if (!engine.branchActive[branch])
            continue;
        if (branch < 32) {
            assert.equal(engine.branchTurns[branch], 2);
            assert.equal(engine.branchLives[branch], 8000);
        } else {
            children.push(branch);
            assert.equal(engine.branchTurns[branch], 1);
            assert.equal(engine.branchAges[branch], 1);
            assert.equal(engine.branchLives[branch], engine.branchMain[branch] ? 8000 : 15);
            offshoots += engine.branchMain[branch] ? 0 : 1;
        }
    }
    assert.ok(offshoots > 0);
    engine.queueGenerations(1);
    drainQueued(engine, 1);
    for (const branch of children)
        assert.equal(engine.branchTurns[branch], 2);
    assertJournal(engine);
});

test("backtracking resumes one probe at a time and stops at exactly 300 inspected cells", () => {
    let engine;
    for (let seed = 0; seed < 256; ++seed) {
        engine = createEngine({
            Seed: seed, InitialBranches: 1, BranchProbability: 0,
            StraightProbability: 1, EndMode: "hold"
        }, 2048, 1);
        const root = engine.seedCells[0];
        if (root > 300 && root < 1747)
            break;
    }
    assert.ok(engine.seedCells[0] > 300 && engine.seedCells[0] < 1747);
    let callbacks = 0;
    while (!engine.backtracking) {
        assert.equal(engine.phase, "growing");
        engine.queueGenerations(200);
        assert.equal(engine.step(1), 1);
        assert.ok(++callbacks < 6000);
    }
    assert.equal(engine.maxBacktrackDepth, 1);
    const interrupted = snapshot(engine);
    engine.reset(engine.seed);
    assert.equal(engine.backtracking, false);
    assert.equal(engine.generationInProgress, false);
    assert.equal(engine.queuedGenerations, 0);
    assert.equal(engine.maxBacktrackDepth, 0);
    callbacks = 0;
    while (!engine.backtracking) {
        engine.queueGenerations(200);
        assert.equal(engine.step(1), 1);
        assert.ok(++callbacks < 6000);
    }
    assert.deepEqual(snapshot(engine), interrupted, "Reset clears and faithfully rebuilds a backtracking cursor");
    const segments = engine.segmentCount;
    const operations = engine.operationCount;
    engine.discardQueuedGenerations();
    assert.equal(engine.generationInProgress, true);
    for (let probe = 1; probe <= 299; ++probe) {
        assert.equal(engine.step(1), 1);
        assert.equal(engine.backtrackOperations, probe);
        assert.equal(engine.maxBacktrackDepth, probe + 1);
        assert.equal(engine.segmentCount, segments);
        assert.equal(engine.changeCount, 0);
        assert.equal(engine.backtracking, probe < 299);
    }
    assert.equal(engine.operationCount, operations + 299);
    assert.equal(engine.phase, "finished");
    assert.equal(engine.stopReason, "branches");
    assert.ok(engine.occupiedCount < engine.capacity);
    assert.equal(engine.step(4096), 0);
    assertJournal(engine);
});

test("density thresholds stop exactly, including a completely occupied grid", () => {
    for (const density of [0.1, 0.5, 1]) {
        const engine = createEngine({
            Seed: 0, InitialBranches: 1, BranchProbability: 0,
            StraightProbability: 0, Density: density, EndMode: "hold"
        }, 10, 10);
        growUntilStopped(engine, 7);
        assert.equal(engine.occupiedCount, Math.ceil(100 * density));
        assert.equal(engine.segmentCount, engine.occupiedCount - 1);
        assert.equal(engine.stopReason, "density");
        assert.equal(engine.phase, "finished");
        assert.equal(engine.budgetLimited, false);
        assertJournal(engine);
    }
});

test("high seed counts at low density leave room for visible growth", () => {
    for (const [columns, rows] of [[10, 10], [4, 4], [2, 1]]) {
        const engine = createEngine({ InitialBranches: 32, Density: 0.1 }, columns, rows);
        assert.equal(engine.phase, "growing");
        growUntilStopped(engine, 1);
        assert.ok(engine.segmentCount > 0, "A valid grid must not finish blank at its seed threshold");
        assert.equal(engine.phase, "holding");
        assertJournal(engine);
    }
});

test("CITY/straight metadata is historical while visual settings preserve geometry", () => {
    for (const probability of [0, 1]) {
        const engine = createEngine({
            Seed: 4, InitialBranches: 1, BranchProbability: 0,
            StraightProbability: probability, EndMode: "hold"
        }, 31, 31);
        engine.queueGenerations(1);
        drainQueued(engine);
        assert.equal(engine.segmentCount, 1);
        assert.equal(engine.segmentCity[0], probability === 0 ? 1 : 0);
        assert.equal(engine.segmentMain[0], 1);
    }
    const options = { Seed: 8, InitialBranches: 3, EndMode: "hold" };
    const first = createEngine(options, 29, 19);
    const second = createEngine({
        ...options, FillCity: false, FillOpacity: 0.9, LineWidth: 7,
        Palette: "ember", HueOffset: 180, BackgroundColor: "#ff0000", GrowthSpeed: 8, MaxFps: 1
    }, 29, 19);
    growUntilStopped(first);
    growUntilStopped(second);
    assert.deepEqual(snapshot(first), snapshot(second));
});

test("a single branch retraces its history, uses 50 segments per generation, and reaches zero", () => {
    const engine = createEngine({
        Seed: 6, InitialBranches: 1, BranchProbability: 0,
        StraightProbability: 0, EndMode: "reverse"
    }, 257, 1);
    growUntilStopped(engine);
    assert.equal(engine.phase, "holding");
    assert.equal(engine.nextPhase, "reversing");
    assert.equal(engine.segmentCount, 256);
    const grown = snapshot(engine);
    const journal = Object.fromEntries(journalNames.map(name => [name, Array.from(engine[name]) ]));
    const buffers = bufferNames.map(name => engine[name]);
    const serial = engine.resetSerial;
    const operations = engine.operationCount;
    assert.equal(engine.queueGenerations(200), 0);
    assert.equal(engine.step(4096), 0);
    assert.equal(engine.operationCount, operations);
    assert.equal(engine.advancePhase(999), true);
    assert.equal(engine.seed, 6, "The reverse transition does not randomize the seed");
    assert.equal(engine.phase, "reversing");
    const beforeGeneration = engine.generationCount;
    const removed = [];
    engine.queueGenerations(1);
    assert.equal(engine.step(7), 7);
    assert.equal(engine.generationInProgress, true);
    removed.push(...engine.changeIds.subarray(0, engine.changeCount));
    assertChanges(engine, 7, -1);
    assert.equal(engine.segmentCount, 249);
    engine.queueGenerations(0);
    assert.equal(engine.step(4096), 43);
    removed.push(...engine.changeIds.subarray(0, engine.changeCount));
    assert.equal(engine.segmentCount, 206);
    assert.equal(engine.generationCount, beforeGeneration + 1);
    assert.equal(engine.generationInProgress, false);
    assert.equal(engine.step(4096), 0);
    while (engine.phase === "reversing") {
        const before = engine.segmentCount;
        engine.queueGenerations(1);
        const count = engine.step(4096);
        assert.equal(count, Math.min(50, before));
        assertChanges(engine, count, -1);
        removed.push(...engine.changeIds.subarray(0, engine.changeCount));
        for (const name of journalNames)
            assert.deepEqual(Array.from(engine[name].subarray(0, engine.journalCount)), journal[name].slice(0, engine.journalCount));
        assertJournal(engine);
    }
    assert.deepEqual(removed, Array.from({ length: 256 }, (_, i) => -(256 - i)));
    assert.equal(engine.generationCount, beforeGeneration + Math.ceil(256 / 50));
    assert.equal(engine.phase, "holding");
    assert.equal(engine.nextPhase, "growing");
    assert.equal(engine.segmentCount, 0);
    assert.equal(engine.occupiedCount, 0);
    assert.equal(engine.seedCount, 0);
    assert.equal(engine.resetSerial, serial);
    assert.equal(engine.advancePhase(), true);
    assert.equal(engine.resetSerial, serial + 1);
    for (let i = 0; i < bufferNames.length; ++i)
        assert.equal(engine[bufferNames[i]], buffers[i]);
    growUntilStopped(engine);
    assert.deepEqual(snapshot(engine), grown, "An unchanged cycle seed repeats exactly");
});

test("reverse retracts old offshoots alongside recent branches without crossing histories", () => {
    const options = { Seed: 19, InitialBranches: 3, BranchProbability: 0.05, Density: 0.3 };
    const engine = createEngine(options, 60, 40);
    growUntilStopped(engine);
    const histories = new Map();
    for (let id = 0; id < engine.journalCount; ++id) {
        const root = engine.segmentBranch[id];
        if (!histories.has(root)) histories.set(root, []);
        histories.get(root).push(id);
    }
    assert.ok(histories.size >= 4 && histories.size <= 50, "Fixture includes old offshoots within one reverse generation");
    const tips = [...histories.values()].map(history => history.at(-1));
    const removed = new Set();
    engine.advancePhase();
    engine.queueGenerations(1);
    assert.equal(engine.step(4096), 50);
    function consume() {
        for (let i = 0; i < engine.changeCount; ++i) {
            const id = -engine.changeIds[i] - 1;
            assert.ok(!removed.has(id), "No primitive is removed twice");
            removed.add(id);
            assert.equal(histories.get(engine.segmentBranch[id]).pop(), id, "Each branch retreats from its own tip");
        }
        assertJournal(engine);
    }
    consume();
    for (const tip of tips)
        assert.ok(removed.has(tip), "Old offshoots start retracting while long branches are still present");
    while (engine.phase === "reversing") {
        engine.queueGenerations(1);
        engine.step(7);
        consume();
    }
    assert.equal(removed.size, engine.journalCount);
    assert.equal(engine.segmentCount, 0);
    assert.equal(engine.occupiedCount, 0);
    engine.reset(options.Seed);
    growUntilStopped(engine);
    assertJournal(engine);
});

test("clear and hold phases require no JS clock and advance only on explicit release", () => {
    const clearing = createEngine({
        Seed: 1, InitialBranches: 1, BranchProbability: 0, EndMode: "clear"
    }, 7, 7);
    growUntilStopped(clearing);
    assert.equal(clearing.phase, "holding");
    assert.equal(clearing.nextPhase, "growing");
    const serial = clearing.resetSerial;
    const phaseSerial = clearing.phaseSerial;
    const counter = clearing.operationCount;
    const saved = snapshot(clearing);
    for (let i = 0; i < 5; ++i) {
        assert.equal(clearing.queueGenerations(200), 0);
        assert.equal(clearing.step(4096), 0);
    }
    assert.deepEqual(snapshot(clearing), saved);
    assert.equal(clearing.advancePhase(42), true);
    assert.equal(clearing.phase, "growing");
    assert.equal(clearing.seed, 42);
    assert.equal(clearing.segmentCount, 0);
    assert.equal(clearing.resetSerial, serial + 1);
    assert.ok(clearing.phaseSerial > phaseSerial);
    assert.equal(clearing.operationCount, counter);
    assert.equal(clearing.cycleOperationCount, 0);
    const holding = createEngine({
        Seed: 1, InitialBranches: 1, BranchProbability: 0, EndMode: "hold"
    }, 7, 7);
    growUntilStopped(holding);
    assert.equal(holding.phase, "finished");
    const finished = snapshot(holding);
    assert.equal(holding.advancePhase(999), false);
    assert.equal(holding.queueGenerations(200), 0);
    assert.equal(holding.step(4096), 0);
    assert.deepEqual(snapshot(holding), finished);
});

test("reset reuses buffers and clears partial generation, backtracking, and old history", () => {
    const options = { Seed: 17, InitialBranches: 5, BranchProbability: 0.2, EndMode: "hold" };
    const engine = createEngine(options, 19, 23);
    const buffers = bufferNames.map(name => engine[name]);
    growUntilStopped(engine);
    const first = snapshot(engine);
    const operations = engine.operationCount;
    const serial = engine.resetSerial;
    assert.equal(engine.reset(17), engine);
    assert.equal(engine.resetSerial, serial + 1);
    assert.equal(engine.changeCount, 0);
    assert.equal(engine.generationCount, 0);
    for (let i = 0; i < bufferNames.length; ++i)
        assert.equal(engine[bufferNames[i]], buffers[i]);
    growUntilStopped(engine, 13);
    assert.deepEqual(snapshot(engine), first);
    assert.equal(engine.operationCount, operations * 2);
    engine.reset(19);
    engine.queueGenerations(200);
    assert.equal(engine.step(1), 1);
    assert.equal(engine.generationInProgress, true);
    engine.reset(100);
    const fresh = createEngine({ ...options, Seed: 100 }, 19, 23);
    assert.deepEqual(snapshot(engine), snapshot(fresh));
    assert.equal(engine.generationInProgress, false);
    assert.equal(engine.queuedGenerations, 0);
    assert.equal(engine.backtracking, false);
    growUntilStopped(engine, 5);
    growUntilStopped(fresh);
    assert.deepEqual(snapshot(engine), snapshot(fresh));
    assertJournal(engine);
});

test("high branch pressure stays within the fixed live-branch and history buffers", () => {
    const engine = createEngine({
        Seed: 100, InitialBranches: 32, BranchProbability: 0.5,
        StraightProbability: 0, EndMode: "hold"
    }, 256, 256);
    const buffers = bufferNames.map(name => engine[name]);
    engine.queueGenerations(200);
    let operations = 0;
    while (engine.generationInProgress || engine.queuedGenerations > 0) {
        const count = engine.step(64);
        assert.ok(count > 0 && count <= 64);
        operations += count;
        assert.ok(operations <= (engine.capacity + 32) * 304);
        assertChanges(engine, count);
        assert.ok(engine.liveBranchCount <= 256);
        assert.ok(engine.peakBranchCount <= 256);
        assert.equal(engine.branchActive.reduce((sum, value) => sum + value, 0), engine.liveBranchCount);
        for (let branch = 0; branch < 256; ++branch) {
            if (engine.branchActive[branch])
                assert.ok(engine.branchAges[branch] < engine.branchLives[branch]);
        }
    }
    assert.ok(engine.peakBranchCount > 32);
    for (let i = 0; i < bufferNames.length; ++i)
        assert.equal(engine[bufferNames[i]], buffers[i]);
    assertJournal(engine);
});

test("queued wall-clock work is replaceable and operation budgets take precedence", () => {
    const engine = createEngine({
        Seed: 4, InitialBranches: 1, BranchProbability: 0, StraightProbability: 0, EndMode: "hold"
    }, 256, 256);
    assert.equal(engine.queueGenerations(1e12), 200);
    assert.equal(engine.step(1), 1);
    assert.equal(engine.budgetLimited, true);
    assert.equal(engine.queuedGenerations, 199);
    assert.equal(engine.queueGenerations(3), 3);
    engine.discardQueuedGenerations();
    assert.equal(engine.queuedGenerations, 0);
    assert.equal(engine.generationInProgress, true);
    assert.equal(engine.step(1), 1);
    assert.equal(engine.generationCount, 1);
    assert.equal(engine.generationInProgress, false);
    assert.equal(engine.budgetLimited, false);
    assert.equal(engine.step(4096), 0);
    for (const invalid of [-1, 0, NaN, Infinity, "5"])
        assert.equal(engine.queueGenerations(invalid), 0);
    for (const invalid of [-1, 0, NaN, Infinity, "5"])
        assert.equal(engine.step(invalid), 0);
    const busy = createEngine({
        Seed: 4, InitialBranches: 32, BranchProbability: 0, EndMode: "hold"
    }, 256, 256);
    busy.queueGenerations(200);
    assert.equal(busy.step(1e12), 4096);
    assert.equal(busy.budgetLimited, true);
    assert.ok(busy.generationInProgress || busy.queuedGenerations > 0);
    assertChanges(busy, 4096);
    assertJournal(busy);
});
