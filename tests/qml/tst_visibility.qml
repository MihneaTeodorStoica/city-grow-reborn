// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Mihnea Teodor Stoica

import QtQuick
import QtTest
import "../../package/contents/ui" as CityUi

TestCase {
    name: "VisibilitySignalDispatch"

    function watcherFor(iface) {
        var objects = CityUi.RuntimeHub.resources
        for (var i = 0; i < objects.length; ++i) {
            if (objects[i].iface === iface) return objects[i]
        }
        fail("Missing real RuntimeHub watcher for " + iface)
        return null
    }

    function init() {
        compare(CityUi.RuntimeHub.consumerCount, 0)
    }

    function cleanup() {
        // Invoke only signal handlers that cannot query the bus without a live
        // consumer. Do not register consumers or call reloadConfig in fixtures.
        watcherFor("org.freedesktop.ScreenSaver").dbusActiveChanged(false)
        watcherFor("org.kde.KWin").dbusshowingDesktopChanged(false)
    }


    function test_nativeBooleanSignals() {
        var lock = watcherFor("org.freedesktop.ScreenSaver")
        var kwin = watcherFor("org.kde.KWin")
        var probes = CityUi.RuntimeHub.powerProbeCount
        var requests = CityUi.RuntimeHub.snapshotRequestCount

        lock.dbusActiveChanged(true)
        verify(CityUi.RuntimeHub.lockKnown)
        verify(CityUi.RuntimeHub.locked)
        lock.dbusActiveChanged(false)
        verify(!CityUi.RuntimeHub.locked)

        kwin.dbusshowingDesktopChanged(true)
        verify(CityUi.RuntimeHub.showDesktopKnown)
        verify(CityUi.RuntimeHub.showingDesktop)
        kwin.dbusshowingDesktopChanged(false)
        verify(!CityUi.RuntimeHub.showingDesktop)

        compare(CityUi.RuntimeHub.consumerCount, 0)
        compare(CityUi.RuntimeHub.powerProbeCount, probes)
        compare(CityUi.RuntimeHub.snapshotRequestCount, requests)
    }

    function test_diagnosticsArePassive() {
        var probes = CityUi.RuntimeHub.powerProbeCount
        var requests = CityUi.RuntimeHub.snapshotRequestCount
        compare(CityUi.RuntimeHub.diagnosticMessage, "")
        wait(20)
        compare(CityUi.RuntimeHub.consumerCount, 0)
        compare(CityUi.RuntimeHub.powerProbeCount, probes)
        compare(CityUi.RuntimeHub.snapshotRequestCount, requests)
        verify(!CityUi.RuntimeHub.powerProbeRunning)
        verify(!CityUi.RuntimeHub.coveragePending)
    }
}
