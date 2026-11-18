// SPDX-License-Identifier: MIT
// Copyright (c) 2024 Felix Lemke; 2026 Mihnea Teodor Stoica
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls
import "code/settings.js" as Settings

ColumnLayout {
    id: root
    implicitWidth: 680
    implicitHeight: 360
    property var configDialog
    property var wallpaperConfiguration
    property string cfg_Preset: "Original"
    property string cfg_BackgroundMode: "solid"
    property color cfg_BackgroundColor: "#000000"
    property color cfg_BackgroundColor2: "#101827"
    property string cfg_BackgroundImage: ""
    property string cfg_Palette: "original"
    property string cfg_CustomColors: "[\"#66e3c4\",\"#76a9fa\",\"#bb9af7\",\"#e0af68\"]"
    property int cfg_HueOffset: 0
    property int cfg_Scale: 3
    property real cfg_LineWidth: 2
    property bool cfg_FillCity: true
    property real cfg_FillOpacity: 0.25
    property real cfg_GrowthSpeed: 1
    property int cfg_InitialBranches: 3
    property real cfg_BranchProbability: 0.15
    property real cfg_StraightProbability: 0.12
    property real cfg_Density: 1
    property int cfg_Seed: 1
    property bool cfg_RandomizeEachCycle: true
    property string cfg_EndMode: "reverse"
    property real cfg_CycleDelay: 1
    property string cfg_VisibilityMode: "adaptive"
    property bool cfg_Paused: false
    property int cfg_MaxFps: 15
    property int cfg_PartialFps: 5
    property bool cfg_CheckDisplayPower: true
    property int cfg_DisplayPowerInterval: 5
    property var snapshot: ({
        Preset: root.cfg_Preset,
        BackgroundMode: root.cfg_BackgroundMode,
        BackgroundColor: String(root.cfg_BackgroundColor),
        BackgroundColor2: String(root.cfg_BackgroundColor2),
        BackgroundImage: root.cfg_BackgroundImage,
        Palette: root.cfg_Palette,
        CustomColors: root.cfg_CustomColors,
        HueOffset: root.cfg_HueOffset,
        Scale: root.cfg_Scale,
        LineWidth: root.cfg_LineWidth,
        FillCity: root.cfg_FillCity,
        FillOpacity: root.cfg_FillOpacity,
        GrowthSpeed: root.cfg_GrowthSpeed,
        InitialBranches: root.cfg_InitialBranches,
        BranchProbability: root.cfg_BranchProbability,
        StraightProbability: root.cfg_StraightProbability,
        Density: root.cfg_Density,
        Seed: root.cfg_Seed,
        RandomizeEachCycle: root.cfg_RandomizeEachCycle,
        EndMode: root.cfg_EndMode,
        CycleDelay: root.cfg_CycleDelay,
        VisibilityMode: root.cfg_VisibilityMode,
        Paused: root.cfg_Paused,
        MaxFps: root.cfg_MaxFps,
        PartialFps: root.cfg_PartialFps,
        CheckDisplayPower: root.cfg_CheckDisplayPower,
        DisplayPowerInterval: root.cfg_DisplayPowerInterval
    })
    property string message: ""
    property bool assigning: false
    property var customPalette: {
        try { return JSON.parse(cfg_CustomColors); }
        catch (error) { return JSON.parse(Settings.schema.CustomColors.value); }
    }
    function setField(key, value) {
        const error = Settings.validateValue(key, value);
        if (error) { message = error; return; }
        if (String(root["cfg_" + key]) === String(value)) return;
        root["cfg_" + key] = value;
        message = "";
        if (!assigning && Settings.presetKeys.indexOf(key) >= 0) cfg_Preset = "Custom";
    }
    function assign(values) {
        assigning = true;
        Object.keys(values).forEach(function(key) { root["cfg_" + key] = values[key]; });
        assigning = false; message = "";
    }
    function applyPreset(name) { const values = Settings.preset(name); if (values) assign(values); }
    function setCustomColor(index, color) {
        const colors = customPalette.slice(); colors[index] = color;
        setField("CustomColors",JSON.stringify(colors));
    }
    function imageName() {
        if (!cfg_BackgroundImage) return i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "No image selected");
        try { return decodeURIComponent(cfg_BackgroundImage.split('/').pop()); }
        catch (error) { return cfg_BackgroundImage; }
    }
    TabBar {
        id: navigation
        objectName: "settingsNavigation"
        Layout.fillWidth: true
        TabButton { text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Look") }
        TabButton { text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Animation") }
        TabButton { text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Power") }
        TabButton { text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Share") }
    }
    StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        currentIndex: navigation.currentIndex
        Flickable {
            id: lookPage
            clip: true
            objectName: "lookScroll"
            contentWidth: width
            contentHeight: lookContent.implicitHeight
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ColumnLayout {
                id: lookContent
                width: Math.max(0,lookPage.width - Kirigami.Units.gridUnit)
                spacing: Kirigami.Units.smallSpacing
                ToolButton { id: previewToggle; objectName: "previewToggle"; checkable: true; text: checked ? i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Hide live preview") : i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Show live preview"); icon.name: "view-preview" }
                CityView {
                    id: preview
                    objectName: "settingsPreview"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 130
                    visible: previewToggle.checked
                    settings: root.snapshot
                    active: root.visible && previewToggle.checked && navigation.currentIndex === 0 && !root.cfg_Paused
                    fps: Math.min(10,root.cfg_MaxFps)
                }
                Label { visible: previewToggle.checked; Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.7; text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Preview only — the desktop changes when you press Apply.") }
                Kirigami.FormLayout { Layout.fillWidth: true
                    ComboBox {
                        objectName: "presetControl"
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Style:")
                        model: Settings.schema.Preset.choices
                        wheelEnabled: false
                        currentIndex: model.indexOf(root.cfg_Preset)
                        onActivated: root.applyPreset(currentText)
                    }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.7
                        text: root.cfg_Preset === 'Original' ? i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Vivid rainbow branches, like the original wallpaper.") : root.cfg_Preset === 'Aurora' ? i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Cool mint, blue and violet; gentle growth.") : root.cfg_Preset === 'Ember' ? i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Warm coral and gold; livelier growth.") : root.cfg_Preset === 'Monochrome' ? i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Quiet gray-blue lines, without filled blocks.") : i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Your own combination of colors and growth settings.")
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Background:")
                        rule: Settings.schema.BackgroundMode
                        value: root.snapshot.BackgroundMode
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Choose a flat color, a top-to-bottom blend, or a local image.")
                        visible: true
                        choiceLabels: [i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Solid color"),i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Vertical gradient"),i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Local image")]
                        onEdited: function(value) { root.setField("BackgroundMode", value); }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Color:")
                        rule: Settings.schema.BackgroundColor
                        value: root.snapshot.BackgroundColor
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Shown behind the lines, and used if an image cannot be loaded.")
                        visible: root.cfg_BackgroundMode !== "image"
                        
                        onEdited: function(value) { root.setField("BackgroundColor", value); }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Bottom color:")
                        rule: Settings.schema.BackgroundColor2
                        value: root.snapshot.BackgroundColor2
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "The gradient fades down to this color.")
                        visible: root.cfg_BackgroundMode === "gradient"
                        
                        onEdited: function(value) { root.setField("BackgroundColor2", value); }
                    }
                    RowLayout {
                        visible: root.cfg_BackgroundMode === "image"
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Image:")
                        Button { text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Choose image…"); onClicked: imageDialog.open() }
                        Label { Layout.fillWidth: true; text: root.imageName(); elide: Text.ElideMiddle; ToolTip.visible: hovered; property bool hovered: imageHover.hovered; ToolTip.text: root.cfg_BackgroundImage; HoverHandler { id: imageHover } }
                        ToolButton { icon.name: "edit-clear"; enabled: root.cfg_BackgroundImage !== ""; onClicked: root.setField("BackgroundImage",""); ToolTip.visible: hovered; ToolTip.text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Clear image") }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Fallback color:")
                        rule: Settings.schema.BackgroundColor
                        value: root.snapshot.BackgroundColor
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Shown behind the lines, and used if an image cannot be loaded.")
                        visible: root.cfg_BackgroundMode === "image"
                        
                        onEdited: function(value) { root.setField("BackgroundColor", value); }
                    }
                    RowLayout {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Line spacing:")
                        Slider { Layout.fillWidth: true; wheelEnabled: false; from:1; to:16; stepSize:1; value:root.cfg_Scale; onMoved:root.setField("Scale",Math.round(value)); ToolTip.visible: hovered; ToolTip.text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Larger spacing gives a coarser, less busy pattern.") }
                        Label { text: root.cfg_Scale*2 + " px" }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Translucent blocks:")
                        rule: Settings.schema.FillCity
                        value: root.snapshot.FillCity
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Adds translucent square blocks beside the lines. Turn off for lines only.")
                        visible: true
                        
                        onEdited: function(value) { root.setField("FillCity", value); }
                    }
                }
                Label { visible: preview.imageError; Layout.fillWidth: true; wrapMode: Text.Wrap; text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Image unavailable. The fallback color is shown instead.") }
                ToolButton { id: fineLook; checkable: true; text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Advanced appearance"); icon.name: checked ? "arrow-up" : "arrow-down" }
                Kirigami.FormLayout {
                    Layout.fillWidth: true; visible: fineLook.checked
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Line colors:")
                        rule: Settings.schema.Palette
                        value: root.snapshot.Palette
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Changes the colors without restarting the existing pattern.")
                        visible: true
                        choiceLabels: [i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Original rainbow"),i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Aurora"),i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Ember"),i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Monochrome"),i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Custom")]
                        onEdited: function(value) { root.setField("Palette", value); }
                    }
                    ColumnLayout {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Custom colors:")
                        visible: root.cfg_Palette === "custom"
                        Flow {
                            Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                            Repeater {
                                model: root.customPalette
                                delegate: KQuickControls.ColorButton {
                                    required property string modelData
                                    required property int index
                                    color: modelData
                                    property bool ready: false
                                    Component.onCompleted: ready = true
                                    onColorChanged: if (ready) root.setCustomColor(index,String(color))
                                }
                            }
                        }
                        RowLayout {
                            Button { text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Add color"); enabled: root.customPalette.length < 8; onClicked: root.setField("CustomColors",JSON.stringify(root.customPalette.concat(["#66e3c4"]))) }
                            Button { text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Remove last"); enabled: root.customPalette.length > 2; onClicked: root.setField("CustomColors",JSON.stringify(root.customPalette.slice(0,-1))) }
                        }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Hue rotation (degrees):")
                        rule: Settings.schema.HueOffset
                        value: root.snapshot.HueOffset
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Rotates every line color around the color wheel. Zero keeps the palette unchanged.")
                        visible: true
                        
                        onEdited: function(value) { root.setField("HueOffset", value); }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Line width (px):")
                        rule: Settings.schema.LineWidth
                        value: root.snapshot.LineWidth
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Stroke thickness in logical pixels; automatically kept narrower than the spacing.")
                        visible: true
                        
                        onEdited: function(value) { root.setField("LineWidth", value); }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Block opacity:")
                        rule: Settings.schema.FillOpacity
                        value: root.snapshot.FillOpacity
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "How strongly blocks cover the background: 0% is invisible, 100% is opaque.")
                        displayMultiplier: 100
                        decimalPlaces: 0
                        unit: "%"
                        visible: root.cfg_FillCity
                        
                        onEdited: function(value) { root.setField("FillOpacity", value); }
                    }
                }
            }
        }
        Flickable {
            id: animationPage
            clip: true
            objectName: "animationScroll"
            contentWidth: width
            contentHeight: animationContent.implicitHeight
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ColumnLayout {
                id: animationContent
                width: Math.max(0,animationPage.width - Kirigami.Units.gridUnit)
                spacing: Kirigami.Units.largeSpacing
                Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "How the pattern grows and what happens when it finishes.") }
                Kirigami.FormLayout { Layout.fillWidth: true
                    RowLayout {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Growth speed:")
                        Slider { Layout.fillWidth: true; wheelEnabled: false; from:0.1; to:8; stepSize:0.1; value:root.cfg_GrowthSpeed; onMoved:root.setField("GrowthSpeed",Math.round(value*10)/10) }
                        Label { text: root.cfg_GrowthSpeed.toFixed(1) + "×" }
                    }
                    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.7; text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "1× grows at about 25 turns per second. Higher values build faster; frame-rate limits are separate in Power.") }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "When complete:")
                        rule: Settings.schema.EndMode
                        value: root.snapshot.EndMode
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Rewind removes the newest lines first. Clear starts fresh. Keep stops after growth finishes.")
                        visible: true
                        choiceLabels: [i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Rewind, then grow again"),i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Clear, then grow again"),i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Keep the finished pattern")]
                        onEdited: function(value) { root.setField("EndMode", value); }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Rest between phases (seconds):")
                        rule: Settings.schema.CycleDelay
                        value: root.snapshot.CycleDelay
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Rest after growth and after rewinding, before the next phase starts.")
                        visible: root.cfg_EndMode !== "hold"
                        
                        onEdited: function(value) { root.setField("CycleDelay", value); }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "New pattern each cycle:")
                        rule: Settings.schema.RandomizeEachCycle
                        value: root.snapshot.RandomizeEachCycle
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "On: a different layout each cycle. Off: repeat the seed at the same size.")
                        visible: true
                        
                        onEdited: function(value) { root.setField("RandomizeEachCycle", value); }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Repeatable pattern seed:")
                        rule: Settings.schema.Seed
                        value: root.snapshot.Seed
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "The same seed, output size and growth settings produce the same layout.")
                        visible: !root.cfg_RandomizeEachCycle
                        
                        onEdited: function(value) { root.setField("Seed", value); }
                    }
                }
                ToolButton { id: fineGrowth; checkable: true; text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Advanced growth"); icon.name: checked ? "arrow-up" : "arrow-down" }
                Kirigami.FormLayout {
                    Layout.fillWidth: true; visible: fineGrowth.checked
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Starting branches:")
                        rule: Settings.schema.InitialBranches
                        value: root.snapshot.InitialBranches
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Independent starting points. More branches fill the screen from more places.")
                        visible: true
                        
                        onEdited: function(value) { root.setField("InitialBranches", value); }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Offshoot chance:")
                        rule: Settings.schema.BranchProbability
                        value: root.snapshot.BranchProbability
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Chance of a short side branch on each city-growth turn. Straight runs use 40% of this chance.")
                        displayMultiplier: 100
                        decimalPlaces: 0
                        unit: "%"
                        visible: true
                        
                        onEdited: function(value) { root.setField("BranchProbability", value); }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Straight-run chance:")
                        rule: Settings.schema.StraightProbability
                        value: root.snapshot.StraightProbability
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Chance of entering a straighter stretch, not the chance of each individual direction.")
                        displayMultiplier: 100
                        decimalPlaces: 0
                        unit: "%"
                        visible: true
                        
                        onEdited: function(value) { root.setField("StraightProbability", value); }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Coverage target:")
                        rule: Settings.schema.Density
                        value: root.snapshot.Density
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Stop at this share of occupied grid cells. Lower values leave more open space.")
                        displayMultiplier: 100
                        decimalPlaces: 0
                        unit: "%"
                        visible: true
                        
                        onEdited: function(value) { root.setField("Density", value); }
                    }
                }
            }
        }
        Flickable {
            id: powerPage
            clip: true
            objectName: "powerScroll"
            contentWidth: width
            contentHeight: powerContent.implicitHeight
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ColumnLayout {
                id: powerContent
                width: Math.max(0,powerPage.width - Kirigami.Units.gridUnit)
                spacing: Kirigami.Units.largeSpacing
                Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "The default caps are 15 fps when visible and 5 fps when partly covered. Covered, locked and confirmed display-off scenes stop animating.") }
                Kirigami.FormLayout { Layout.fillWidth: true
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Pause wallpaper:")
                        rule: Settings.schema.Paused
                        value: root.snapshot.Paused
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Stop the wallpaper until you turn this off. Its existing pattern is kept.")
                        visible: true
                        
                        onEdited: function(value) { root.setField("Paused", value); }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Window coverage:")
                        rule: Settings.schema.VisibilityMode
                        value: root.snapshot.VisibilityMode
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Automatic slows or stops behind opaque windows. The other option ignores coverage, but still respects lock and display-off.")
                        visible: true
                        choiceLabels: [i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Automatic power saving"),i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Animate behind windows too")]
                        onEdited: function(value) { root.setField("VisibilityMode", value); }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Visible frame-rate limit (fps):")
                        rule: Settings.schema.MaxFps
                        value: root.snapshot.MaxFps
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Maximum paint updates per second while visible. Lower uses less work; growth speed is unchanged.")
                        visible: true
                        
                        onEdited: function(value) { root.setField("MaxFps", value); }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Partly covered limit (fps):")
                        rule: Settings.schema.PartialFps
                        value: root.snapshot.PartialFps
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Used at 50–98% window coverage, or when coverage is unknown. Never exceeds the visible limit.")
                        visible: root.cfg_VisibilityMode === "adaptive"
                        
                        onEdited: function(value) { root.setField("PartialFps", value); }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Check whether the display is off:")
                        rule: Settings.schema.CheckDisplayPower
                        value: root.snapshot.CheckDisplayPower
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Reads display power using a short command. Turning this off removes that probe, but keeps lock pausing.")
                        visible: true
                        
                        onEdited: function(value) { root.setField("CheckDisplayPower", value); }
                    }
                    SettingControl {
                        Kirigami.FormData.label: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Display check interval (seconds):")
                        rule: Settings.schema.DisplayPowerInterval
                        value: root.snapshot.DisplayPowerInterval
                        explanation: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Seconds between power checks. Larger values wake less often, but can delay resume by that long.")
                        visible: root.cfg_CheckDisplayPower
                        
                        onEdited: function(value) { root.setField("DisplayPowerInterval", value); }
                    }
                }
                Label { Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.7; text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Window coverage is an estimate: transparent apps, shaped surfaces and effects may need “Animate behind windows too”. Display checks run a short command at the chosen interval; disabling them does not disable lock pausing.") }
                GroupBox {
                    title: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Status")
                    Layout.fillWidth: true
                    ColumnLayout {
                        anchors.fill: parent
                        Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: RuntimeHub.diagnosticMessage || i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "No visibility or display-power warnings.") }
                        Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn","Preview spacing: %1 px · operations: %2 · paints: %3",preview.effectiveScale*2,preview.operationCount,preview.paintCount) }
                        Label { visible: preview.budgetLimited; Layout.fillWidth: true; wrapMode: Text.Wrap; text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Work budget reached; growth is slowed rather than building a backlog.") }
                    }
                }
            }
        }
        Flickable {
            id: sharePage
            clip: true
            objectName: "shareScroll"
            contentWidth: width
            contentHeight: shareContent.implicitHeight
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ColumnLayout {
                id: shareContent
                width: Math.max(0,sharePage.width - Kirigami.Units.gridUnit)
                spacing: Kirigami.Units.largeSpacing
                Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Share every setting as a recipe. Image files are not included; choose them again on another computer.") }
                Label { text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Export — select and copy:"); font.bold: true }
                TextArea {
                    id: exportArea
                    objectName: "exportRecipe"
                    Layout.fillWidth: true; Layout.preferredHeight: 130
                    readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
                    text: Settings.exportRecipe(root.snapshot)
                }
                Button { text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Select recipe"); onClicked: { exportArea.forceActiveFocus(); exportArea.selectAll(); } }
                Label { text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Import — paste a recipe:"); font.bold: true }
                TextArea {
                    id: recipeInput
                    objectName: "importRecipe"
                    Layout.fillWidth: true; Layout.preferredHeight: 130
                    selectByMouse: true; wrapMode: TextEdit.Wrap
                    placeholderText: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Paste the complete recipe JSON here.")
                }
                Button {
                    text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Validate and load into preview")
                    onClicked: {
                        const result=Settings.parseRecipe(recipeInput.text);
                        if (result.ok) { root.assign(result.settings); root.message=i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Recipe loaded. Press Apply to use it on the desktop."); }
                        else root.message=result.error;
                    }
                }
            }
        }
    }
    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.message; visible: text.length>0 }
    Button { text: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Reset all settings"); onClicked: root.assign(Settings.defaults()) }
    FileDialog {
        id: imageDialog
        title: i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Choose a local background")
        nameFilters: [i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "Images (*.png *.jpg *.jpeg *.webp *.bmp *.svg)"),i18nd("plasma_wallpaper_io.github.mihneateodorstoica.citygrowreborn", "All files (*)")]
        onAccepted: root.setField("BackgroundImage",String(selectedFile))
    }
}
