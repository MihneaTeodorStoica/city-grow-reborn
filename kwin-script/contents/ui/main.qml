// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Mihnea Teodor Stoica

import QtQuick
import Qt.labs.folderlistmodel

// KWin caches this fixed entry point across script reloads. Directory changes
// select a content-addressed implementation without a timer or a second copy.
Loader {
    id: bootstrap

    function selectRuntime() {
        if (runtimes.status !== FolderListModel.Ready) return
        var directory = ""
        for (var i = 0; i < runtimes.count; ++i) {
            var name = runtimes.get(i, "fileName")
            if (!/^runtime-[0-9a-f]{64}$/.test(name)) continue
            if (directory !== "") {
                source = ""
                console.error("City Grow Reborn: multiple installed visibility runtimes")
                return
            }
            directory = name
        }
        source = Qt.resolvedUrl(directory !== ""
            ? "../" + directory + "/ui/VisibilityRuntime.qml"
            : "VisibilityRuntime.qml")
    }

    FolderListModel {
        id: runtimes
        folder: Qt.resolvedUrl("../")
        showFiles: false
        showDotAndDotDot: false
        onStatusChanged: bootstrap.selectRuntime()
        onCountChanged: bootstrap.selectRuntime()
    }
}
