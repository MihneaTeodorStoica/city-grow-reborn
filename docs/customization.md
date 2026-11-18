---
layout: default
title: Customization
---

[Home]({{ '/' | relative_url }}) · [Installation]({{ '/installation.html' | relative_url }}) · [Customization]({{ '/customization.html' | relative_url }}) · [Performance]({{ '/performance.html' | relative_url }}) · [Troubleshooting]({{ '/troubleshooting.html' | relative_url }})

# Customization

Open **Desktop and Wallpaper**, choose **City Grow Reborn**, and start with a style. The fixed **Look**, **Animation**, **Power**, and **Share** tabs keep related controls together. Each tab scrolls independently; mouse-wheel scrolling does not change numeric values or dropdown selections. Descriptions explain the controls, and probabilities/opacity are displayed as percentages instead of raw fractions.

**Show live preview** opens an isolated simulation, capped at 10 fps. It stops when hidden or when you leave Look. Changes reach the desktop only after **Apply**; **Cancel** discards unapplied edits.

## Presets

| Preset | Character and differences from Original |
| --- | --- |
| Original | Random hues, black background by default, translucent blocks; 3 initial branches, speed 1, line width 2. |
| Aurora | Mint/blue/lilac/gold; speed 0.6, 4 branches, branch probability 0.10. |
| Ember | Orange/gold/pink/red; speed 1.2, 5 branches, straight-run entry probability 0.18. |
| Monochrome | Cool gray/lavender; speed 0.5, line width 1.5, no block fill, branch probability 0.08. |
| Custom | The result of editing a preset-controlled field. |

Presets set palette/hue, scale/line/fill, speed/branching, density, end mode, and cycle delay. They preserve your background, custom-color list, seed/randomization choices, and all power controls. **Reset all settings** resets the complete form, not just the preset-controlled fields.

## Background and color

- **solid:** `BackgroundColor` beneath transparent city geometry.
- **gradient:** vertical `BackgroundColor` → `BackgroundColor2`.
- **image:** a local `file:` URL, asynchronously decoded and cropped to fill the output. Non-file URLs are rejected. Empty/missing/unreadable files fall back to `BackgroundColor` and show a warning without stopping growth.
- **original palette:** random hues with distinct main/offshoot lightness; children remain related to their parent.
- **custom palette:** use the color swatches in **Look → Advanced appearance** to choose 2–8 opaque colors. Recipes store them as a JSON list of `#RRGGBB` strings; you do not need to edit JSON to choose colors.

Palette, hue, line width, and fill edits redraw existing geometry. Scale, seed, and growth-rule edits rebuild only the affected simulation instance. Reverse removes city geometry to transparency, so nonblack backgrounds and images remain visible rather than being painted over with black.

## Advanced reference

These are the exact `General` recipe/configuration keys. Defaults apply to a fresh installation; preset changes preserve the independent fields described above.

| Key | Default | Allowed values / meaning |
| --- | --- | --- |
| `Preset` | `Original` | Original, Aurora, Ember, Monochrome, Custom. |
| `BackgroundMode` | `solid` | solid, gradient, image. |
| `BackgroundColor` | `#000000` | Opaque `#RRGGBB`. |
| `BackgroundColor2` | `#101827` | Opaque `#RRGGBB`. |
| `BackgroundImage` | empty | Empty or local `file:` URL. Machine-local path. |
| `Palette` | `original` | original, aurora, ember, monochrome, custom. |
| `CustomColors` | `["#66e3c4","#76a9fa","#bb9af7","#e0af68"]` | A **string containing JSON**, 2–8 opaque `#RRGGBB` colors. |
| `HueOffset` | 0 | Integer 0–359 degrees. |
| `Scale` | 3 | Integer 1–16; requested cell spacing = 2 × Scale logical pixels. |
| `LineWidth` | 2 | 0.5–8; effective width is capped below cell spacing. |
| `FillCity` | true | Draw translucent block fills. |
| `FillOpacity` | 0.25 | 0–1. |
| `GrowthSpeed` | 1 | 0.1–8; multiplies a 25-generation/second simulation clock. |
| `InitialBranches` | 3 | Integer 1–32. |
| `BranchProbability` | 0.15 | 0–0.5; straight-run branching uses the original 6/15 ratio. |
| `StraightProbability` | 0.12 | 0–1; chance of **entering straight-run mode**, not a neighbor weight. |
| `Density` | 1 | 0.1–1 occupied-grid fraction before growth stops. |
| `Seed` | 1 | Integer 0–2147483647. |
| `RandomizeEachCycle` | true | Choose one new seed at a cycle boundary, never on visibility resume. |
| `EndMode` | `reverse` | reverse, clear, hold. |
| `CycleDelay` | 1 | 0–300 seconds between cycling transitions. |
| `VisibilityMode` | `adaptive` | adaptive or always; always does not override lock/off/manual pause. |
| `Paused` | false | Manual pause. |
| `MaxFps` | 15 | Integer 1–30, independent of monitor refresh and growth speed. |
| `PartialFps` | 5 | Integer 1–30, effectively capped by MaxFps. |
| `CheckDisplayPower` | true | Optional shared read-only `kscreen-doctor --dpms show` probe. |
| `DisplayPowerInterval` | 5 | Integer 1–30 seconds; wake detection may take this long. |

With randomization disabled, identical seed, size, and topology settings repeat deterministically. Resuming never simulates hidden elapsed time. Generated cities are kept in memory only; logout or scene reconstruction starts a new configured cycle.

**Reverse** grows, waits, retracts each branch from its own tip, waits, then resets. Older offshoots retreat alongside longer branches, rather than waiting for one global newest-first stack. **Clear** grows, waits, then clears into a new cycle. **Hold** stops at completed growth. Holds/finished states stop the repeating animation timer. A paused cycle delay retains its remaining time.

The Original preset keeps the original two-stage growth order: existing branches split first, then the enlarged population moves, including newly created offshoots. Bounds, exclusive destination claims, and branch-local backtracking remain enforced. On very small grids, the density target reserves room for at least one visible segment instead of stopping at invisible seeds.

The occupancy grid is capped at 262,144 cells and live branches at 256 per wallpaper instance. Large outputs may require a larger effective spacing than requested; Advanced diagnostics report it. Operation budgeting can limit requested speed instead of accumulating catch-up work. See [performance and visibility limits]({{ '/performance.html' | relative_url }}).

## Share a recipe

Use the selectable export text area, or paste JSON into the import area. No helper process reads the clipboard or writes recipe files. Import validates the **whole** recipe before changing any field. Errors leave the existing form untouched.

Recipes are limited to 64 KiB and use version 1. Unknown keys, missing required keys, wrong types/ranges/enums, malformed colors, unsupported versions, and non-file image URLs are rejected. Nothing is evaluated as JavaScript. Background paths are machine-local and may need reselection on the destination computer.

A complete default recipe:

```json
{
  "version": 1,
  "settings": {
    "Preset": "Original",
    "BackgroundMode": "solid",
    "BackgroundColor": "#000000",
    "BackgroundColor2": "#101827",
    "BackgroundImage": "",
    "Palette": "original",
    "CustomColors": "[\"#66e3c4\",\"#76a9fa\",\"#bb9af7\",\"#e0af68\"]",
    "HueOffset": 0,
    "Scale": 3,
    "LineWidth": 2,
    "FillCity": true,
    "FillOpacity": 0.25,
    "GrowthSpeed": 1,
    "InitialBranches": 3,
    "BranchProbability": 0.15,
    "StraightProbability": 0.12,
    "Density": 1,
    "Seed": 1,
    "RandomizeEachCycle": true,
    "EndMode": "reverse",
    "CycleDelay": 1,
    "VisibilityMode": "adaptive",
    "Paused": false,
    "MaxFps": 15,
    "PartialFps": 5,
    "CheckDisplayPower": true,
    "DisplayPowerInterval": 5
  }
}
```
