---
layout: default
title: Troubleshooting
---

[Home]({{ '/' | relative_url }}) · [Installation]({{ '/installation.html' | relative_url }}) · [Customization]({{ '/customization.html' | relative_url }}) · [Performance]({{ '/performance.html' | relative_url }}) · [Troubleshooting]({{ '/troubleshooting.html' | relative_url }})

# Troubleshooting

Behavior, installer, and native settings/helper checks are recorded on the [performance page]({{ '/performance.html' | relative_url }}#verification-status). Distinguish those observations from numerical measurements and hardware states that were not exercised when reporting a problem.

## Installer refuses prerequisites

Read the reported missing commands/modules. The target is Plasma/KWin 6.8+ on Wayland; the installer checks both version binaries and Qt 6 module directories. Install missing components with your distribution tools and rerun. No sudo or package-manager action is performed automatically.

On a headless/offline system, use `--no-enable`; a normal installation needs an active KWin session and the session bus. This option bypasses live enable/removal, **not** installed runtime prerequisites. Do not run the per-user installer as root.

## Release or guide returns 404

Check the exact repository, version tag, and Pages URL shown in the installation guide. For development, use the repository's `bash docs/install.sh --local . --no-enable` in an isolated XDG environment. Do not substitute an unrelated download mirror.

For a maintainer, verify Pages is configured for branch **main**, path **/docs**, with the built-in `jekyll-theme-minimal`; `_config.yml` has `/city-grow-reborn` as its base URL. Tag release assets are the ZIP, `install.sh`, and `SHA256SUMS`.

## Checksum, archive, or metadata failure

Nothing should replace the installed packages when preflight validation fails. Re-download the ZIP and its matching exact-tag `SHA256SUMS`. Do not mix checksum files across releases or edit the manifest to bypass an error. Same-channel checksums detect corruption, not independently authenticated compromise.

Local directories must have the two expected IDs and matching stable metadata versions. For development, both metadata versions must match the tag supplied to `scripts/package.py`. Symlinks, unexpected runtime files, and local background images are deliberately rejected by the source packager.

If a package-manager or enable step fails, the installer reports rollback. Preserve the complete message. A rollback-error message means restoration itself hit an error; inspect the two replacement user package paths and the single KWin enabled key before retrying. The installer never restores unrelated files or rewrites your selected wallpaper.

## Wallpaper did not appear after installation

Installation does not choose a wallpaper. Open **Desktop and Wallpaper** and select **City Grow Reborn** for the desired output. Original City Grow remains a separate choice.

If package files were installed with `--no-enable`, enable **City Grow Reborn Visibility** under System Settings → Window Management → KWin Scripts for adaptive coverage. This does not require restarting KWin or plasmashell. Do not disable unrelated scripts as a troubleshooting step.

Read-only package information:

```bash
kpackagetool6 --type Plasma/Wallpaper --show io.github.mihneateodorstoica.citygrowreborn
kpackagetool6 --type KWin/Script --show citygrow-reborn-visibility
```

When diagnosing a custom `XDG_DATA_HOME`, run those commands in that same environment.

If an update seems to retain old wallpaper behavior, Plasma may still hold its compiled QML. Reselecting the wallpaper is not a reliable cache flush. Log out and back in when convenient; never restart KWin in a Wayland session just to refresh wallpaper code. The companion's content-addressed implementation is refreshed by a live installer upgrade without restarting KWin.

## Animation is stopped or slower than expected

Check **Paused**, **EndMode=hold**, output lock/off state, and Advanced diagnostics. Adaptive mode pauses at >=98% usable-area coverage and uses the partial cap from 50%. Unknown coverage intentionally runs at the partial cap with a warning.

**GrowthSpeed** and **MaxFps** are independent. Frame-rate caps are not monitor-refresh promises. The bounded operation budget may limit requested speed on demanding scenes rather than accumulating unbounded work. Holding/reversing delays are expected transitions; pause preserves the delay remainder.

Minimizing/moving a covering window or using Show Desktop should resume the existing state without replaying hidden time. A missing companion or stale snapshot should warn and use the partial rate, not remain frozen. Report an actual failure with the output name and helper status.

In the verification session, Show Desktop immediately reset with the original wallpaper, Reborn, and KDE Image, including without test windows. Its live resume scenario remains unverified; this observation does not identify a Reborn-specific cause. See the [verification limits]({{ '/performance.html' | relative_url }}#verification-status).

## A translucent window incorrectly pauses growth

The policy is a **window-coverage estimate**, not pixel-exact occlusion. Scalar opacity is detectable; per-pixel alpha, shaped surfaces, effects, Overview, panel translucency, and tiny gaps have documented limits. Set **VisibilityMode=always** as the override. Manual pause, lock, and confirmed output-off remain enforced.

## Display wakes but animation resumes late

The optional read-only DPMS probe defaults to five seconds; wake detection can take up to `DisplayPowerInterval`. Missing/unparseable state fails open with a warning. To inspect the observed format without changing display state:

```bash
kscreen-doctor --dpms show
```

Expected lines look like `dpms mode for screen DP-2: on`. Do not issue power-off commands merely to troubleshoot. `CheckDisplayPower=false` disables this probe while keeping lock pausing.

## Missing image or black/nonblack background problem

Use the local file picker, or a local `file:` URL. Remote URLs are rejected. An empty, missing, or unreadable image must fall back to **BackgroundColor** with a warning; it must not stop the simulation. Check that the current user can read the file. A path shared in a recipe may only exist on the original machine.

Reverse is supposed to clear the city to transparency, revealing the current solid/gradient/image background. If you see black erasure over a colored background, report the palette, line/fill settings, output scale, and end mode; do not change your background to hide the defect.

## Recipe rejected or edits disappeared

Import requires one complete version-1 recipe under 64 KiB, only known keys, correct types/ranges, opaque `#RRGGBB` colors, and a local-or-empty image URL. `CustomColors` is a JSON **string**, not an array at the outer recipe level. The inline error should leave the form unchanged.

Settings preview changes are intentionally isolated until **Apply**. **Cancel** discards them. Choosing a named preset preserves independent background/seed/power fields; editing a controlled field marks it Custom. See a [complete valid recipe]({{ '/customization.html' | relative_url }}#share-a-recipe).

## Removal refuses an active wallpaper

Select another wallpaper on every affected desktop, then rerun `bash install.sh --uninstall`. The installer will not silently change the selected wallpaper. `--no-enable` is an offline escape hatch, not a way to safely unload a live active scene: unload/disable only the replacement helper separately when needed.

Saved wallpaper settings are deliberately left in place; original City Grow and unrelated packages/scripts must remain unchanged.

## Useful evidence for a report

Include Plasma/KWin/Qt versions, Wayland session, output names/sizes/scales, recipe with private background paths removed, exact installer output, and whether the issue is reproducible in a preview or live desktop. Recent logs can be read without restarting the session:

```bash
journalctl --user --since '5 minutes ago' --no-pager
```

Review logs for private window titles/paths before posting. The project has no telemetry or analytics. [Open an issue](https://github.com/MihneaTeodorStoica/city-grow-reborn/issues).
