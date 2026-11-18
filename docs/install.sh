#!/usr/bin/env bash
# City Grow Reborn — per-user installer, SPDX-License-Identifier: MIT
# Copyright (c) 2024 Felix Lemke
# Copyright (c) 2026 Mihnea Teodor Stoica
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
set -euo pipefail
if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' 'City Grow Reborn: missing prerequisite: Python 3 (python3).' >&2
    exit 1
fi
exec python3 - "$@" <<'PY'
import argparse
import glob
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import zipfile

REPO = "MihneaTeodorStoica/city-grow-reborn"
WALLPAPER_ID = "io.github.mihneateodorstoica.citygrowreborn"
SCRIPT_ID = "citygrow-reborn-visibility"
ENABLED_KEY = SCRIPT_ID + "Enabled"
PACKAGES = (
    ("wallpaper", WALLPAPER_ID, "Plasma/Wallpaper", "plasma/wallpapers"),
    ("kwin-script", SCRIPT_ID, "KWin/Script", "kwin/scripts"),
)
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+\Z")
TAG = re.compile(r"v[0-9]+\.[0-9]+\.[0-9]+\Z")
RUNTIME_ENTRY = re.compile(r"runtime-[0-9a-f]{64}/ui/VisibilityRuntime\.qml\Z")
RUNTIME_SUFFIXES = {".qml", ".js", ".xml", ".json", ".mo"}
MAX_ARCHIVE_SIZE = 128 * 1024 * 1024


class InstallError(Exception):
    pass


def run(args, timeout=60):
    try:
        result = subprocess.run(
            [str(arg) for arg in args], text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=timeout,
            env=dict(os.environ, LC_ALL="C"),
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise InstallError(f"Cannot run {args[0]}: {error}") from error
    if result.returncode:
        detail = (result.stderr + "\n" + result.stdout).strip()
        raise InstallError(f"{' '.join(map(str, args))} failed ({result.returncode}):\n{detail}")
    return result.stdout.strip()


def require_runtime(no_enable, network):
    required = ["kpackagetool6", "dbus-send", "kscreen-doctor", "plasmashell", "kwin_wayland"]
    if network:
        required += ["curl", "sha256sum"]
    qdbus = shutil.which("qdbus-qt6") or shutil.which("qdbus6")
    if not no_enable:
        required += ["kwriteconfig6"]
        if not qdbus:
            required += ["qdbus-qt6 (or qdbus6)"]
    missing = [name for name in required if not shutil.which(name)]
    if missing:
        raise InstallError("Missing prerequisites: " + ", ".join(missing) +
                           ". Install them with your distribution's tools; this installer never uses sudo.")
    for binary in ("plasmashell", "kwin_wayland"):
        reported = run([binary, "--version"])
        match = re.search(r"\b(\d+)\.(\d+)(?:\.\d+)?\b", reported)
        if not match or tuple(map(int, match.groups())) < (6, 8):
            raise InstallError(f"Plasma/KWin >= 6.8 is required; {binary} reported: {reported!r}")
    roots = []
    for variable in ("QML_IMPORT_PATH", "QML2_IMPORT_PATH"):
        roots.extend(Path(value) for value in os.environ.get(variable, "").split(os.pathsep) if value)
    qtpaths = shutil.which("qtpaths6") or shutil.which("qtpaths-qt6")
    if qtpaths:
        roots.append(Path(run([qtpaths, "--query", "QT_INSTALL_QML"])))
    roots.extend(Path(value) for pattern in (
        "/usr/lib*/qt6/qml", "/usr/lib/*/qt6/qml", "/usr/local/lib*/qt6/qml",
    ) for value in glob.glob(pattern))
    absent = [module for module in ("org/kde/plasma/plasma5support", "org/kde/plasma/workspace/dbus",
                                   "Qt/labs/folderlistmodel")
              if not any((root / module / "qmldir").is_file() for root in roots)]
    if absent:
        raise InstallError("Missing Qt 6 QML modules: " + ", ".join(absent) +
                           ". Install your distribution's Plasma and Qt declarative QML packages.")
    types = run(["kpackagetool6", "--list-types"])
    for _, _, package_type, _ in PACKAGES:
        if package_type not in types:
            raise InstallError(f"kpackagetool6 is missing the {package_type} package structure.")
    return qdbus


def load_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise InstallError(f"Invalid JSON in {path}: {error}") from error


def validate_package(path, package_id, package_type, installed=False):
    if path.is_symlink() or not path.is_dir():
        raise InstallError(f"Expected a real package directory: {path}")
    manifest = load_json(path / "metadata.json")
    plugin = manifest.get("KPlugin", {}) if isinstance(manifest, dict) else {}
    if not isinstance(plugin, dict) or plugin.get("Id") != package_id:
        raise InstallError(f"Wrong package ID in {path}; expected {package_id}.")
    version = plugin.get("Version")
    if not isinstance(version, str) or not VERSION.fullmatch(version):
        raise InstallError(f"Invalid stable metadata version in {path}: {version!r}")
    if manifest.get("KPackageStructure") != package_type:
        raise InstallError(f"Wrong package structure in {path}; expected {package_type}.")
    if not (path / "contents/ui/main.qml").is_file():
        raise InstallError(f"Missing contents/ui/main.qml in {path}.")
    if package_type == "KWin/Script" and manifest.get("X-Plasma-API") != "declarativescript":
        raise InstallError(f"Expected a declarative KWin script in {path}.")
    if package_type == "KWin/Script":
        if "X-CityGrow-Runtime" in manifest:
            entry = manifest["X-CityGrow-Runtime"]
            if not installed or not isinstance(entry, str) or not RUNTIME_ENTRY.fullmatch(entry):
                raise InstallError(f"Invalid or reserved installed runtime entry in {path}.")
            contents = path / "contents"
            runtimes = sorted(child.name for child in contents.iterdir() if child.name.startswith("runtime-"))
            if runtimes != [entry.split("/")[0]] or not (contents / entry).is_file():
                raise InstallError(f"Expected exactly one complete versioned runtime in {path}.")
        elif not installed and not (path / "contents/ui/VisibilityRuntime.qml").is_file():
            raise InstallError(f"Missing canonical visibility runtime in {path}.")
    return version


def source_files(package):
    metadata = package / "metadata.json"
    contents = package / "contents"
    if metadata.is_symlink() or contents.is_symlink() or not metadata.is_file() or not contents.is_dir():
        raise InstallError(f"Invalid package source: {package}")
    yield metadata
    for path in sorted(contents.rglob("*")):
        relative = path.relative_to(contents)
        if path.is_symlink() or any(part.startswith(".") or part in ("tests", "__pycache__") for part in relative.parts):
            raise InstallError(f"Refusing symlink, hidden, or non-runtime source: {path}")
        if path.is_dir():
            continue
        if not path.is_file() or (path.suffix not in RUNTIME_SUFFIXES and path.name not in ("qmldir", "LICENSE", "COPYING")):
            raise InstallError(f"Unexpected runtime file (background images belong outside the package): {path}")
        yield path


def stage_directory(source, destination):
    for name, package_id, package_type, _ in PACKAGES:
        package = source / ("package" if name == "wallpaper" else name)
        validate_package(package, package_id, package_type)
        files = list(source_files(package))
        for path in files:
            target = destination / name / path.relative_to(package)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)


def extract_archive(archive, destination):
    try:
        with zipfile.ZipFile(archive) as bundle:
            entries = bundle.infolist()
            if len(entries) > 4096 or sum(entry.file_size for entry in entries) > MAX_ARCHIVE_SIZE:
                raise InstallError("Release archive exceeds the bounded package size.")
            seen = {}
            for entry in entries:
                name = entry.orig_filename
                parts = name.rstrip("/").split("/")
                mode = stat.S_IFMT(entry.external_attr >> 16)
                if (not name or "\x00" in name or "\\" in name or name.startswith("/") or
                        any(part in ("", ".", "..") or ":" in part for part in parts) or
                        mode not in (0, stat.S_IFREG, stat.S_IFDIR) or entry.flag_bits & 1):
                    raise InstallError(f"Unsafe archive entry: {name!r}")
                canonical = "/".join(parts)
                if canonical in seen:
                    raise InstallError(f"Duplicate archive entry: {name!r}")
                if parts[0] not in ("wallpaper", "kwin-script"):
                    raise InstallError(f"Unexpected archive root: {name!r}")
                allowed = (len(parts) == 1 and entry.is_dir()) or (
                    len(parts) == 2 and parts[1] == "metadata.json" and not entry.is_dir()
                ) or (len(parts) >= 2 and parts[1] == "contents")
                if (not allowed or (mode == stat.S_IFDIR and not entry.is_dir()) or
                        (mode == stat.S_IFREG and entry.is_dir())):
                    raise InstallError(f"Unexpected archive path: {name!r}")
                seen[canonical] = entry.is_dir()
            for name in seen:
                for parent in PurePosixPath(name).parents:
                    if str(parent) in seen and not seen[str(parent)]:
                        raise InstallError(f"File/directory collision in archive: {name!r}")
            # No extraction starts until every entry has passed the path/type checks.
            for entry in entries:
                target = destination.joinpath(*entry.filename.rstrip("/").split("/"))
                if entry.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with bundle.open(entry) as incoming, target.open("xb") as outgoing:
                        shutil.copyfileobj(incoming, outgoing)
    except (zipfile.BadZipFile, RuntimeError, EOFError) as error:
        raise InstallError(f"Invalid release ZIP: {error}") from error


def check_checksum(archive, checksum_file, external=False):
    matches = []
    for line in checksum_file.read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"([a-fA-F0-9]{64}) [ *](.+)", line)
        if match and match.group(2) == archive.name:
            matches.append(match.group(1).lower())
    if len(matches) != 1:
        raise InstallError(f"SHA256SUMS must contain exactly one checksum for {archive.name}.")
    digest = run(["sha256sum", archive]).split()[0] if external else file_hash(archive)
    if digest != matches[0]:
        raise InstallError(f"SHA256 mismatch for {archive.name}; nothing was installed.")


def file_hash(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def download(url, target):
    run(["curl", "--fail", "--location", "--silent", "--show-error", "--proto", "=https",
         "--proto-redir", "=https", "--tlsv1.2", "--max-time", "120", "--output", target, url], timeout=130)


def remote_archive(tag, temporary):
    if tag is None:
        release_file = temporary / "release.json"
        download(f"https://api.github.com/repos/{REPO}/releases/latest", release_file)
        release = load_json(release_file)
        if not isinstance(release, dict) or release.get("draft") or release.get("prerelease"):
            raise InstallError("GitHub did not return a stable release.")
        tag = release.get("tag_name")
        if not isinstance(tag, str) or not TAG.fullmatch(tag):
            raise InstallError("No supported stable release is available.")
    archive = temporary / f"city-grow-reborn-{tag}.zip"
    base = f"https://github.com/{REPO}/releases/download/{tag}"
    download(f"{base}/SHA256SUMS", temporary / "SHA256SUMS")
    download(f"{base}/{archive.name}", archive)
    # Network installs use sha256sum against the strictly parsed exact-tag manifest.
    check_checksum(archive, temporary / "SHA256SUMS", external=True)
    return archive, tag[1:]


def xdg_directory(variable, default):
    value = Path(os.environ.get(variable) or str(Path.home() / default))
    if not value.is_absolute():
        raise InstallError(f"{variable} must be an absolute path.")
    return value.resolve()


def read_enabled(config):
    if not config.exists():
        return None
    group = ""
    values = []
    for line in config.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            group = stripped
            if group.startswith("[Plugins][$"):
                raise InstallError(f"Cannot safely change a flagged KConfig group: {group!r}")
        elif group == "[Plugins]" and "=" in line and not stripped.startswith(("#", ";")):
            key, value = line.split("=", 1)
            if key.strip().split("[")[0] == ENABLED_KEY:
                if key.strip() != ENABLED_KEY:
                    raise InstallError(f"Cannot safely change a flagged KConfig key: {key!r}")
                values.append(value)
    if len(values) > 1:
        raise InstallError(f"Duplicate {ENABLED_KEY} entries in {config}.")
    return values[0] if values else None


def tree_hash(path):
    digest = hashlib.sha256()
    for child in sorted(path.rglob("*")):
        if child.is_symlink():
            return None
        if child.is_file():
            digest.update(child.relative_to(path).as_posix().encode("utf-8") + b"\0")
            digest.update(bytes.fromhex(file_hash(child)))
    return digest.hexdigest()


def version_runtime(package):
    # KWin hardcodes ui/main.qml and retains its compiled QML after unloading.
    # Keep that bootstrap stable; put the implementation at a content-unique URL.
    contents = package / "contents"
    digest = tree_hash(contents)
    if digest is None:
        raise InstallError("Refusing a symlink in the staged visibility runtime.")
    relative = f"runtime-{digest}/ui/VisibilityRuntime.qml"
    runtime = contents / relative
    runtime.parent.mkdir(parents=True)
    (contents / "ui/VisibilityRuntime.qml").rename(runtime)
    (contents / "code").rename(runtime.parent.parent / "code")
    metadata = package / "metadata.json"
    manifest = load_json(metadata)
    manifest["X-CityGrow-Runtime"] = relative
    metadata.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


class LiveKWin:
    def __init__(self, executable, config):
        self.executable = executable
        self.config = config

    def scripting(self, method, *arguments):
        return run([self.executable, "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting." + method, *arguments])

    def loaded(self):
        answer = self.scripting("isScriptLoaded", SCRIPT_ID).lower()
        if answer not in ("true", "false"):
            raise InstallError(f"Unexpected KWin scripting response: {answer!r}")
        return answer == "true"

    def unload(self):
        if self.loaded() and self.scripting("unloadScript", SCRIPT_ID).lower() != "true":
            raise InstallError("KWin could not unload the City Grow Reborn visibility script.")

    def reconfigure(self):
        run([self.executable, "org.kde.KWin", "/KWin", "org.kde.KWin.reconfigure"])

    def set_enabled(self, value):
        command = ["kwriteconfig6", "--file", self.config, "--group", "Plugins", "--key", ENABLED_KEY]
        run(command + (["--delete"] if value is None else [value]))
        if read_enabled(self.config) != value:
            raise InstallError("KWin's enabled setting did not persist (possibly immutable configuration).")

    def reject_active_uninstall(self):
        script = ('var active = false; var all = desktops(); '
                  'for (var i = 0; i < all.length; ++i) { '
                  f'if (all[i].wallpaperPlugin === "{WALLPAPER_ID}") active = true; '
                  '} print(active ? "citygrow-active" : "citygrow-inactive");')
        answer = run([self.executable, "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", script])
        if "citygrow-active" in answer:
            raise InstallError("Select another wallpaper on every City Grow Reborn desktop before uninstalling; no selection was changed.")
        if "citygrow-inactive" not in answer:
            raise InstallError("Could not establish the active wallpaper. Select another wallpaper, then use --no-enable for offline removal if needed.")

    def load_runtime(self, script_path):
        if self.loaded():
            return
        entry = load_json(script_path / "metadata.json").get("X-CityGrow-Runtime", "ui/main.qml")
        if entry != "ui/main.qml" and (not isinstance(entry, str) or not RUNTIME_ENTRY.fullmatch(entry)):
            raise InstallError("Invalid installed visibility runtime entry.")
        script_id = self.scripting("loadDeclarativeScript", script_path / "contents" / entry, SCRIPT_ID)
        if not re.fullmatch(r"\d+", script_id):
            raise InstallError(f"KWin failed to load the visibility runtime: {script_id!r}")
        run([self.executable, "org.kde.KWin", f"/Scripting/Script{script_id}", "run"])

    def restore_loaded(self, previously_loaded, script_path):
        if previously_loaded:
            self.load_runtime(script_path)
        self.reconfigure()
        if not previously_loaded:
            self.unload()


def remove_path(path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def transact(staged, data_home, config_home, temporary, local, uninstall, live):
    records = []
    versions = []
    for name, package_id, package_type, relative_root in PACKAGES:
        root = data_home / relative_root
        target = root / package_id
        if target.is_symlink() or (target.exists() and not target.is_dir()):
            raise InstallError(f"Refusing to replace a symlink or non-directory: {target}")
        old_version = validate_package(target, package_id, package_type, installed=True) if target.exists() else None
        new_version = None if uninstall else validate_package(staged / name, package_id, package_type, installed=True)
        if new_version:
            versions.append(new_version)
        same = old_version == new_version and old_version is not None
        unchanged = same and (not local or tree_hash(target) == tree_hash(staged / name))
        needed = target.exists() if uninstall else not unchanged
        records.append(dict(name=name, package_id=package_id, package_type=package_type, root=root,
                            target=target, old_version=old_version, new_version=new_version, needed=needed))
    if versions and len(set(versions)) != 1:
        raise InstallError("Wallpaper and KWin script metadata versions do not match.")
    if not any(record["needed"] for record in records) and not uninstall:
        print(f"City Grow Reborn {versions[0]} is already installed; no changes made.")
        return
    prior_enabled = read_enabled(config_home / "kwinrc") if live else None
    previously_loaded = live.loaded() if live else False
    if live and uninstall:
        live.reject_active_uninstall()
    desired_enabled = prior_enabled
    if live and not uninstall and records[1]["old_version"] is None and prior_enabled is None:
        desired_enabled = "true"
    # Finish both backups before touching either installed package or KWin setting.
    for record in records:
        backup = temporary / "backup" / record["name"]
        if record["target"].exists():
            shutil.copytree(record["target"], backup, symlinks=True)
        record["backup"] = backup
    try:
        if live and (uninstall or records[1]["needed"]):
            live.unload()
        for record in records:
            if not record["needed"]:
                continue
            record["root"].mkdir(parents=True, exist_ok=True)
            command = ["kpackagetool6", "--type", record["package_type"], "--packageroot", record["root"]]
            if uninstall:
                run(command + ["--remove", record["package_id"]])
                continue
            old = record["old_version"]
            new = record["new_version"]
            if old and tuple(map(int, new.split("."))) <= tuple(map(int, old.split("."))):
                # KPackage rejects same-version upgrades/downgrades. This stays inside rollback.
                run(command + ["--remove", record["package_id"]])
                old = None
            run(command + (["--upgrade"] if old else ["--install"]) + [staged / record["name"]])
            installed_version = validate_package(record["target"], record["package_id"], record["package_type"], installed=True)
            if installed_version != new:
                raise InstallError(f"KPackage installed {installed_version}, expected {new}.")
        if live:
            live.set_enabled(None if uninstall else desired_enabled)
            if not uninstall and desired_enabled is not None and desired_enabled.lower() == "true":
                # Reserve this ID with fresh code before KWin's normal startup
                # can load its cached canonical entry point.
                live.load_runtime(records[1]["target"])
            live.reconfigure()
            if not uninstall:
                live.scripting("start")
    except BaseException as original:
        rollback_errors = []
        if live:
            try:
                live.unload()
            except Exception as error:
                rollback_errors.append(str(error))
        for record in records:
            try:
                remove_path(record["target"])
                if record["backup"].exists():
                    record["target"].parent.mkdir(parents=True, exist_ok=True)
                    shutil.copytree(record["backup"], record["target"], symlinks=True)
            except Exception as error:
                rollback_errors.append(f"Restoring {record['package_id']}: {error}")
        if live:
            try:
                live.set_enabled(prior_enabled)
            except Exception as error:
                rollback_errors.append(str(error))
            try:
                live.restore_loaded(previously_loaded, records[1]["target"])
            except Exception as error:
                rollback_errors.append(str(error))
        detail = "\nRollback errors: " + "\n".join(rollback_errors) if rollback_errors else "\nBoth user package copies and the prior enabled setting were restored."
        raise InstallError(f"Installation/removal failed: {original}{detail}") from original
    if uninstall:
        print("Removed only City Grow Reborn's two user packages. Saved wallpaper settings and original packages were left untouched.")
    else:
        print(f"Installed City Grow Reborn {versions[0]} for this user. Select it in Desktop and Wallpaper settings; your current wallpaper was not changed.")
    if not live:
        print("--no-enable: no KWin configuration or live compositor calls were made. Select another wallpaper before removing an active installation.")


def main():
    parser = argparse.ArgumentParser(description="Install City Grow Reborn for the current user; never uses sudo or changes the selected wallpaper.")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--version", metavar="vX.Y.Z", help="install one exact stable release (default: resolve latest stable once)")
    mode.add_argument("--local", metavar="PATH", help="repository root or release ZIP; no network access")
    mode.add_argument("--uninstall", action="store_true", help="remove only the two new user packages")
    parser.add_argument("--no-enable", action="store_true", help="offline file-only operation: do not read/write KWin settings or call its live service")
    args = parser.parse_args()
    if args.version and not TAG.fullmatch(args.version):
        parser.error("--version must be a stable tag such as v0.1.0")
    network = not args.local and not args.uninstall
    qdbus = require_runtime(args.no_enable, network)
    data_home = xdg_directory("XDG_DATA_HOME", ".local/share")
    config_home = xdg_directory("XDG_CONFIG_HOME", ".config")
    live = None if args.no_enable else LiveKWin(qdbus, config_home / "kwinrc")
    if live:
        try:
            live.loaded()
        except InstallError as error:
            raise InstallError(f"An active KWin session is required for enabling/removal. Use --no-enable for offline deployment.\n{error}") from error
    with tempfile.TemporaryDirectory(prefix="citygrow-reborn-") as work:
        temporary = Path(work)
        staged = temporary / "staged"
        expected_version = None
        if not args.uninstall:
            if args.local:
                source = Path(args.local).expanduser().resolve()
                if source.is_dir():
                    stage_directory(source, staged)
                elif source.is_file():
                    sums = source.parent / "SHA256SUMS"
                    if sums.exists():
                        check_checksum(source, sums)
                    extract_archive(source, staged)
                else:
                    raise InstallError(f"Local repository or ZIP does not exist: {source}")
            else:
                archive, expected_version = remote_archive(args.version, temporary)
                extract_archive(archive, staged)
            versions = [validate_package(staged / name, package_id, package_type)
                        for name, package_id, package_type, _ in PACKAGES]
            if len(set(versions)) != 1 or (expected_version and versions[0] != expected_version):
                raise InstallError("Package metadata versions do not match each other or the requested release tag.")
            version_runtime(staged / "kwin-script")
        transact(staged, data_home, config_home, temporary, bool(args.local), args.uninstall, live)


def stop_requested(*_):
    raise KeyboardInterrupt("terminated")


signal.signal(signal.SIGTERM, stop_requested)
try:
    main()
except (InstallError, OSError, UnicodeError, ValueError, KeyboardInterrupt) as error:
    print(f"City Grow Reborn: {error}", file=sys.stderr)
    sys.exit(1)
PY
