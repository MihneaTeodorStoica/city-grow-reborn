---
layout: default
title: Installation
---

[Home]({{ '/' | relative_url }}) · [Installation]({{ '/installation.html' | relative_url }}) · [Customization]({{ '/customization.html' | relative_url }}) · [Performance]({{ '/performance.html' | relative_url }}) · [Troubleshooting]({{ '/troubleshooting.html' | relative_url }})

# Installation

## Prerequisites

The first release targets **KDE Plasma/KWin >= 6.8 on Wayland**. Install these using your distribution's own package tools:

- Bash and Python 3.
- `kpackagetool6`, including the `Plasma/Wallpaper` and `KWin/Script` package structures.
- `plasmashell` and `kwin_wayland` (their `--version` output is checked).
- `dbus-send` and `kscreen-doctor`.
- Qt 6 QML modules `org.kde.plasma.plasma5support`, `org.kde.plasma.workspace.dbus`, and `Qt.labs.folderlistmodel`.
- For live enable/removal: `kwriteconfig6` and either `qdbus-qt6` or `qdbus6`, plus an active KWin session.
- For release downloads: `curl` and `sha256sum`.

The installer reports missing prerequisites **before** changing packages; it never runs a package manager or sudo. Names of the distribution packages vary. Qt module discovery uses the QML import path, `qtpaths6`/`qtpaths-qt6` when available, and standard Qt 6 library directories.

## Download, inspect, install

```bash
curl -fLo install.sh https://mihneateodorstoica.github.io/city-grow-reborn/install.sh
less install.sh
bash install.sh
```

Do not pipe an uninspected download into a shell. The default invocation resolves GitHub's latest stable release once, then downloads the ZIP and `SHA256SUMS` from **that same exact tag**. No stable release or a failed download is an error, not a fallback to an unversioned development snapshot.

To use one exact release:

```bash
bash install.sh --version v0.1.0
```

For an immutable installer source as well as a pinned payload:

```bash
curl -fLo install-v0.1.0.sh https://raw.githubusercontent.com/MihneaTeodorStoica/city-grow-reborn/v0.1.0/docs/install.sh
less install-v0.1.0.sh
bash install-v0.1.0.sh --version v0.1.0
```

[Browse the version-tagged installer source](https://github.com/MihneaTeodorStoica/city-grow-reborn/blob/v0.1.0/docs/install.sh) · [Release assets](https://github.com/MihneaTeodorStoica/city-grow-reborn/releases/tag/v0.1.0)

Pin both the installer source and payload when you need a reproducible version; the unversioned Pages installer tracks the maintained guide.

After installation, select **City Grow Reborn** in **Desktop and Wallpaper** on each desired output. Installation never selects it for you. The original `org.kde.plasma.citygrow` and unrelated wallpapers are not modified.

## Local or offline installation

From a checkout containing `package/` and `kwin-script/`:

```bash
bash docs/install.sh --local .
```

Or install a downloaded release ZIP:

```bash
bash install.sh --local city-grow-reborn-v0.1.0.zip
```

`--local` makes **no network requests**. If a local ZIP has a sibling `SHA256SUMS`, its checksum must match; a ZIP supplied alone still receives the full archive/ID/version checks.

For a machine without an active KWin session, or isolated deployment:

```bash
bash docs/install.sh --local . --no-enable
```

`--no-enable` installs/removes package files only: it does not read/write the KWin enabled setting, call the compositor, or unload/start scripts. It does not relax the installed runtime prerequisites. If deploying this way for real use, enable **City Grow Reborn Visibility** in System Settings → Window Management → KWin Scripts when a session is available. A file-only upgrade does not replace an already-loaded script instance; reload only this script later in KWin settings.

## Safety and upgrades

Both IDs are distinct from upstream:

| Package | User path, relative to `XDG_DATA_HOME` |
| --- | --- |
| Wallpaper | `plasma/wallpapers/io.github.mihneateodorstoica.citygrowreborn` |
| KWin script | `kwin/scripts/citygrow-reborn-visibility` |

`XDG_DATA_HOME` defaults to `~/.local/share`; `XDG_CONFIG_HOME` defaults to `~/.config`. Relative XDG paths are rejected. There is no global installation mode.

Before a mutation, both existing user copies and the script's `[Plugins] citygrow-reborn-visibilityEnabled` value are backed up in private temporary storage. A package-manager or enable failure restores both package copies and the prior setting. Same-version local replacements and explicit downgrades remove/install **inside that transaction**, because KPackage's upgrade policy does not accept them. An already-installed identical release version is a no-op; local same-version content changes are detected.

The first live installation enables only this helper. Upgrades preserve a preexisting disabled setting. The installer unloads only its own helper before replacement, requests KWin reconfiguration/start when needed, and never restarts KWin or plasmashell.

The helper implementation is installed in a content-addressed directory. Its small, fixed KWin entry point selects that directory through filesystem notifications, not polling. Live upgrades load the unique implementation URL before requesting normal script startup, avoiding KWin's retained QML component cache. This also applies to changed same-version local builds.

Plasma can retain the **wallpaper's** old QML until the next login; merely reselecting it does not guarantee updated code. After updating an already-running wallpaper, log out and back in when convenient. The installer does not restart the desktop, KWin, or applications.

Archives are rejected before extraction for absolute/traversing/backslash paths, duplicate members, file/directory collisions, symlinks, special files, encryption, unexpected roots, or excessive size. Both IDs and both metadata versions must match. Remote archives must also match the requested tag and release checksum. Checksums delivered from the same release detect corruption; they are **not independent authentication** against a compromised publishing account.

## Remove

First select another wallpaper on every desktop currently using City Grow Reborn:

```bash
bash install.sh --uninstall
```

A live uninstall refuses an active selection rather than silently changing it. It unloads only the replacement helper, deletes only its enabled key, and removes only the two replacement user packages. Saved wallpaper settings and the original City Grow package remain.

Offline file-only removal:

```bash
bash install.sh --uninstall --no-enable
```

This cannot inspect or unload the live session. Select another wallpaper first and, if the helper is loaded, disable/unload it through KWin settings afterward.

Modes `--version`, `--local`, and `--uninstall` are mutually exclusive. Unknown or conflicting arguments return nonzero.

## Building and verifying a release locally

The automated checks use the real engine, QML canvases, and KPackage tools:

```bash
node --test tests/engine.test.cjs tests/coverage.test.cjs tests/recipes.test.cjs
for scale in 1 1.5; do
  QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_SCALE_FACTOR=$scale \
    qmltestrunner-qt6 -input tests/qml || exit
done
bash tests/installer.sh
python3 scripts/package.py --version v0.1.0 --output dist
```

The development-only QML runner is supplied by Fedora's `qt6-qtdeclarative-devel`; an extracted same-version runner can be used by absolute path instead. The installer isolation test uses actual `kpackagetool6` in private XDG directories, deliberately fails the real second-package operation, and verifies rollback. It never accesses the live KWin service.

Packaging uses only Python's standard library. The ZIP contains `wallpaper/{metadata.json,contents/**}` and `kwin-script/{metadata.json,contents/**}`, including MIT notices. Historical ZIPs, Git metadata, tests, configuration, symlinks, and background images are excluded. Runtime source files use a narrow allowlist; custom backgrounds stay outside the package. `dist/` receives the ZIP, canonical `install.sh`, and checksums for both.

The tag workflow uses Fedora 45, runs all three behavior checks above, then packages and publishes those three assets. A release tag must be created **only after** actual desktop appearance/visibility/resource proof, not merely after headless tests. GitHub Pages uses the built-in Minimal theme from **`main:/docs`**; there is no local Rust/mdBook toolchain, analytics, or embedded live animation.
