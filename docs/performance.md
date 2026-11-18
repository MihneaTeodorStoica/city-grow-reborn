---
layout: default
title: Performance and visibility
---

[Home]({{ '/' | relative_url }}) · [Installation]({{ '/installation.html' | relative_url }}) · [Customization]({{ '/customization.html' | relative_url }}) · [Performance]({{ '/performance.html' | relative_url }}) · [Troubleshooting]({{ '/troubleshooting.html' | relative_url }})

# Performance and visibility

## Verification status

Behavior, native appearance/settings, helper coverage/reload, and matched CPU/GPU checks below have passed. Measurements are one session observation, not a general power-saving guarantee. Interactive and hardware limits are explicit.

| Evidence | Status |
| --- | --- |
| Deterministic engine, rectangle coverage, recipe behavior | Passed Node behavior checks; latest engine run: 20 passing tests. |
| Real QML raster/seam/undo tests at scale factors 1 and 1.5 | Passed on Qt 6.11.2. Additional palette stroke/alpha-fill cases and frame-by-frame branch reversal passed at both scales. |
| Actual isolated KPackage install/upgrade/rollback/removal | Passed, including changed same-version runtime URLs, obsolete-runtime removal, invalid override rejection, and both rollback cases. |
| Original/new appearance and settings Apply/Cancel/persistence | Native recipe preview/Apply/persistence/Cancel/reopen passed; original complete recipe restored afterward. Corrected palette colors also inspected on the running desktop. |
| Visible/partial/covered, tiled windows, reload recovery | Seven native cases passed: 25% normal-window coverage, half coverage, maximized, fullscreen, scalar opacity 0.8, minimized, and two opaque tiles. Unique-runtime/canonical-bootstrap reload and wallpaper deselection/reselection passed. Covered city pixels froze; uncovering resumed them. |
| Show Desktop | Policy fixtures passed; live scenario unverified. This session immediately reset Show Desktop with original City Grow, Reborn, and KDE Image, even without test windows. No specific cause established; publication with this documented limit was approved. |
| Lock/unlock | Policy fixtures passed; interactive lock/unlock not run. Never lock an unattended user's session. |
| Display-off state | Parser/policy fixtures passed; no hardware power-off was requested. |
| Multiple active outputs | Geometry fixtures passed; only DP-2 tested live. Disabled eDP-1 is not a live check. |
| Matched 30-second plasmashell + kwin_wayland CPU measurements | Completed; both processes included. See the session samples below. |
| Whole-desktop NVIDIA GPU power/utilization samples | Completed; noisy whole-desktop readings, not wallpaper-only watts. |
| Published Pages/release route and isolated version-pinned install | Pending publication and HTTPS proof. |

## Matched session samples — 2026-11-18

Host: Intel Core i9-13980HX, NVIDIA GeForce RTX 4090 Laptop GPU, Plasma/KWin 6.8.2, Qt 6.11.2, Wayland. DP-2 was 2560×1440 at 239.97 Hz, output scale 1, HDR enabled; eDP-1 was disabled. Each interval followed three seconds of warmup and lasted approximately 30 seconds.

Both wallpapers used three starting branches, wallpaper Scale 3, fills, a solid black background, and original-style growth at 25 generations/second. Original Smart Play was enabled. Reborn used the Original palette, GrowthSpeed 1, 15/5 fps caps, adaptive visibility, and the session's two-second display-power probe interval. This compares configured wallpapers, not the renderer alone: the original paints at approximately 25 fps.

The same two static GTK 3/XWayland test windows ran on an otherwise empty temporary workspace. A full-output scalar-opacity-0.8 window anchored focus; the opaque coverage window was minimized for visible samples and maximized for covered samples. Other user applications stayed open. ClickToFocus was temporary; the exact FocusFollowsMouse setting, wallpaper preferences, prior focus/workspace, and desktop count were restored afterward. No unrelated KWin scripts were disabled.

CPU is process CPU time divided by elapsed time: **100% means one CPU core**, not the whole machine. Combined CPU includes Plasma and KWin/helper cost.

| Wallpaper/state | Plasma CPU % | KWin CPU % | Combined CPU % | Whole-desktop GPU mean W | GPU mean utilization % |
| --- | ---: | ---: | ---: | ---: | ---: |
| Original visible | 31.00 | 6.82 | 37.82 | 38.09 | 9.60 |
| Original covered | 0.07 | 0.03 | 0.10 | 37.87 | 3.27 |
| Reborn visible | 12.52 | 4.03 | 16.55 | 36.34 | 7.37 |
| Reborn covered | 0.20 | 0.20 | 0.40 | 37.97 | 4.10 |

Visible combined CPU was **56.2% lower in this sample**. Both covered configurations were near idle; Reborn's measured process CPU was slightly higher, not zero. GPU samples included unrelated utilization spikes and overlapping power ranges: these results do **not** establish a GPU power reduction, wallpaper-attributable watts, or discrete-GPU wake behavior. A single run does not quantify variance or guarantee the same benefit on other scenes/hardware.

Decoded RGB snapshots confirmed that visible city geometry changed, covered city geometry remained identical, and minimizing the covering window resumed growth. The existing opaque weather widget was excluded from that comparison: its “Updated … ago” text changed even while the city was frozen. Raw whole-containment PNG inequality alone is not an animation test.

The first three intervals came from one continuous run. The final covered interval was collected separately after correcting that weather-widget comparison; the original covered Reborn snapshots also had no city-pixel changes. The 512-pixel tile setting was retained because visible CPU did not regress; 256/1024 variants were not measured.

## Scheduling policy

The default visible cap is **15 fps**, and the partial/unknown cap is **5 fps**, independent of a monitor's refresh rate. Simulation speed is separately controlled by `GrowthSpeed`: 25 original-style generations per active second at speed 1. More fps does not mean more simulation generations.

| Condition | Animation |
| --- | --- |
| Manual pause, confirmed screen lock, explicit QML invisibility, confirmed output-off | Stopped. |
| Adaptive mode and >=98% usable-area coverage | Stopped. |
| Adaptive mode and 50% to <98% coverage | min(MaxFps, PartialFps). |
| Unknown coverage/snapshot | Partial cap and a warning; never indefinitely frozen on stale data. |
| Visible, or VisibilityMode=always | MaxFps, still subject to lock/off/manual pause. |

Paused state retains its existing geometry and simulation position; hidden time does not accumulate. Once pending rendering has drained, stopped instances should perform zero simulation operations and zero animation paints. Holding/finished phases stop the repeating animation timer and use at most a single one-shot cycle-delay timer; pausing stops that timer as well.

Show Desktop explicitly overrides a stale window-coverage classification to visible. Coverage is discarded after KWin restart/reconfiguration, and a fresh snapshot is requested. An absent snapshot after two seconds is unknown rather than covered.

## Window-coverage estimate, not compositor occlusion

The companion uses event-driven KWin geometry/window/desktop/activity notifications coalesced over 100 ms. It computes the exact union of eligible rectangles separately for every active output, so overlapping windows are not double-counted and spanning windows contribute on both outputs. Panel struts are excluded by using the usable desktop area.

Only normal/dialog windows on that output's current desktop/activity contribute. Minimized, hidden, desktop/dock/special, or scalar-opacity-below-0.999 windows do not. More than 256 eligible windows or invalid geometry fails open to visible rather than falsely pausing.

This is deliberately a **window-coverage estimate**:

- Per-client alpha and shaped surfaces may expose wallpaper without detectable scalar opacity changes.
- Compositor effects and Overview exposure are not reliably represented.
- Tiny gaps below the 98% threshold and panel translucency are intentionally ignored.
- Use **VisibilityMode=always** if a translucent app is treated as opaque.

The companion suspends window tracking when no output selects this wallpaper. Coverage classifications are broadcast only when changed, or in response to a snapshot request, via a short-lived `dbus-send`; there is no persistent helper process.

## Display power and background cost

There is no verified public event-only DPMS API for the targeted runtime. One shared hub therefore runs **`kscreen-doctor --dpms show`** every `DisplayPowerInterval` seconds while it is useful and unlocked. The default is five seconds. It only reads state and never changes display power.

- A confirmed-off output performs no animation work.
- Wake detection may take up to the configured interval.
- Missing/unparseable per-output state is treated as unknown/visible and warns; it does not freeze the wallpaper.
- The probe stops while locked, with no live wallpaper instances, or when every instance is otherwise covered/manual-paused/explicitly invisible.
- An off-but-otherwise-visible output continues probing to detect wake.
- `CheckDisplayPower=false` disables the probe, not lock detection.

This optional periodic subprocess is a small but nonzero background cost. “Zero animation work” is not a claim of zero process wakeups or zero desktop power draw. Preview instances do not register with the shared live hub.

## Bounded simulation and rendering

Each wallpaper instance owns its seeded engine and occupancy data. The limits are 262,144 grid cells and 256 live branches. Requested cell spacing is increased when needed to stay within the grid cap; inspect the effective scale in Advanced diagnostics. Tiny/zero-size surfaces stop cleanly. Normal cycle resets reuse allocated buffers.

A callback is bounded to 4 ms or 4,096 elementary operations, whichever is reached first; backtracking counts against that budget. Work-budget saturation limits effective speed instead of building a hidden-time catch-up backlog. Reverse processes up to 50 segments per simulated generation, rotating through branch histories so old offshoots and newer branches retreat together. Surviving segments retain chronological paint order; sparse reversal never treats a removed segment as live.

Only changed 512-logical-pixel Canvas tiles are dirtied. Transparent tiles sit above static solid/gradient/image backgrounds. Undo clears to transparency and replays surviving geometry in the dirty area; it never erases with a background color. Painting does not advance randomness or the simulation.

Stroke and fill colors are precomputed as QColor values. Real raster checks cover Aurora, Ember, Monochrome, custom colors, original offshoot lightness, and translucent blending; this avoids Qt 6.11's rejected fractional-HSL CSS strings rendering black.

Qt 6.11 may recreate a **whole Canvas image texture** when it updates; a dirty rectangle does not guarantee a partial GPU upload. Tiling bounds that cost. The matched configured-wallpaper result above does not isolate the benefit of tiling from the different paint cadence.

## How resource comparisons must be recorded

1. Capture the original appearance and requested scale/branch settings before switching only the intended wallpaper containments. Preserve unrelated desktops and original packages.
2. Match original/replacement scale, branch count, drawing progress, output size, and compositor conditions. Comparing different simulation speeds is not evidence of a renderer improvement.
3. After warmup, measure matched **30-second visible** and **30-second covered** intervals. Sample CPU ticks for **both `plasmashell` and `kwin_wayland`** from `/proc`; helper cost must not disappear from the comparison.
4. If available, collect finite GPU samples:

   ```bash
   timeout 30 nvidia-smi --query-gpu=power.draw,utilization.gpu --format=csv -l 1
   ```

5. Record hardware, output geometry/refresh, Qt/Plasma/KWin versions, active apps, timing, progress, variation/noise, and whether display probing was enabled. GPU values are **whole-desktop readings**, not wallpaper-only watts. Renderer choice alone cannot establish whether a discrete GPU was woken.
6. Distinguish pure fixtures, offscreen QML tests, actual session observations, and interactive-only checks. Do not claim multi-output, lock, or DPMS hardware scenarios that were not actually exercised.

The first release must pass its reachable proof before publication. If a live smoke check fails, restore the original wallpaper on only the changed containment while fixing the replacement.
