// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Mihnea Teodor Stoica

import QtQuick

QtObject {
    id: controller

    property var settings: ({})
    property string outputName: ""
    property bool itemVisible: true

    readonly property bool locked: RuntimeHub.locked
    readonly property bool lockKnown: RuntimeHub.lockKnown
    readonly property bool showingDesktop: RuntimeHub.showingDesktop
    readonly property int consumerCount: RuntimeHub.consumerCount
    readonly property string coverageState: RuntimeHub.coverageState(outputName)
    readonly property string displayPowerState: checkDisplayPower
        ? RuntimeHub.displayPowerState(outputName) : "disabled"
    readonly property string pauseReason: {
        if (manuallyPaused) return "manual"
        if (lockKnown && locked) return "locked"
        if (!itemVisible) return "invisible"
        if (checkDisplayPower && displayPowerState === "off") return "display-off"
        if (!alwaysVisible && !showingDesktop && coverageState === "covered") return "covered"
        return ""
    }
    readonly property int effectiveFps: {
        if (pauseReason !== "") return 0
        return alwaysVisible || showingDesktop || coverageState === "visible"
            ? maximumFps : Math.min(maximumFps, partialFps)
    }

    readonly property string coverageWarning: alwaysVisible ? "" : RuntimeHub.coverageDiagnostic(outputName)
    readonly property string powerWarning: !checkDisplayPower || manuallyPaused || !itemVisible || (lockKnown && locked)
        ? "" : RuntimeHub.powerDiagnostic(outputName)
    readonly property string lockWarning: consumerToken > 0 ? RuntimeHub.lockDiagnostic() : ""
    readonly property string diagnosticMessage: [coverageWarning, powerWarning, lockWarning]
        .filter(function(message) { return message !== "" }).join("\n")

    readonly property int maximumFps: integerSetting("MaxFps", 15, 1, 30)
    readonly property int partialFps: integerSetting("PartialFps", 5, 1, 30)
    readonly property int displayPowerInterval: integerSetting("DisplayPowerInterval", 5, 1, 30)
    readonly property bool manuallyPaused: settings && settings.Paused === true
    readonly property bool alwaysVisible: settings && settings.VisibilityMode === "always"
    readonly property bool checkDisplayPower: !settings || settings.CheckDisplayPower !== false
    readonly property var consumerOptions: ({
        outputName: outputName,
        itemVisible: itemVisible,
        paused: manuallyPaused,
        visibilityMode: alwaysVisible ? "always" : "adaptive",
        checkDisplayPower: checkDisplayPower,
        displayPowerInterval: displayPowerInterval
    })
    property int consumerToken: 0

    function integerSetting(key, fallback, minimum, maximum) {
        var value = settings && settings[key] !== undefined ? Number(settings[key]) : fallback
        return isFinite(value) ? Math.max(minimum, Math.min(maximum, Math.round(value))) : fallback
    }

    function syncConsumer() {
        if (consumerToken > 0) RuntimeHub.updateConsumer(consumerToken, consumerOptions)
    }

    onConsumerOptionsChanged: syncConsumer()
    Component.onCompleted: consumerToken = RuntimeHub.registerConsumer(consumerOptions)
    Component.onDestruction: {
        if (consumerToken > 0) RuntimeHub.unregisterConsumer(consumerToken)
    }
}
