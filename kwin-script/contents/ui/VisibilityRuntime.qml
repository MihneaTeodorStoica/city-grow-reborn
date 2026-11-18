// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Mihnea Teodor Stoica

import QtQuick
import org.kde.kwin
import org.kde.plasma.workspace.dbus as DBus
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/coverage.js" as Coverage

Item {
    id: root

    readonly property string wallpaperId: "io.github.mihneateodorstoica.citygrowreborn"
    property bool tracking: false
    property var trackedWindows: []
    property var outputConnections: []
    property int selectionSerial: 0
    property int selectionRemaining: 0
    property bool selectionUsesWallpaper: false
    property string latestSnapshot: ""
    property string lastEmittedSnapshot: ""
    property string pendingSnapshot: ""
    property bool pendingForced: false
    property string emissionSource: ""
    property string emittingSnapshot: ""

    // Only wallpaper/output/activity events query selection. No window tracking
    // or signal helper process remains active when this wallpaper is unused.
    Timer {
        id: selectionTimer
        interval: 100
        repeat: false
        onTriggered: root.queryWallpaperSelection()
    }
    Timer {
        id: coverageTimer
        interval: 100
        repeat: false
        onTriggered: root.recomputeCoverage(false)
    }
    Timer {
        id: emissionTimer
        interval: 0
        repeat: false
        onTriggered: root.emitPendingSnapshot()
    }

    Plasma5Support.DataSource {
        id: sender
        engine: "executable"
        interval: 0
        connectedSources: []
        onNewData: function(sourceName, data) {
            if (data["exit code"] !== undefined)
                root.emissionFinished(sourceName, data)
        }
    }

    DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: "io.github.mihneateodorstoica.CityGrowReborn.Requests"
        path: "/io/github/mihneateodorstoica/CityGrowReborn"
        iface: "io.github.mihneateodorstoica.CityGrowReborn.Requests"
        function dbusSnapshotRequested(unused) {
            if (root.tracking) root.recomputeCoverage(true)
            else selectionTimer.start()
        }
    }
    DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: "org.kde.plasmashell"
        path: "/PlasmaShell"
        iface: "org.kde.PlasmaShell"
        function dbuswallpaperChanged(screenNum) { selectionTimer.start() }
        function dbusshellChanged(shell) {
            root.setTracking(false)
            selectionTimer.start()
        }
        // A shell color change can accompany changing the wallpaper source.
        function dbuscolorChanged(color) { selectionTimer.start() }
    }
    DBus.DBusServiceWatcher {
        id: shellService
        busType: DBus.BusType.Session
        watchedService: "org.kde.plasmashell"
        onRegisteredChanged: {
            if (registered) selectionTimer.start()
            else {
                ++root.selectionSerial
                selectionTimer.stop()
                root.setTracking(false)
            }
        }
    }

    Connections {
        target: Workspace
        function onScreensChanged() {
            root.setTracking(false)
            selectionTimer.start()
        }
        function onScreenOrderChanged() { selectionTimer.start() }
        function onCurrentActivityChanged(id) {
            root.setTracking(false)
            selectionTimer.start()
        }
    }
    Connections {
        target: Workspace
        enabled: root.tracking
        function onWindowAdded(window) {
            root.trackWindow(window)
            root.scheduleCoverage()
        }
        function onWindowRemoved(window) {
            root.untrackWindow(window)
            root.scheduleCoverage()
        }
        function onWindowActivated(window) { root.scheduleCoverage() }
        function onCurrentDesktopChanged(previous, current, output) { root.scheduleCoverage() }
    }

    function queryWallpaperSelection() {
        var serial = ++selectionSerial
        if (!shellService.registered) {
            setTracking(false)
            return
        }
        // Plasma's screen IDs are indices in its active screen order; KWin's
        // screen count bounds the same current active-output indices.
        selectionRemaining = Workspace.screens.length
        selectionUsesWallpaper = false
        if (selectionRemaining === 0) {
            setTracking(false)
            return
        }
        for (var index = 0; index < Workspace.screens.length; ++index)
            queryWallpaper(index, serial)
    }

    function queryWallpaper(index, serial) {
        DBus.SessionBus.asyncCall({
            service: "org.kde.plasmashell",
            path: "/PlasmaShell",
            iface: "org.kde.PlasmaShell",
            member: "wallpaper",
            signature: "(u)",
            arguments: [new DBus.uint32(index)]
        }, function(reply) {
            if (serial !== root.selectionSerial) return
            if (reply.value && String(reply.value["wallpaperPlugin"]) === root.wallpaperId)
                root.selectionUsesWallpaper = true
            root.finishWallpaperQuery(serial)
        }, function(reply) {
            root.finishWallpaperQuery(serial)
        })
    }

    function finishWallpaperQuery(serial) {
        if (serial !== selectionSerial) return
        if (--selectionRemaining === 0) setTracking(selectionUsesWallpaper)
    }

    function connectSignal(target, name, handler, records) {
        var signal = target[name]
        signal.connect(handler)
        records.push({ target: target, name: name, handler: handler })
    }

    function disconnectSignals(records) {
        for (var i = 0; i < records.length; ++i) {
            // windowRemoved can run during destruction of its QObject.
            try { records[i].target[records[i].name].disconnect(records[i].handler) }
            catch (error) { /* Already destroyed; no connection can survive it. */ }
        }
    }

    function trackWindow(window) {
        for (var i = 0; i < trackedWindows.length; ++i)
            if (trackedWindows[i].window === window) return
        var record = { window: window, connections: [] }
        var handler = function() { root.scheduleCoverage() }
        var names = ["frameGeometryChanged", "opacityChanged", "minimizedChanged",
                     "hiddenChanged", "outputChanged", "desktopsChanged", "activitiesChanged",
                     "stackingOrderChanged", "windowClassChanged"]
        for (var j = 0; j < names.length; ++j)
            connectSignal(window, names[j], handler, record.connections)
        trackedWindows.push(record)
    }

    function untrackWindow(window) {
        for (var i = trackedWindows.length - 1; i >= 0; --i) {
            if (trackedWindows[i].window !== window) continue
            disconnectSignals(trackedWindows[i].connections)
            trackedWindows.splice(i, 1)
        }
    }

    function setTracking(enabled) {
        if (tracking === enabled) return
        tracking = enabled
        if (!enabled) {
            coverageTimer.stop()
            emissionTimer.stop()
            pendingSnapshot = ""
            pendingForced = false
            latestSnapshot = ""
            for (var i = 0; i < trackedWindows.length; ++i)
                disconnectSignals(trackedWindows[i].connections)
            trackedWindows = []
            disconnectSignals(outputConnections)
            outputConnections = []
            return
        }
        var windows = Workspace.stackingOrder
        for (var j = 0; j < windows.length; ++j) trackWindow(windows[j])
        var outputs = Workspace.screens
        var handler = function() { root.scheduleCoverage() }
        for (var k = 0; k < outputs.length; ++k) {
            connectSignal(outputs[k], "geometryChanged", handler, outputConnections)
            connectSignal(outputs[k], "scaleChanged", handler, outputConnections)
        }
        recomputeCoverage(true)
    }

    function scheduleCoverage() {
        if (tracking) coverageTimer.start()
    }

    function recomputeCoverage(force) {
        if (!tracking) return
        var outputs = []
        var screens = Workspace.screens
        var windows = Workspace.stackingOrder
        for (var i = 0; i < screens.length; ++i) {
            var state = "visible"
            try {
                var desktop = Workspace.currentDesktopForScreen(screens[i])
                var area = Workspace.clientArea(Workspace.MaximizeArea, screens[i], desktop)
                state = Coverage.coverageForOutput(area, windows, desktop, Workspace.currentActivity).state
            } catch (error) {
                // An output disappearing during a coalesced update must not
                // leave its wallpaper frozen by an old covered classification.
                state = "visible"
            }
            outputs.push({ name: String(screens[i].name), state: state })
        }
        outputs.sort(function(a, b) { return a.name < b.name ? -1 : a.name > b.name ? 1 : 0 })
        var json = JSON.stringify({ version: 1, outputs: outputs })
        var changed = json !== latestSnapshot
        latestSnapshot = json
        if (force || changed) queueSnapshot(json, force)
    }

    function queueSnapshot(json, force) {
        pendingSnapshot = json
        pendingForced = pendingForced || force
        if (emissionSource === "") emissionTimer.start()
    }

    function shellQuote(text) {
        return "'" + text.replace(/'/g, "'\\''") + "'"
    }

    function emitPendingSnapshot() {
        if (!tracking || emissionSource !== "" || pendingSnapshot === "") return
        var json = pendingSnapshot
        var force = pendingForced
        pendingSnapshot = ""
        pendingForced = false
        if (!force && json === lastEmittedSnapshot) return
        emittingSnapshot = json
        emissionSource = "dbus-send --session --sender=io.github.mihneateodorstoica.CityGrowReborn.Visibility"
            + " --type=signal /io/github/mihneateodorstoica/CityGrowReborn"
            + " io.github.mihneateodorstoica.CityGrowReborn.Visibility.StateChanged "
            + shellQuote("string:" + json)
        sender.connectSource(emissionSource)
    }

    function emissionFinished(sourceName, data) {
        var succeeded = Number(data["exit code"]) === 0
        sender.disconnectSource(sourceName)
        if (sourceName !== emissionSource) return
        if (succeeded) lastEmittedSnapshot = emittingSnapshot
        emissionSource = ""
        emittingSnapshot = ""
        // Dispatch on the next turn, after the executable data container has
        // disconnected, keeping one in-flight command and only the latest state.
        if (tracking && pendingSnapshot !== "") emissionTimer.start()
    }

    Component.onCompleted: selectionTimer.start()
    Component.onDestruction: {
        ++selectionSerial
        setTracking(false)
        if (emissionSource !== "") sender.disconnectSource(emissionSource)
    }
}
