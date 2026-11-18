// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihnea Teodor Stoica
import QtQuick
import QtQuick.Window
import "code/city.js" as City
import "code/settings.js" as Settings
import "code/render.js" as Render

Item {
    id: root
    property var settings: Settings.defaults()
    property bool active: true
    property int fps: 15
    readonly property real effectiveScale: _engine ? _engine.effectiveScale : 0
    readonly property int operationCount: _operationCount
    readonly property int paintCount: _paintCount
    readonly property bool budgetLimited: _budgetLimited
    readonly property string phase: _phase
    readonly property bool imageError: _values.BackgroundMode === "image" && _values.BackgroundImage !== "" && (!Settings.localImage(_values.BackgroundImage) || backgroundImage.status === Image.Error)
    readonly property var engine: _engine
    readonly property real deviceScale: Screen.devicePixelRatio || 1
    property var _engine: null
    property var _renderer: null
    property var _values: Settings.defaults()
    property string _topology: ""
    property string _appearance: ""
    property string _phase: "finished"
    property int _operationCount: 0
    property int _paintCount: 0
    property bool _budgetLimited: false
    property bool _ready: false
    property double _lastTick: 0
    property double _fraction: 0
    property double _delayRemaining: 0
    property double _delayStarted: 0
    clip: true

    function scheduleSettings() { if (_ready) Qt.callLater(applySettings); }
    function applySettings() {
        const values = Settings.defaults();
        Object.keys(values).forEach(function(key) {
            if (settings && Settings.validateValue(key, settings[key]) === "") values[key] = settings[key];
        });
        _values = values;
        const topology = JSON.stringify([width,height,deviceScale,values.Scale,values.Seed,values.InitialBranches,values.BranchProbability,values.StraightProbability,values.Density,values.EndMode]);
        const appearance = JSON.stringify([values.Palette,values.CustomColors,values.HueOffset,values.LineWidth,values.FillCity,values.FillOpacity]);
        if (topology !== _topology) {
            clock.stop(); cycleDelay.stop(); _fraction = 0; _delayRemaining = 0;
            _topology = topology;
            _engine = City.createEngine(values, Math.floor(Math.max(0,width)/(2*values.Scale)), Math.floor(Math.max(0,height)/(2*values.Scale)));
            _renderer = Render.createRenderer(_engine,Math.max(0,width),Math.max(0,height),deviceScale,512);
            _renderer.setStyle(values); _renderer.reset();
            _phase = _engine.phase;
            if (_phase === "holding") _delayRemaining = values.CycleDelay*1000;
        } else if (appearance !== _appearance && _renderer) {
            _renderer.setStyle(values);
        }
        _appearance = appearance;
        flushPaints(); updateActivity();
    }
    function flushPaints() {
        if (!_renderer) return;
        _renderer.flush(function(index,x,y,w,h) {
            const tile = tiles.itemAt(index);
            if (tile && tile.available) tile.markDirty(Qt.rect(x,y,w,h));
        });
    }
    function updateActivity() {
        if (!_ready || !_engine) return;
        if (!active || fps <= 0 || !visible) {
            clock.stop();
            if (cycleDelay.running) {
                _delayRemaining = Math.max(0,_delayRemaining-(Date.now()-_delayStarted));
                cycleDelay.stop();
            }
            _lastTick = 0;
            _engine.discardQueuedGenerations();
            return;
        }
        _lastTick = Date.now();
        if (_phase === "holding") {
            clock.stop();
            if (!cycleDelay.running) {
                cycleDelay.interval = Math.max(1,Math.ceil(_delayRemaining));
                _delayStarted = Date.now(); cycleDelay.start();
            }
        } else if (_phase === "growing" || _phase === "reversing") {
            cycleDelay.stop(); clock.start();
        } else { clock.stop(); cycleDelay.stop(); }
    }
    function tick() {
        if (!_engine || !active || fps <= 0 || !visible) return;
        const now = Date.now();
        const elapsed = Math.min(Math.max(0,now-_lastTick),Math.max(100,1000/fps));
        _lastTick = now;
        _fraction += elapsed*25*_values.GrowthSpeed/1000;
        const generations = Math.floor(_fraction); _fraction -= generations;
        _engine.queueGenerations(generations);
        const started = Date.now();
        let operations = 0;
        while (operations < 4096 && Date.now()-started < 4) {
            const done = _engine.step(Math.min(64,4096-operations));
            _renderer.sync(); operations += done;
            if (!done) break;
        }
        _operationCount += operations;
        _budgetLimited = (_engine.generationInProgress || _engine.queuedGenerations > 0) && (operations >= 4096 || Date.now()-started >= 4);
        _engine.discardQueuedGenerations();
        flushPaints();
        if (_phase !== _engine.phase) {
            _phase = _engine.phase;
            if (_phase === "holding") _delayRemaining = _values.CycleDelay*1000;
            updateActivity();
        }
    }
    onSettingsChanged: scheduleSettings()
    onWidthChanged: scheduleSettings()
    onHeightChanged: scheduleSettings()
    onDeviceScaleChanged: scheduleSettings()
    onActiveChanged: updateActivity()
    onFpsChanged: updateActivity()
    onVisibleChanged: updateActivity()
    Component.onCompleted: { _ready = true; applySettings(); }
    Component.onDestruction: { clock.stop(); cycleDelay.stop(); }

    Rectangle { anchors.fill: parent; color: root._values.BackgroundColor }
    Rectangle {
        anchors.fill: parent
        visible: root._values.BackgroundMode === "gradient"
        gradient: Gradient {
            GradientStop { position: 0; color: root._values.BackgroundColor }
            GradientStop { position: 1; color: root._values.BackgroundColor2 }
        }
    }
    Image {
        id: backgroundImage
        anchors.fill: parent
        visible: root._values.BackgroundMode === "image" && status === Image.Ready
        source: root._values.BackgroundMode === "image" && Settings.localImage(root._values.BackgroundImage) ? root._values.BackgroundImage : ""
        asynchronous: true
        sourceSize: Qt.size(Math.ceil(root.width*root.deviceScale),Math.ceil(root.height*root.deviceScale))
        fillMode: Image.PreserveAspectCrop
    }
    Repeater {
        id: tiles
        model: root._renderer ? root._renderer.tileCount : 0
        delegate: CanvasTile {
            required property int index
            x: root._renderer.tileColumns > 0 ? index % root._renderer.tileColumns * 512 : 0
            y: root._renderer.tileColumns > 0 ? Math.floor(index / root._renderer.tileColumns) * 512 : 0
            width: Math.max(0,Math.min(512,root.width-x))
            height: Math.max(0,Math.min(512,root.height-y))
            renderer: root._renderer
            tileIndex: index
            onPainted: root._paintCount++
        }
    }
    Timer {
        id: clock
        interval: Math.max(1,Math.ceil(1000/Math.max(1,root.fps)))
        repeat: true
        onTriggered: root.tick()
    }
    Timer {
        id: cycleDelay
        repeat: false
        onTriggered: {
            if (!root._engine || !root.active) return;
            const serial = root._engine.resetSerial;
            const seed = root._values.RandomizeEachCycle ? Math.floor(Math.random()*2147483648) : root._values.Seed;
            root._engine.advancePhase(seed);
            if (serial !== root._engine.resetSerial) { root._renderer.reset(); root.flushPaints(); }
            root._phase = root._engine.phase;
            root._delayRemaining = 0; root._fraction = 0;
            root.updateActivity();
        }
    }
}
