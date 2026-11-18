# City Grow Reborn

Colorful top-down branching lines and translucent blocks for KDE Plasma. A bounded,
seeded simulation and tiled Canvas rendering preserve City Grow's visual language;
an event-driven KWin companion supplies an adaptive **window-coverage estimate**.

First supported target: **Plasma/KWin 6.8+ on Wayland**. Initial version: **0.1.0**.

**Verification/publication status:** actual desktop proof, resource measurements,
and the hosted release route are pending. No CPU or power-saving result is claimed.
See the [verification record](docs/performance.md#verification-status).

## Install without the Plasma Store

Download, inspect, then run; no curl-pipe-shell, sudo, compiler, or session restart:

```bash
curl -fLo install.sh https://mihneateodorstoica.github.io/city-grow-reborn/install.sh
less install.sh
bash install.sh
```

Hosted routes become usable after the first tested release and Pages publication.
The installer resolves one exact stable tag, validates archive/checksums and both
package IDs, and rolls back both user packages and its enabled setting on failure.
It does not select a wallpaper or modify the original City Grow package. Select
**City Grow Reborn** in **Desktop and Wallpaper** afterward.

For a checkout or offline deployment:

```bash
bash docs/install.sh --local .
# No live KWin access or enabled-setting changes:
bash docs/install.sh --local . --no-enable
```

Exact releases: `bash install.sh --version v0.1.0`. Remove after selecting another
wallpaper: `bash install.sh --uninstall`. Only the two new user package IDs are
removed; saved wallpaper settings and unrelated packages remain.

Read [installation and prerequisites](docs/installation.md) before use.

## Controls and limits

- Original, Aurora, Ember, Monochrome presets and Advanced controls.
- Solid/vertical-gradient/local-image backgrounds; custom palettes and recipes.
- Independent speed and 15/5 fps default visible/partial caps.
- Covered/locked/off/manual-paused animation stops; resume keeps state.
- Isolated preview and validated, atomic JSON import/export.
- Optional shared DPMS probe every five seconds: a nonzero background cost, and
  wake detection can take up to that interval.

Coverage is not pixel-exact compositor occlusion: per-pixel alpha, shaped surfaces,
effects, Overview, panels, and tiny gaps have limits. `VisibilityMode=always` is
the override; lock/off/manual pause still apply. No permanent helper daemon,
native plugin, remote background downloads, analytics, or automatic updater.

## Documentation and development

[Hosted guide](https://mihneateodorstoica.github.io/city-grow-reborn/) ·
[Customization](docs/customization.md) · [Performance](docs/performance.md) ·
[Troubleshooting](docs/troubleshooting.md)

```bash
node --test tests/engine.test.cjs tests/coverage.test.cjs tests/recipes.test.cjs
for scale in 1 1.5; do
  QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_SCALE_FACTOR=$scale \
    qmltestrunner-qt6 -input tests/qml || exit
done
bash tests/installer.sh
python3 scripts/package.py --version v0.1.0 --output dist
```

These commands are the required checks, not a statement that they have passed.
QML testing requires Qt Quick Test and the development runner; Fedora provides it
in `qt6-qtdeclarative-devel`. Installer tests use real KPackage operations in private
XDG directories without a live KWin call. Packaging uses Python's standard library.

The tag workflow uses Fedora 45 and publishes the ZIP, canonical installer, and
SHA256SUMS only after all three behavior checks pass. Tag only after actual desktop
and resource proof too. GitHub Pages publishes Jekyll Minimal from `main:/docs`.
`Messages.sh` remains the translation-extraction entry point; no CMake/ECM build or
obsolete Qt5 install/restart scripts are required.

## Attribution

Forked from [HobbyBlobby/PlasmaWallpaper_CityGrow](https://github.com/HobbyBlobby/PlasmaWallpaper_CityGrow).
Original City Grow by **Felix Lemke**, copyright 2024; rewrite by
**Mihnea Teodor Stoica**. Original history and [MIT license](LICENSE) are retained.
