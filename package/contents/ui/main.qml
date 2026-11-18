// SPDX-License-Identifier: MIT
// Copyright (c) 2024 Felix Lemke; 2026 Mihnea Teodor Stoica
import QtQuick
import QtQuick.Window
import org.kde.plasma.plasmoid

WallpaperItem {
    id: wallpaper
    // Explicit fields: KConfig may notify without changing object identity.
    property var settingsSnapshot: ({
        Preset: wallpaper.configuration.Preset,
        BackgroundMode: wallpaper.configuration.BackgroundMode,
        BackgroundColor: String(wallpaper.configuration.BackgroundColor),
        BackgroundColor2: String(wallpaper.configuration.BackgroundColor2),
        BackgroundImage: wallpaper.configuration.BackgroundImage,
        Palette: wallpaper.configuration.Palette,
        CustomColors: wallpaper.configuration.CustomColors,
        HueOffset: wallpaper.configuration.HueOffset,
        Scale: wallpaper.configuration.Scale,
        LineWidth: wallpaper.configuration.LineWidth,
        FillCity: wallpaper.configuration.FillCity,
        FillOpacity: wallpaper.configuration.FillOpacity,
        GrowthSpeed: wallpaper.configuration.GrowthSpeed,
        InitialBranches: wallpaper.configuration.InitialBranches,
        BranchProbability: wallpaper.configuration.BranchProbability,
        StraightProbability: wallpaper.configuration.StraightProbability,
        Density: wallpaper.configuration.Density,
        Seed: wallpaper.configuration.Seed,
        RandomizeEachCycle: wallpaper.configuration.RandomizeEachCycle,
        EndMode: wallpaper.configuration.EndMode,
        CycleDelay: wallpaper.configuration.CycleDelay,
        VisibilityMode: wallpaper.configuration.VisibilityMode,
        Paused: wallpaper.configuration.Paused,
        MaxFps: wallpaper.configuration.MaxFps,
        PartialFps: wallpaper.configuration.PartialFps,
        CheckDisplayPower: wallpaper.configuration.CheckDisplayPower,
        DisplayPowerInterval: wallpaper.configuration.DisplayPowerInterval
    })
    VisibilityController {
        id: visibility
        settings: wallpaper.settingsSnapshot
        outputName: wallpaper.Screen.name
        itemVisible: wallpaper.visible
    }
    CityView {
        id: city
        anchors.fill: parent
        settings: wallpaper.settingsSnapshot
        active: visibility.effectiveFps > 0
        fps: visibility.effectiveFps
    }
}
