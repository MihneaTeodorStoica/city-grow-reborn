---
layout: default
title: City Grow Reborn
---

[Home]({{ '/' | relative_url }}) · [Installation]({{ '/installation.html' | relative_url }}) · [Customization]({{ '/customization.html' | relative_url }}) · [Performance]({{ '/performance.html' | relative_url }}) · [Troubleshooting]({{ '/troubleshooting.html' | relative_url }})

# City Grow Reborn

A KDE Plasma wallpaper with colorful, top-down branching lines and translucent blocks. It preserves City Grow's visual language rather than replacing it with an isometric city or illustrated map.

The rewrite separates a bounded, seeded simulation from tiled Canvas rendering. A companion KWin script estimates how much desktop space windows cover, so the wallpaper can run more slowly or stop when it is not visible. There is no permanent helper daemon, compiled plugin, root installer, or Plasma Store requirement.

**First supported target:** Plasma/KWin 6.8 or newer on Wayland. Older Plasma and X11 are not advertised as supported. Version 0.1.0 is the initial release.

**Verification status:** native appearance/settings, seven window-coverage cases, reload recovery, and matched resource samples passed. Covered city pixels freeze and uncovering resumes growth. The [verification record]({{ '/performance.html' | relative_url }}#verification-status) documents the measured CPU result and the unverified live Show Desktop, lock, display-off, and multi-output scenarios.

## Install without the store

Download the installer, inspect it, and run it separately:

```bash
curl -fLo install.sh https://mihneateodorstoica.github.io/city-grow-reborn/install.sh
less install.sh
bash install.sh
```

The installer installs two per-user packages and enables only its own visibility script. It does **not** choose your wallpaper, restart Plasma/KWin, run sudo, or change other scripts. Select **City Grow Reborn** in **Desktop and Wallpaper** afterward. The original City Grow package remains installed and untouched.

Read the [prerequisites, exact-version, offline, upgrade, and removal instructions]({{ '/installation.html' | relative_url }}) first. The hosted download and release routes become usable only after the first release and Pages deployment are published.

## Make it yours

- Original, Aurora, Ember, and Monochrome presets, plus Advanced controls.
- Solid, vertical-gradient, or local-image backgrounds.
- Independent growth speed and frame-rate limits; seeded repeatable cycles.
- Reverse, clear, or hold at the end of growth.
- Validated JSON recipe import/export without filesystem or clipboard helper processes.
- Isolated settings preview; changes reach the desktop only when applied.

[Explore customization]({{ '/customization.html' | relative_url }}).

## What “visible” means

Adaptive mode uses a **window-coverage estimate**, not pixel-exact compositor occlusion. Normal/dialog windows collectively covering at least 98% of an output's usable desktop area pause growth; 50–97% coverage reduces the frame cap. Scalar-transparent, minimized, hidden, other-desktop, and other-activity windows do not contribute. Per-pixel alpha, shaped surfaces, effects, and Overview exposure cannot reliably be inferred.

Use **VisibilityMode = always** if a translucent application is incorrectly counted as opaque. Lock, confirmed display-off, explicit invisibility, and manual pause still override it. Optional display-power probing is a small, explicit background cost; its default five-second interval also bounds wake detection latency.

## Source and attribution

[Source and releases](https://github.com/MihneaTeodorStoica/city-grow-reborn) · [Upstream City Grow](https://github.com/HobbyBlobby/PlasmaWallpaper_CityGrow) · [MIT license](https://github.com/MihneaTeodorStoica/city-grow-reborn/blob/main/LICENSE)

Based on City Grow by **Felix Lemke**, copyright 2024. Rewrite by **Mihnea Teodor Stoica**. Upstream history and MIT attribution are retained.
