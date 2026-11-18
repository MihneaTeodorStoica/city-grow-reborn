// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Mihnea Teodor Stoica

pragma Singleton

import QtQuick
import org.kde.plasma.workspace.dbus as DBus
import org.kde.plasma.plasma5support as Plasma5Support
import "code/power.js" as Power

// One instance per live wallpaper QML engine. Only VisibilityController
// registers consumers; CityView and its isolated settings preview do not.
Item {
    id: hub
    visible: false

    readonly property int consumerCount: _consumerCount
    readonly property bool locked: _locked
    readonly property bool lockKnown: _lockKnown
    readonly property bool showingDesktop: _showingDesktop
    readonly property bool showDesktopKnown: _showDesktopKnown
    readonly property bool coveragePending: _coveragePending
    readonly property bool coverageTimedOut: _coverageTimedOut
    readonly property bool powerProbeRunning: _powerSource !== ""
    readonly property int powerProbeInterval: _powerInterval
    readonly property int powerProbeCount: _powerProbeCount
    readonly property int snapshotRequestCount: _snapshotRequestCount
    readonly property int snapshotReceiveCount: _snapshotReceiveCount
    readonly property double lastPowerProbeAt: _lastPowerProbeAt
    readonly property string diagnosticMessage: runtimeDiagnostics()

    property var _consumers: []
    property int _consumerCount: 0
    property int _nextToken: 1
    property int _sessionSerial: 0
    property int _lockSerial: 0
    property int _showDesktopSerial: 0
    property bool _locked: false
    property bool _lockKnown: false
    property bool _showingDesktop: false
    property bool _showDesktopKnown: false
    property var _coverageStates: ({})
    property bool _coverageReceived: false
    property bool _coveragePending: false
    property bool _coverageTimedOut: false
    property string _coverageError: ""
    property bool _requestPending: false
    property string _requestSource: ""
    property int _requestSession: 0
    property int _snapshotRequestCount: 0
    property int _snapshotReceiveCount: 0
    property bool _powerDemand: false
    property int _powerInterval: 5
    property var _powerOutputs: []
    property var _powerStates: ({})
    property bool _powerHasResult: false
    property bool _powerFailed: false
    property bool _powerProbePending: false
    property int _powerEpoch: 0
    property int _probeEpoch: 0
    property int _probeSession: 0
    property string _powerSource: ""
    property int _powerProbeCount: 0
    property double _lastPowerProbeAt: 0

    Timer {
        id: snapshotDeadline
        interval: 2000
        repeat: false
        onTriggered: {
            hub._coveragePending = false
            hub._coverageTimedOut = !hub._coverageReceived
        }
    }
    Timer {
        id: requestDispatch
        interval: 0
        repeat: false
        onTriggered: hub.sendPendingRequest()
    }
    Timer {
        id: powerDispatch
        interval: 0
        repeat: false
        onTriggered: hub.sendPendingPowerProbe()
    }
    Timer {
        id: powerTimer
        interval: hub._powerInterval * 1000
        repeat: false
        onTriggered: hub.queuePowerProbe()
    }

    DBus.SignalWatcher {
        enabled: hub.consumerCount > 0
        busType: DBus.BusType.Session
        service: "io.github.mihneateodorstoica.CityGrowReborn.Visibility"
        path: "/io/github/mihneateodorstoica/CityGrowReborn"
        iface: "io.github.mihneateodorstoica.CityGrowReborn.Visibility"
        function dbusStateChanged(json) { hub.acceptSnapshot(String(json)) }
    }
    DBus.SignalWatcher {
        enabled: hub.consumerCount > 0
        busType: DBus.BusType.Session
        service: "org.freedesktop.ScreenSaver"
        path: "/ScreenSaver"
        iface: "org.freedesktop.ScreenSaver"
        function dbusActiveChanged(active) {
            ++hub._lockSerial
            hub._locked = active === true
            hub._lockKnown = true
            hub.refreshPowerDemand()
        }
    }
    DBus.SignalWatcher {
        enabled: hub.consumerCount > 0
        busType: DBus.BusType.Session
        service: "org.kde.KWin"
        path: "/KWin"
        iface: "org.kde.KWin"
        function dbusreloadConfig() {
            hub.invalidateCoverage("")
            hub.queryShowDesktop()
            hub.requestSnapshot()
        }
        function dbusshowingDesktopChanged(showing) {
            ++hub._showDesktopSerial
            hub._showingDesktop = showing === true
            hub._showDesktopKnown = true
            hub.refreshPowerDemand()
            if (!hub._showingDesktop) hub.requestSnapshot()
        }
    }
    // NameOwnerChanged catches owner replacement as well as service loss;
    // a registered-only watcher can miss a nonempty-to-nonempty replacement.
    DBus.SignalWatcher {
        enabled: hub.consumerCount > 0
        busType: DBus.BusType.Session
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        iface: "org.freedesktop.DBus"
        function dbusNameOwnerChanged(name, oldOwner, newOwner) {
            name = String(name)
            if (name === "org.kde.KWin") {
                ++hub._showDesktopSerial
                hub._showingDesktop = false
                hub._showDesktopKnown = false
                hub.invalidateCoverage("")
                if (String(newOwner) !== "") {
                    hub.queryShowDesktop()
                    hub.requestSnapshot()
                }
            } else if (name === "org.freedesktop.ScreenSaver") {
                ++hub._lockSerial
                hub._locked = false
                hub._lockKnown = false
                hub.refreshPowerDemand()
                if (String(newOwner) !== "") hub.queryLock()
            }
        }
    }

    Plasma5Support.DataSource {
        id: requester
        engine: "executable"
        interval: 0
        connectedSources: []
        onNewData: function(sourceName, data) {
            if (data["exit code"] !== undefined) hub.requestFinished(sourceName, data)
        }
    }
    Plasma5Support.DataSource {
        id: powerProbe
        engine: "executable"
        interval: 0
        connectedSources: []
        onNewData: function(sourceName, data) {
            if (data["exit code"] !== undefined) hub.powerProbeFinished(sourceName, data)
        }
    }

    function normalizeConsumer(token, options) {
        return {
            token: token,
            outputName: String(options.outputName || ""),
            itemVisible: options.itemVisible !== false,
            paused: options.paused === true,
            visibilityMode: options.visibilityMode === "always" ? "always" : "adaptive",
            checkDisplayPower: options.checkDisplayPower !== false,
            displayPowerInterval: Math.max(1, Math.min(30, Number(options.displayPowerInterval) || 5))
        }
    }

    function registerConsumer(options) {
        var token = _nextToken++
        var consumers = _consumers.slice()
        consumers.push(normalizeConsumer(token, options))
        _consumers = consumers
        var first = _consumerCount === 0
        _consumerCount = consumers.length
        if (first) startRuntime()
        else {
            refreshPowerDemand()
            if (coverageState(options.outputName) === "unknown") requestSnapshot()
        }
        return token
    }

    function updateConsumer(token, options) {
        var consumers = _consumers.slice()
        for (var i = 0; i < consumers.length; ++i) {
            if (consumers[i].token !== token) continue
            var changedOutput = consumers[i].outputName !== String(options.outputName || "")
            consumers[i] = normalizeConsumer(token, options)
            _consumers = consumers
            refreshPowerDemand()
            if (changedOutput && coverageState(options.outputName) === "unknown") requestSnapshot()
            return
        }
    }

    function unregisterConsumer(token) {
        var consumers = _consumers.filter(function(consumer) { return consumer.token !== token })
        _consumers = consumers
        _consumerCount = consumers.length
        if (_consumerCount === 0) stopRuntime()
        else refreshPowerDemand()
    }

    function startRuntime() {
        var session = ++_sessionSerial
        invalidateCoverage("")
        // Defer until the enabled bus receivers have registered before emitting
        // the initial request. Callbacks never retain a controller QObject.
        Qt.callLater(function() {
            if (session !== hub._sessionSerial || hub.consumerCount === 0) return
            hub.queryLock()
            hub.queryShowDesktop()
            hub.requestSnapshot()
            hub.refreshPowerDemand()
        })
    }

    function stopRuntime() {
        ++_sessionSerial
        ++_lockSerial
        ++_showDesktopSerial
        ++_powerEpoch
        snapshotDeadline.stop()
        requestDispatch.stop()
        powerDispatch.stop()
        powerTimer.stop()
        _requestPending = false
        _powerProbePending = false
        _powerDemand = false
        _powerOutputs = []
        _powerStates = ({})
        _powerHasResult = false
        _powerFailed = false
        _coverageStates = ({})
        _coverageReceived = false
        _coveragePending = false
        _coverageTimedOut = false
        _coverageError = ""
        _locked = false
        _lockKnown = false
        _showingDesktop = false
        _showDesktopKnown = false
        // Already-launched one-shot commands may finish, but cannot reschedule.
    }

    function queryLock() {
        var session = _sessionSerial
        var serial = ++_lockSerial
        DBus.SessionBus.asyncCall({
            service: "org.freedesktop.ScreenSaver", path: "/ScreenSaver",
            iface: "org.freedesktop.ScreenSaver", member: "GetActive"
        }, function(reply) {
            if (session !== hub._sessionSerial || serial !== hub._lockSerial) return
            hub._lockKnown = typeof reply.value === "boolean"
            hub._locked = hub._lockKnown && reply.value
            hub.refreshPowerDemand()
        }, function(reply) {
            if (session !== hub._sessionSerial || serial !== hub._lockSerial) return
            hub._lockKnown = false
            hub._locked = false
            hub.refreshPowerDemand()
        })
    }

    function queryShowDesktop() {
        var session = _sessionSerial
        var serial = ++_showDesktopSerial
        DBus.SessionBus.asyncCall({
            service: "org.kde.KWin", path: "/KWin",
            iface: "org.freedesktop.DBus.Properties", member: "Get",
            signature: "(ss)", arguments: ["org.kde.KWin", "showingDesktop"]
        }, function(reply) {
            if (session !== hub._sessionSerial || serial !== hub._showDesktopSerial) return
            hub._showDesktopKnown = typeof reply.value === "boolean"
            hub._showingDesktop = hub._showDesktopKnown && reply.value
            hub.refreshPowerDemand()
        }, function(reply) {
            if (session !== hub._sessionSerial || serial !== hub._showDesktopSerial) return
            hub._showDesktopKnown = false
            hub._showingDesktop = false
            hub.refreshPowerDemand()
        })
    }

    function invalidateCoverage(error) {
        _coverageStates = ({})
        _coverageReceived = false
        _coveragePending = consumerCount > 0
        _coverageTimedOut = false
        _coverageError = error
        if (consumerCount > 0) snapshotDeadline.restart()
        refreshPowerDemand()
    }

    function acceptSnapshot(json) {
        if (consumerCount === 0) return
        var snapshot
        var states = Object.create(null)
        try {
            if (json.length > 65536) throw new Error("oversized snapshot")
            snapshot = JSON.parse(json)
            if (!snapshot || snapshot.version !== 1 || !Array.isArray(snapshot.outputs)
                    || snapshot.outputs.length > 256) throw new Error("invalid snapshot")
            for (var i = 0; i < snapshot.outputs.length; ++i) {
                var output = snapshot.outputs[i]
                if (!output || typeof output.name !== "string" || output.name.length === 0
                        || ["visible", "partial", "covered"].indexOf(output.state) < 0
                        || Object.prototype.hasOwnProperty.call(states, output.name))
                    throw new Error("invalid output")
                states[output.name] = output.state
            }
        } catch (error) {
            invalidateCoverage("invalid")
            return
        }
        _coverageStates = states
        _coverageReceived = true
        _coveragePending = false
        _coverageTimedOut = false
        _coverageError = ""
        ++_snapshotReceiveCount
        snapshotDeadline.stop()
        refreshPowerDemand()
    }

    function coverageState(outputName) {
        if (!_coverageReceived) return "unknown"
        return Object.prototype.hasOwnProperty.call(_coverageStates, outputName)
            ? _coverageStates[outputName] : "unknown"
    }

    function coverageIssue(outputName) {
        if (_coverageError !== "") return _coverageError
        if (_coverageTimedOut) return "missing"
        if (_coverageReceived && coverageState(outputName) === "unknown") return "output-missing"
        return ""
    }

    function requestSnapshot() {
        if (consumerCount === 0) return
        _requestPending = true
        if (_requestSource === "") requestDispatch.start()
    }

    function sendPendingRequest() {
        if (!_requestPending || _requestSource !== "" || consumerCount === 0) return
        _requestPending = false
        _requestSession = _sessionSerial
        _requestSource = "dbus-send --session --sender=io.github.mihneateodorstoica.CityGrowReborn.Requests"
            + " --type=signal /io/github/mihneateodorstoica/CityGrowReborn"
            + " io.github.mihneateodorstoica.CityGrowReborn.Requests.SnapshotRequested 'string:'"
        ++_snapshotRequestCount
        requester.connectSource(_requestSource)
    }

    function requestFinished(sourceName, data) {
        var failed = Number(data["exit code"]) !== 0
        requester.disconnectSource(sourceName)
        if (sourceName !== _requestSource) return
        _requestSource = ""
        if (failed && _requestSession === _sessionSerial && consumerCount > 0 && !_coverageReceived)
            _coverageError = "request-failed"
        if (_requestPending && consumerCount > 0) requestDispatch.start()
    }

    function refreshPowerDemand() {
        var outputs = []
        var interval = 30
        if (!(_lockKnown && _locked)) {
            for (var i = 0; i < _consumers.length; ++i) {
                var consumer = _consumers[i]
                if (!consumer.checkDisplayPower || consumer.paused || !consumer.itemVisible) continue
                if (consumer.visibilityMode !== "always" && !_showingDesktop
                        && coverageState(consumer.outputName) === "covered") continue
                if (outputs.indexOf(consumer.outputName) < 0) outputs.push(consumer.outputName)
                interval = Math.min(interval, consumer.displayPowerInterval)
            }
        }
        outputs.sort()
        var demand = outputs.length > 0
        var changedOutputs = JSON.stringify(outputs) !== JSON.stringify(_powerOutputs)
        var changedInterval = interval !== _powerInterval
        _powerInterval = demand ? interval : 5
        if (!demand) {
            if (_powerDemand) ++_powerEpoch
            _powerDemand = false
            _powerOutputs = []
            _powerHasResult = false
            _powerFailed = false
            _powerProbePending = false
            powerDispatch.stop()
            powerTimer.stop()
            return
        }
        var starting = !_powerDemand || changedOutputs
        _powerDemand = true
        _powerOutputs = outputs
        if (starting) {
            ++_powerEpoch
            // Keep a confirmed off state until the immediate fresh probe
            // replaces it, so a demand change cannot briefly animate it.
            _powerHasResult = false
            _powerFailed = false
            powerTimer.stop()
            queuePowerProbe()
        } else if (changedInterval && powerTimer.running) {
            powerTimer.restart()
        }
    }

    function queuePowerProbe() {
        if (!_powerDemand || consumerCount === 0) return
        _powerProbePending = true
        if (_powerSource === "") powerDispatch.start()
    }

    function sendPendingPowerProbe() {
        if (!_powerProbePending || !_powerDemand || _powerSource !== "" || consumerCount === 0) return
        _powerProbePending = false
        _probeEpoch = _powerEpoch
        _probeSession = _sessionSerial
        _powerSource = "kscreen-doctor --dpms show"
        ++_powerProbeCount
        powerProbe.connectSource(_powerSource)
    }

    function powerProbeFinished(sourceName, data) {
        var succeeded = Number(data["exit code"]) === 0
        var stdout = String(data["stdout"] || "")
        powerProbe.disconnectSource(sourceName)
        if (sourceName !== _powerSource) return
        _powerSource = ""
        if (_powerDemand && _probeEpoch === _powerEpoch && _probeSession === _sessionSerial) {
            var parsed = Power.parseDisplayPower(succeeded ? stdout : "", _powerOutputs)
            _powerStates = parsed.states
            _powerHasResult = true
            _powerFailed = !succeeded
            _lastPowerProbeAt = Date.now()
            if (!_powerProbePending) powerTimer.restart()
        } else if (_powerDemand && consumerCount > 0) {
            _powerProbePending = true
        }
        if (_powerProbePending && _powerDemand && consumerCount > 0) powerDispatch.start()
    }

    function displayPowerState(outputName) {
        return Object.prototype.hasOwnProperty.call(_powerStates, outputName)
            ? _powerStates[outputName] : "unknown"
    }

    function powerIssue(outputName) {
        if (!_powerDemand || _powerOutputs.indexOf(outputName) < 0 || !_powerHasResult) return ""
        if (_powerFailed) return "failed"
        return displayPowerState(outputName) === "unknown" ? "unknown" : ""
    }

    function coverageDiagnostic(outputName) {
        var issue = coverageIssue(outputName)
        if (issue === "") return ""
        if (issue === "invalid")
            return i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn",
                "Invalid window-coverage estimate; unknown outputs use the partial frame-rate limit.")
        if (issue === "request-failed")
            return i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn",
                "Could not request the window-coverage estimate; unknown outputs use the partial frame-rate limit.")
        return i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn",
            "Window-coverage estimate unavailable for %1; unknown outputs use the partial frame-rate limit.", outputName)
    }

    function powerDiagnostic(outputName) {
        if (powerIssue(outputName) === "") return ""
        return i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn",
            "Display power could not be read for %1; treating this output as on.", outputName)
    }

    function lockDiagnostic() {
        if (consumerCount === 0 || _lockKnown) return ""
        return i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn",
            "Session lock state is unavailable.")
    }

    // Reading this property from the configuration page never registers a
    // consumer, enables a watcher, or starts a timer or executable source.
    function runtimeDiagnostics() {
        if (consumerCount === 0) return ""
        var messages = [lockDiagnostic()]
        for (var i = 0; i < _consumers.length; ++i) {
            var consumer = _consumers[i]
            if (consumer.visibilityMode !== "always")
                messages.push(coverageDiagnostic(consumer.outputName))
            if (consumer.checkDisplayPower)
                messages.push(powerDiagnostic(consumer.outputName))
        }
        return messages.filter(function(message, index) {
            return message !== "" && messages.indexOf(message) === index
        }).join("\n")
    }

    Component.onDestruction: {
        stopRuntime()
        if (_requestSource !== "") requester.disconnectSource(_requestSource)
        if (_powerSource !== "") powerProbe.disconnectSource(_powerSource)
    }
}
