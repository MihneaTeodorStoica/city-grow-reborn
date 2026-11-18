// The MIT License
// 
// Copyright (c) 2024 Felix Lemke
// Copyright (c) 2026 Mihnea Teodor Stoica
// 
// Permission is hereby granted, free of charge, 
// to any person obtaining a copy of this software and 
// associated documentation files (the "Software"), to 
// deal in the Software without restriction, including 
// without limitation the rights to use, copy, modify, 
// merge, publish, distribute, sublicense, and/or sell 
// copies of the Software, and to permit persons to whom 
// the Software is furnished to do so, 
// subject to the following conditions:
// 
// The above copyright notice and this permission notice 
// shall be included in all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, 
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES 
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR 
// ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, 
// TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
// SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

/*
 * Deterministic, allocation-free-per-operation simulation. Options use the
 * documented General setting names. Visual-only settings do not affect growth.
 *
 * Renderer contract (all buffers belong to this engine and survive reset):
 * - occupancy: Uint8Array, one immediately claimed entry per occupied cell.
 * - segmentFrom/segmentTo: Uint32Array cell IDs, x=id%columns, y=floor(id/columns).
 * - segmentHue: Uint16Array, original hue range 0..255; apply HueOffset at paint.
 * - segmentColor: Uint8Array palette slot; reduce modulo the current palette size.
 * - segmentMain: Uint8Array, 1 for main/light branches, 0 for short/dark offshoots.
 * - segmentCity: Uint8Array, 1 for CITY (adjacent block-fill candidates), 0 for
 *   LAND/straight-run. FillCity and FillOpacity remain renderer-only decisions.
 * journalCount is the chronological journal length; segmentCount counts its
 * surviving entries. segmentActive marks survivors during branch-wise reversal.
 * changeIds[0..changeCount) contains +(segmentId+1) for additions and
 * -(segmentId+1) for removals. Consume it after each step; the next step replaces
 * it. reset increments resetSerial instead of publishing an enormous clear list.
 *
 * queueGenerations REPLACES the unstarted queue, capped at 200 (one second at
 * maximum supported speed). It never discards an unfinished generation. Call it
 * once per active scheduler callback, then step in bounded chunks; discard any
 * unstarted remainder with discardQueuedGenerations after the callback's time
 * budget expires. No elapsed time, timers, or Math.random are used here.
 *
 * Each generation branches its existing population, then moves all live branches,
 * including new children, as in the original. Backtracking costs one operation
 * per inspected cell (at most 300). Reverse visits branch histories round-robin,
 * costing one operation per removal, with 50 removals per generation.
 * step never exceeds 4096 operations. Children cannot branch until a later
 * generation and backtracking never crosses their inherited junction.
 *
 * phase is growing, holding, reversing, or finished. During holding, nextPhase
 * is reversing or growing. The owner supplies its single-shot delay, then calls
 * advancePhase(seed). Only a transition to growing uses that optional new seed.
 * reset(seed) also works directly and reuses every allocated buffer. Empty/tiny
 * grids finish without a timer. phaseSerial distinguishes phase transitions.
 */
function createEngine(options, columns, rows) {
    options = options || {};

    var maximumCells = 262144;
    var maximumBranches = 256;
    var maximumSeeds = 32;
    var maximumBacktrack = 300;
    var maximumOperations = 4096;
    var maximumQueuedGenerations = 200;
    var mainLifetime = 8000;
    var offshootLifetime = 15;

    function numericOption(name, fallback, minimum, maximum) {
        var value = options[name];
        return typeof value === "number" && isFinite(value)
            ? Math.max(minimum, Math.min(maximum, value)) : fallback;
    }

    function dimension(value) {
        return typeof value === "number" && isFinite(value)
            ? Math.max(0, Math.min(2147483647, Math.floor(value))) : 0;
    }

    function normalizedSeed(value, fallback) {
        return typeof value === "number" && isFinite(value)
            ? Math.max(0, Math.min(2147483647, Math.floor(value))) : fallback;
    }

    var requestedColumns = dimension(columns);
    var requestedRows = dimension(rows);
    var scale = numericOption("Scale", 3, 1, 16);
    columns = requestedColumns;
    rows = requestedRows;
    if (columns === 0 || rows === 0) {
        columns = 0;
        rows = 0;
    } else if (columns * rows > maximumCells) {
        var reduction = Math.sqrt(columns * rows / maximumCells);
        columns = Math.max(1, Math.floor(columns / reduction));
        rows = Math.max(1, Math.floor(rows / reduction));
        // A very narrow grid may still exceed the cap after keeping one row.
        if (columns * rows > maximumCells) {
            if (columns >= rows)
                columns = Math.floor(maximumCells / rows);
            else
                rows = Math.floor(maximumCells / columns);
        }
    }
    var capacity = columns * rows;
    var scaleFactor = capacity === 0 ? 1
        : Math.max(requestedColumns / columns, requestedRows / rows);
    var initialBranches = Math.floor(numericOption("InitialBranches", 3, 1, 32));
    var branchProbability = numericOption("BranchProbability", 0.15, 0, 0.5);
    var straightProbability = numericOption("StraightProbability", 0.12, 0, 1);
    var density = numericOption("Density", 1, 0.1, 1);
    var densityLimit = Math.min(capacity, Math.max(2, Math.ceil(capacity * density)));
    var endMode = options.EndMode === "hold" || options.EndMode === "clear"
        ? options.EndMode : "reverse";

    var occupancy = new Uint8Array(capacity);
    var segmentFrom = new Uint32Array(capacity);
    var segmentTo = new Uint32Array(capacity);
    var segmentHue = new Uint16Array(capacity);
    var segmentColor = new Uint8Array(capacity);
    var segmentMain = new Uint8Array(capacity);
    var segmentCity = new Uint8Array(capacity);
    var segmentActive = new Uint8Array(capacity);
    var segmentBranch = new Uint32Array(capacity);
    var segmentPrevious = new Int32Array(capacity);
    var historyHeads = new Int32Array(capacity);
    var reverseBranches = new Uint32Array(capacity);
    var reverseBranchCount = 0;
    var reverseCursor = 0;
    var changeIds = new Int32Array(capacity);
    var seedCells = new Uint32Array(maximumSeeds);

    // A cell links to the previous position acquired by its owning branch.
    // Backtracking does not truncate this acquisition history.
    var cellPrevious = new Int32Array(capacity);
    var branchActive = new Uint8Array(maximumBranches);
    var branchCells = new Uint32Array(maximumBranches);
    var branchHeads = new Int32Array(maximumBranches);
    var branchRoots = new Uint32Array(maximumBranches);
    var branchAges = new Uint16Array(maximumBranches);
    var branchLives = new Uint16Array(maximumBranches);
    var branchHues = new Uint16Array(maximumBranches);
    var branchColors = new Uint8Array(maximumBranches);
    var branchMain = new Uint8Array(maximumBranches);
    var branchModes = new Uint8Array(maximumBranches); // 0=CITY, 1=LAND
    var branchDirections = new Uint8Array(maximumBranches); // E, W, S, N
    var branchTurns = new Uint32Array(maximumBranches);
    var freeBranches = new Uint16Array(maximumBranches);
    var generationBranches = new Uint16Array(maximumBranches);
    var freeCount = 0;
    var eligibleCount = 0;
    var turnIndex = 0;
    var generationStage = 0; // branch the snapshot, then move the enlarged population
    var turnStage = 1; // movement, resumable backtracking
    var roundRobinCursor = 0;
    var backtrackCursor = -1;
    var backtrackDepth = 0;
    var reverseRemaining = 0;
    var randomState = 0;

    var engine = {
        requestedColumns: requestedColumns,
        requestedRows: requestedRows,
        columns: columns,
        rows: rows,
        capacity: capacity,
        scaleFactor: scaleFactor,
        effectiveScale: scale * scaleFactor,
        effectiveSpacing: 2 * scale * scaleFactor,
        densityLimit: densityLimit,
        branchCapacity: maximumBranches,
        maxBacktrack: maximumBacktrack,
        maxOperationsPerStep: maximumOperations,
        generationQueueLimit: maximumQueuedGenerations,
        occupancy: occupancy,
        segmentFrom: segmentFrom,
        segmentTo: segmentTo,
        segmentHue: segmentHue,
        segmentColor: segmentColor,
        segmentMain: segmentMain,
        segmentCity: segmentCity,
        segmentActive: segmentActive,
        segmentBranch: segmentBranch,
        journalCount: 0,
        changeIds: changeIds,
        changeCount: 0,
        segmentCount: 0,
        occupiedCount: 0,
        seedCells: seedCells,
        seedCount: 0,
        // Read-only diagnostics; slot counters include any later slot reuse.
        branchActive: branchActive,
        branchCells: branchCells,
        branchAges: branchAges,
        branchLives: branchLives,
        branchModes: branchModes,
        branchMain: branchMain,
        branchTurns: branchTurns,
        liveBranchCount: 0,
        peakBranchCount: 0,
        backtracking: false,
        backtrackOperations: 0,
        maxBacktrackDepth: 0,
        operationCount: 0,
        cycleOperationCount: 0,
        generationCount: 0,
        totalGenerationCount: 0,
        generationInProgress: false,
        queuedGenerations: 0,
        budgetLimited: false,
        phase: "finished",
        nextPhase: "",
        stopReason: "",
        phaseSerial: 0,
        resetSerial: 0,
        seed: normalizedSeed(options.Seed, 1),
        queueGenerations: queueGenerations,
        discardQueuedGenerations: discardQueuedGenerations,
        step: step,
        advancePhase: advancePhase,
        reset: reset
    };

    // Mulberry32: seed zero is valid and no instance shares PRNG state.
    function random() {
        randomState = (randomState + 0x6d2b79f5) >>> 0;
        var value = randomState;
        value = Math.imul(value ^ (value >>> 15), value | 1);
        value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
        return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
    }

    function freeMask(cell) {
        var x = cell % columns;
        var y = Math.floor(cell / columns);
        var mask = 0;
        if (x + 1 < columns && occupancy[cell + 1] === 0)
            mask |= 1;
        if (x > 0 && occupancy[cell - 1] === 0)
            mask |= 2;
        if (y + 1 < rows && occupancy[cell + columns] === 0)
            mask |= 4;
        if (y > 0 && occupancy[cell - columns] === 0)
            mask |= 8;
        return mask;
    }

    function neighborCount(mask) {
        return (mask & 1) + ((mask >>> 1) & 1)
            + ((mask >>> 2) & 1) + ((mask >>> 3) & 1);
    }

    function directionAt(mask, index) {
        for (var direction = 0; direction < 4; ++direction) {
            if ((mask & (1 << direction)) !== 0) {
                if (index === 0)
                    return direction;
                --index;
            }
        }
        return 0; // Callers always provide an index below neighborCount(mask).
    }

    function neighbor(cell, direction) {
        if (direction === 0)
            return cell + 1;
        if (direction === 1)
            return cell - 1;
        return direction === 2 ? cell + columns : cell - columns;
    }

    function allocateBranch(cell, hue, color, main, lifetime) {
        var branch = freeBranches[--freeCount];
        branchActive[branch] = 1;
        branchCells[branch] = cell;
        branchHeads[branch] = cell;
        branchRoots[branch] = cell;
        branchAges[branch] = 0;
        branchLives[branch] = lifetime;
        branchHues[branch] = hue;
        branchColors[branch] = color;
        branchMain[branch] = main;
        branchModes[branch] = 0;
        branchDirections[branch] = 0;
        ++engine.liveBranchCount;
        engine.peakBranchCount = Math.max(engine.peakBranchCount, engine.liveBranchCount);
        return branch;
    }

    function releaseBranch(branch) {
        if (branchActive[branch] !== 0) {
            branchActive[branch] = 0;
            freeBranches[freeCount++] = branch;
            --engine.liveBranchCount;
        }
    }

    function appendSegment(branch, from, to) {
        var segment = engine.journalCount++;
        ++engine.segmentCount;
        var root = branchRoots[branch];
        segmentActive[segment] = 1;
        segmentBranch[segment] = root;
        segmentPrevious[segment] = historyHeads[root];
        if (historyHeads[root] < 0)
            reverseBranches[reverseBranchCount++] = root;
        historyHeads[root] = segment;
        segmentFrom[segment] = from;
        segmentTo[segment] = to;
        segmentHue[segment] = branchHues[branch];
        segmentColor[segment] = branchColors[branch];
        segmentMain[segment] = branchMain[branch];
        segmentCity[segment] = branchModes[branch] === 0 ? 1 : 0;
        occupancy[to] = 1;
        ++engine.occupiedCount;
        changeIds[engine.changeCount++] = segment + 1;
    }

    function tryBranch(branch) {
        if (freeCount === 0 || branchHeads[branch] === branchRoots[branch])
            return;
        // Original falloff=50, with LAND branching scaled from 15% to 6%.
        var probability = branchProbability * 51 / (50 + engine.liveBranchCount);
        if (branchModes[branch] !== 0)
            probability *= 0.4;
        if (random() >= probability)
            return;
        var from = branchHeads[branch];
        var mask = freeMask(from);
        if (mask === 0)
            return;
        var direction = directionAt(mask, Math.floor(random() * neighborCount(mask)));
        var to = neighbor(from, direction);
        // The parent advances to the junction; the child inherits an anchor, not
        // a second claim. Its backtracking stops at that junction.
        appendSegment(branch, from, to);
        cellPrevious[to] = branchHeads[branch];
        branchHeads[branch] = to;
        branchCells[branch] = to;
        var hue = branchHues[branch];
        var color = branchColors[branch];
        var main = random() < 0.01 ? 1 : 0;
        if (main !== 0) {
            hue = (hue + 9) % 256;
            color = (color + 1) % 8;
        }
        allocateBranch(to, hue, color, main, main !== 0 ? mainLifetime : offshootLifetime);
    }

    function moveBranch(branch, mask) {
        var count = neighborCount(mask);
        if (branchModes[branch] === 0) {
            if (random() < straightProbability) {
                branchModes[branch] = 1;
                branchDirections[branch] = directionAt(mask, Math.floor(random() * count));
            } else if (random() < 0.00003) {
                // Retain the original rare CITY age refresh (0.003%).
                branchAges[branch] = Math.floor(random() * (branchAges[branch] + 1));
            }
        }
        if (branchLives[branch] - branchAges[branch] < offshootLifetime) {
            branchModes[branch] = 0;
        } else if (branchModes[branch] !== 0
                   && (mask & (1 << branchDirections[branch])) === 0) {
            branchModes[branch] = 0;
            branchAges[branch] = Math.floor(random() * (branchAges[branch] + 1));
        }
        var direction;
        if (branchModes[branch] !== 0) {
            // Ten extra tickets favor the forward neighbor, as in the original.
            var choice = Math.floor(random() * (count + 10));
            direction = choice < count ? directionAt(mask, choice) : branchDirections[branch];
        } else {
            direction = directionAt(mask, Math.floor(random() * count));
        }
        var from = branchCells[branch];
        var to = neighbor(from, direction);
        appendSegment(branch, from, to);
        cellPrevious[to] = branchHeads[branch];
        branchHeads[branch] = to;
        branchCells[branch] = to;
        ++branchAges[branch];
        if (branchAges[branch] >= branchLives[branch])
            releaseBranch(branch);
    }

    function setPhase(phase, nextPhase) {
        engine.phase = phase;
        engine.nextPhase = nextPhase;
        ++engine.phaseSerial;
    }

    function clearSeeds() {
        for (var i = 0; i < engine.seedCount; ++i) {
            var cell = seedCells[i];
            if (occupancy[cell] !== 0) {
                occupancy[cell] = 0;
                --engine.occupiedCount;
            }
        }
        engine.seedCount = 0;
    }

    function completeGeneration() {
        if (engine.generationInProgress) {
            engine.generationInProgress = false;
            ++engine.generationCount;
            ++engine.totalGenerationCount;
        }
        engine.backtracking = false;
        eligibleCount = 0;
        turnIndex = 0;
        generationStage = 0;
        turnStage = 1;
    }

    function stopGrowth(reason) {
        completeGeneration();
        engine.queuedGenerations = 0;
        branchActive.fill(0);
        engine.liveBranchCount = 0;
        engine.stopReason = reason;
        if (engine.segmentCount === 0) {
            // No visible geometry means no useful growth/reverse delay loop.
            clearSeeds();
            setPhase("finished", "");
        } else if (endMode === "hold") {
            setPhase("finished", "");
        } else {
            setPhase("holding", endMode === "reverse" ? "reversing" : "growing");
        }
    }

    function finishReverse() {
        completeGeneration();
        engine.queuedGenerations = 0;
        clearSeeds();
        setPhase("holding", "growing");
    }

    function startGeneration() {
        --engine.queuedGenerations;
        if (engine.phase === "reversing") {
            if (engine.segmentCount === 0) {
                finishReverse();
                return;
            }
            reverseRemaining = 50;
        } else {
            eligibleCount = 0;
            for (var offset = 0; offset < maximumBranches; ++offset) {
                var branch = (roundRobinCursor + offset) % maximumBranches;
                if (branchActive[branch] !== 0)
                    generationBranches[eligibleCount++] = branch;
            }
            roundRobinCursor = (roundRobinCursor + 1) % maximumBranches;
            if (eligibleCount === 0) {
                stopGrowth("branches");
                return;
            }
            turnIndex = 0;
            generationStage = 0;
            turnStage = 1;
        }
        engine.generationInProgress = true;
    }

    function finishTurn(branch) {
        ++branchTurns[branch];
        ++turnIndex;
        turnStage = 1;
        engine.backtracking = false;
    }

    function growOperation() {
        var branch = generationBranches[turnIndex];
        if (generationStage === 0) {
            if (branchActive[branch] !== 0)
                tryBranch(branch);
            if (++turnIndex >= eligibleCount) {
                eligibleCount = 0;
                for (var offset = 0; offset < maximumBranches; ++offset) {
                    var candidate = (roundRobinCursor + offset) % maximumBranches;
                    if (branchActive[candidate] !== 0)
                        generationBranches[eligibleCount++] = candidate;
                }
                turnIndex = 0;
                generationStage = 1;
            }
        } else if (turnStage === 1) {
            var mask = freeMask(branchCells[branch]);
            if (mask !== 0) {
                moveBranch(branch, mask);
                finishTurn(branch);
            } else {
                // The just-tested head is the first of at most 300 candidates.
                backtrackCursor = branchHeads[branch] === branchRoots[branch]
                    ? -1 : cellPrevious[branchHeads[branch]];
                backtrackDepth = 1;
                engine.maxBacktrackDepth = Math.max(engine.maxBacktrackDepth, backtrackDepth);
                if (backtrackCursor < 0) {
                    releaseBranch(branch);
                    finishTurn(branch);
                } else {
                    turnStage = 2;
                    engine.backtracking = true;
                }
            }
        } else {
            ++backtrackDepth;
            ++engine.backtrackOperations;
            engine.maxBacktrackDepth = Math.max(engine.maxBacktrackDepth, backtrackDepth);
            var backtrackMask = freeMask(backtrackCursor);
            if (backtrackMask !== 0) {
                branchCells[branch] = backtrackCursor;
                moveBranch(branch, backtrackMask);
                finishTurn(branch);
            } else {
                backtrackCursor = backtrackCursor === branchRoots[branch]
                    ? -1 : cellPrevious[backtrackCursor];
                if (backtrackCursor < 0 || backtrackDepth >= maximumBacktrack) {
                    releaseBranch(branch);
                    finishTurn(branch);
                }
            }
        }
        if (engine.occupiedCount >= densityLimit) {
            stopGrowth("density");
        } else if (turnIndex >= eligibleCount) {
            completeGeneration();
            if (engine.liveBranchCount === 0)
                stopGrowth("branches");
        }
    }

    function reverseOperation() {
        var root = reverseBranches[reverseCursor];
        var segment = historyHeads[root];
        historyHeads[root] = segmentPrevious[segment];
        if (historyHeads[root] < 0)
            reverseBranches[reverseCursor] = reverseBranches[--reverseBranchCount];
        else
            ++reverseCursor;
        if (reverseCursor >= reverseBranchCount)
            reverseCursor = 0;
        segmentActive[segment] = 0;
        --engine.segmentCount;
        occupancy[segmentTo[segment]] = 0;
        --engine.occupiedCount;
        changeIds[engine.changeCount++] = -(segment + 1);
        --reverseRemaining;
        if (engine.segmentCount === 0) {
            finishReverse();
        } else if (reverseRemaining === 0) {
            completeGeneration();
        }
    }

    function queueGenerations(count) {
        engine.queuedGenerations = engine.phase === "growing" || engine.phase === "reversing"
            ? (typeof count === "number" && isFinite(count)
               ? Math.max(0, Math.min(maximumQueuedGenerations, Math.floor(count))) : 0)
            : 0;
        return engine.queuedGenerations;
    }

    function discardQueuedGenerations() {
        engine.queuedGenerations = 0;
    }

    function step(maxOperations) {
        engine.changeCount = 0;
        engine.budgetLimited = false;
        var limit = maxOperations === undefined ? maximumOperations
            : (typeof maxOperations === "number" && isFinite(maxOperations)
               ? Math.max(0, Math.min(maximumOperations, Math.floor(maxOperations))) : 0);
        var operations = 0;
        while (operations < limit
               && (engine.phase === "growing" || engine.phase === "reversing")) {
            if (!engine.generationInProgress) {
                if (engine.queuedGenerations === 0)
                    break;
                startGeneration();
                if (!engine.generationInProgress)
                    break;
            }
            if (engine.phase === "growing")
                growOperation();
            else
                reverseOperation();
            ++operations;
        }
        engine.operationCount += operations;
        engine.cycleOperationCount += operations;
        engine.budgetLimited = operations === limit && limit !== 0
            && (engine.phase === "growing" || engine.phase === "reversing")
            && (engine.generationInProgress || engine.queuedGenerations !== 0);
        return operations;
    }

    function advancePhase(seed) {
        if (engine.phase !== "holding")
            return false;
        engine.queuedGenerations = 0;
        engine.changeCount = 0;
        engine.budgetLimited = false;
        if (engine.nextPhase === "reversing") {
            setPhase("reversing", "");
        } else {
            reset(seed);
        }
        return true;
    }

    function reset(seed) {
        engine.seed = normalizedSeed(seed, engine.seed);
        randomState = engine.seed >>> 0;
        occupancy.fill(0);
        segmentActive.fill(0);
        historyHeads.fill(-1);
        reverseBranchCount = 0;
        reverseCursor = 0;
        branchActive.fill(0);
        branchTurns.fill(0);
        for (var i = 0; i < maximumBranches; ++i)
            freeBranches[i] = maximumBranches - 1 - i;
        freeCount = maximumBranches;
        eligibleCount = 0;
        turnIndex = 0;
        generationStage = 0;
        turnStage = 1;
        roundRobinCursor = 0;
        backtrackCursor = -1;
        backtrackDepth = 0;
        reverseRemaining = 0;
        engine.changeCount = 0;
        engine.segmentCount = 0;
        engine.journalCount = 0;
        engine.occupiedCount = 0;
        engine.seedCount = 0;
        engine.liveBranchCount = 0;
        engine.peakBranchCount = 0;
        engine.backtracking = false;
        engine.backtrackOperations = 0;
        engine.maxBacktrackDepth = 0;
        engine.cycleOperationCount = 0;
        engine.generationCount = 0;
        engine.generationInProgress = false;
        engine.queuedGenerations = 0;
        engine.budgetLimited = false;
        engine.stopReason = "";
        ++engine.resetSerial;
        setPhase(capacity < 2 ? "finished" : "growing", "");
        if (capacity < 2) {
            engine.stopReason = "empty";
            return engine;
        }
        // Leave a destination for growth even when a small grid has many seeds.
        var count = Math.min(initialBranches, densityLimit - 1, capacity - 1);
        for (var seedIndex = 0; seedIndex < count; ++seedIndex) {
            var cell = Math.floor(random() * capacity);
            // Linear probing is bounded; already claimed seeds cannot collide.
            for (var probe = 0; probe < capacity && occupancy[cell] !== 0; ++probe)
                cell = (cell + 1) % capacity;
            occupancy[cell] = 1;
            ++engine.occupiedCount;
            seedCells[engine.seedCount++] = cell;
            cellPrevious[cell] = -1;
            allocateBranch(cell, Math.floor(random() * 256), Math.floor(random() * 8),
                           1, mainLifetime);
        }
        if (engine.occupiedCount >= densityLimit)
            stopGrowth("density");
        return engine;
    }

    reset(engine.seed);
    return engine;
}
