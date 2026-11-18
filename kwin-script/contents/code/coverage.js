// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Mihnea Teodor Stoica

// Geometry stays in logical desktop coordinates. This estimates opaque window
// coverage, not per-pixel compositor occlusion, effects, or surface alpha.
function validRectangle(rect) {
    return rect && typeof rect.x === "number" && isFinite(rect.x)
        && typeof rect.y === "number" && isFinite(rect.y)
        && typeof rect.width === "number" && isFinite(rect.width) && rect.width > 0
        && typeof rect.height === "number" && isFinite(rect.height) && rect.height > 0
        && isFinite(rect.x + rect.width) && isFinite(rect.y + rect.height)
        && isFinite(rect.width * rect.height);
}

function intersectRectangles(a, b) {
    var left = Math.max(a.x, b.x);
    var top = Math.max(a.y, b.y);
    var right = Math.min(a.x + a.width, b.x + b.width);
    var bottom = Math.min(a.y + a.height, b.y + b.height);
    return right > left && bottom > top
        ? { x: left, y: top, width: right - left, height: bottom - top } : null;
}

// Sweep unique x edges and merge the y intervals in each stripe. Summing
// window areas would incorrectly classify overlapping windows as full cover.
function rectangleUnionArea(rectangles) {
    var edges = [];
    var i;
    for (i = 0; i < rectangles.length; ++i) {
        edges.push(rectangles[i].x, rectangles[i].x + rectangles[i].width);
    }
    edges.sort(function(a, b) { return a - b; });
    var total = 0;
    for (i = 1; i < edges.length; ++i) {
        var left = edges[i - 1];
        var right = edges[i];
        if (right <= left) continue;
        var intervals = [];
        for (var j = 0; j < rectangles.length; ++j) {
            var rect = rectangles[j];
            if (rect.x < right && rect.x + rect.width > left)
                intervals.push([rect.y, rect.y + rect.height]);
        }
        intervals.sort(function(a, b) { return a[0] - b[0]; });
        var length = 0;
        var start = 0;
        var end = 0;
        for (j = 0; j < intervals.length; ++j) {
            if (j === 0 || intervals[j][0] > end) {
                if (j > 0) length += end - start;
                start = intervals[j][0];
                end = intervals[j][1];
            } else {
                end = Math.max(end, intervals[j][1]);
            }
        }
        if (intervals.length > 0) length += end - start;
        total += (right - left) * length;
    }
    return total;
}

function desktopKey(desktop) {
    if (desktop === undefined || desktop === null) return null;
    if (typeof desktop === "object")
        return desktop.id === undefined ? null : String(desktop.id);
    return String(desktop);
}

function windowIsEligible(window, desktop, activity) {
    if (!window || (!window.normalWindow && !window.dialog)
            || window.desktopWindow || window.dock || window.minimized || window.hidden)
        return false;
    var opacity = window.opacity === undefined ? 1 : window.opacity;
    if (typeof opacity !== "number" || !isFinite(opacity) || opacity < 0.999)
        return false;
    var activities = window.activities;
    if (activities && activities.length > 0) {
        var onActivity = false;
        for (var i = 0; i < activities.length; ++i)
            if (String(activities[i]) === String(activity)) onActivity = true;
        if (!onActivity) return false;
    }
    var desktops = window.desktops;
    if (!window.onAllDesktops && desktops && desktops.length > 0) {
        var onDesktop = false;
        var currentKey = desktopKey(desktop);
        for (var j = 0; j < desktops.length; ++j) {
            if (desktops[j] === desktop
                    || (currentKey !== null && desktopKey(desktops[j]) === currentKey))
                onDesktop = true;
        }
        if (!onDesktop) return false;
    }
    return true;
}

// Accepts KWin Window objects directly or equivalent plain fixture records.
// Invalid geometry and excessive candidate counts must never falsely pause.
function coverageForOutput(area, windows, desktop, activity) {
    if (!validRectangle(area))
        return { state: "visible", ratio: 0, reason: "invalid-area" };
    var rectangles = [];
    var eligibleCount = 0;
    for (var i = 0; i < windows.length; ++i) {
        var window = windows[i];
        if (!windowIsEligible(window, desktop, activity)) continue;
        if (++eligibleCount > 256)
            return { state: "visible", ratio: 0, reason: "window-limit" };
        if (!validRectangle(window.frameGeometry))
            return { state: "visible", ratio: 0, reason: "invalid-window" };
        var intersection = intersectRectangles(area, window.frameGeometry);
        if (intersection) rectangles.push(intersection);
    }
    var ratio = Math.min(1, rectangleUnionArea(rectangles) / (area.width * area.height));
    return {
        state: ratio >= 0.98 ? "covered" : ratio >= 0.50 ? "partial" : "visible",
        ratio: ratio,
        reason: ""
    };
}
