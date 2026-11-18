// SPDX-License-Identifier: MIT
import QtQuick

Canvas {
    id: tile
    required property var renderer
    required property int tileIndex
    renderTarget: Canvas.Image
    renderStrategy: Canvas.Immediate
    antialiasing: true
    clip: true
    function reconstruct() {
        if (available && renderer && tileIndex < renderer.tileCount) { renderer.invalidate(tileIndex); requestPaint(); }
    }
    onAvailableChanged: reconstruct()
    onContextChanged: reconstruct()
    onRendererChanged: reconstruct()
    onPaint: function(region) {
        if (!renderer) return;
        renderer.paint(getContext("2d"), tileIndex, region);
    }
}
