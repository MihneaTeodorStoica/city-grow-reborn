#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mihnea Teodor Stoica
# Uses actual kpackagetool6, isolated XDG roots, and no live KWin service.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec python3 - "$root" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import warnings
import zipfile

ROOT = Path(sys.argv[1])
INSTALLER = ROOT / "docs/install.sh"
WALLPAPER = "io.github.mihneateodorstoica.citygrowreborn"
SCRIPT = "citygrow-reborn-visibility"
BASH = shutil.which("bash")
KPACKAGE = shutil.which("kpackagetool6")
if not BASH or not KPACKAGE:
    raise SystemExit("Installer isolation tests need Bash and actual kpackagetool6.")


def invoke(command, env, ok=True, contains=None):
    result = subprocess.run([str(value) for value in command], env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if (result.returncode == 0) != ok or (contains and contains not in result.stdout):
        raise AssertionError(f"Command: {command}\nExit: {result.returncode}\n{result.stdout}")
    return result.stdout


def install(env, *arguments, ok=True, contains=None):
    return invoke([BASH, INSTALLER, *arguments, "--no-enable"], env, ok, contains)


def files(path):
    if not path.exists():
        return None
    result = {}
    for child in sorted(path.rglob("*")):
        if child.is_symlink():
            result[str(child.relative_to(path))] = ("symlink", os.readlink(child))
        elif child.is_file():
            result[str(child.relative_to(path))] = hashlib.sha256(child.read_bytes()).hexdigest()
    return result


def targets(env):
    data = Path(env["XDG_DATA_HOME"])
    return (data / "plasma/wallpapers" / WALLPAPER, data / "kwin/scripts" / SCRIPT)


def snapshot(env):
    config = Path(env["XDG_CONFIG_HOME"])
    return tuple(files(path) for path in targets(env)) + (files(config),)


def assert_versions(env, version):
    for target, expected_id in zip(targets(env), (WALLPAPER, SCRIPT)):
        plugin = json.loads((target / "metadata.json").read_text())["KPlugin"]
        assert plugin["Id"] == expected_id and plugin["Version"] == version, plugin
        assert (target / "contents/ui/main.qml").is_file()
    target = targets(env)[1]
    entry = json.loads((target / "metadata.json").read_text())["X-CityGrow-Runtime"]
    assert re.fullmatch(r"runtime-[0-9a-f]{64}/ui/VisibilityRuntime\.qml", entry), entry
    assert (target / "contents" / entry).is_file()
    assert (target / "contents" / entry).parent.parent.joinpath("code/coverage.js").is_file()
    assert sorted(path.name for path in (target / "contents").glob("runtime-*")) == [entry.split("/")[0]]
    return entry


def repository(work, label, version, marker=""):
    fixture = work / label
    for source in ("package", "kwin-script"):
        (fixture / source).mkdir(parents=True)
        shutil.copyfile(ROOT / source / "metadata.json", fixture / source / "metadata.json")
        shutil.copytree(ROOT / source / "contents", fixture / source / "contents")
        metadata = fixture / source / "metadata.json"
        value = json.loads(metadata.read_text())
        value["KPlugin"]["Version"] = version
        metadata.write_text(json.dumps(value, indent=2) + "\n")
        if marker:
            entry = "VisibilityRuntime.qml" if source == "kwin-script" else "main.qml"
            main = fixture / source / "contents/ui" / entry
            with main.open("a") as output:
                output.write(f"\n// Isolation test variant: {marker}\n")
    (fixture / "scripts").mkdir()
    (fixture / "docs").mkdir()
    shutil.copyfile(ROOT / "scripts/package.py", fixture / "scripts/package.py")
    shutil.copyfile(INSTALLER, fixture / "docs/install.sh")
    return fixture


def package(fixture, output, version, env):
    invoke([sys.executable, fixture / "scripts/package.py", "--version", "v" + version,
            "--output", output], env)
    archive = output / f"city-grow-reborn-v{version}.zip"
    with zipfile.ZipFile(archive) as bundle:
        names = bundle.namelist()
        assert len(names) == len(set(names))
        assert all(name.startswith(("wallpaper/", "kwin-script/")) for name in names)
        assert all(name.endswith("metadata.json") or "/contents/" in name for name in names)
        assert not any(part in (".git", "tests") for name in names for part in name.split("/"))
        assert not any(name.lower().endswith((".png", ".jpg", ".jpeg", ".zip")) for name in names)
    for name in (archive.name, "install.sh"):
        digest = hashlib.sha256((output / name).read_bytes()).hexdigest()
        assert f"{digest}  {name}" in (output / "SHA256SUMS").read_text()
    return archive


def altered_archive(original, target, alter):
    with zipfile.ZipFile(original) as source:
        entries = [(entry, source.read(entry)) for entry in source.infolist()]
    entries = alter(entries)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)  # Duplicate-member fixtures are intentional.
        with zipfile.ZipFile(target, "w") as output:
            for entry, data in entries:
                output.writestr(entry, data)
    return target


def metadata_attack(entries, package_name, mutate):
    changed = []
    for entry, data in entries:
        if entry.filename == package_name + "/metadata.json":
            metadata = json.loads(data)
            mutate(metadata)
            data = json.dumps(metadata).encode()
        changed.append((entry, data))
    return changed


def configure_environment(work):
    env = dict(os.environ)
    for name in ("DBUS_SESSION_BUS_ADDRESS", "WAYLAND_DISPLAY", "DISPLAY", "QML_IMPORT_PATH", "QML2_IMPORT_PATH"):
        env.pop(name, None)
    env.update(HOME=str(work / "home"), XDG_DATA_HOME=str(work / "data"),
               XDG_CONFIG_HOME=str(work / "config"), XDG_CACHE_HOME=str(work / "cache"),
               XDG_STATE_HOME=str(work / "state"), XDG_RUNTIME_DIR=str(work / "runtime"),
               QT_QPA_PLATFORM="offscreen", LC_ALL="C")
    for name in ("HOME", "XDG_CONFIG_HOME", "XDG_RUNTIME_DIR"):
        Path(env[name]).mkdir(parents=True)
    Path(env["XDG_RUNTIME_DIR"]).chmod(0o700)
    config = Path(env["XDG_CONFIG_HOME"])
    (config / "wallpaper-settings-sentinel").write_text("preserve saved wallpaper settings\n")
    (config / "kwinrc").write_text("[Plugins]\ncitygrow-reborn-visibilityEnabled=false\nunrelated-scriptEnabled=true\n")
    for root, package_id in (("plasma/wallpapers", "org.kde.image"), ("kwin/scripts", "unrelated-test-script")):
        directory = Path(env["XDG_DATA_HOME"]) / root / package_id
        directory.mkdir(parents=True)
        (directory / "sentinel").write_text("unrelated package\n")
    return env


with tempfile.TemporaryDirectory(prefix="citygrow installer isolation ") as directory:
    work = Path(directory)
    env = configure_environment(work / "xdg")
    traps = work / "no live tools"
    traps.mkdir()
    log = work / "forbidden-calls"
    env["CITYGROW_FORBIDDEN_LOG"] = str(log)
    # These commands satisfy presence checks but must never be invoked in --no-enable/local mode.
    for name in ("qdbus-qt6", "qdbus6", "kwriteconfig6", "dbus-send", "kscreen-doctor", "curl"):
        trap = traps / name
        trap.write_text('#!/bin/sh\nprintf "%s\\n" "$0 $*" >> "$CITYGROW_FORBIDDEN_LOG"\nexit 95\n')
        trap.chmod(0o755)
    env["PATH"] = str(traps) + os.pathsep + os.environ["PATH"]
    baseline_config = files(Path(env["XDG_CONFIG_HOME"]))
    current_version = json.loads((ROOT / "package/metadata.json").read_text())["KPlugin"]["Version"]
    major, minor, patch = map(int, current_version.split("."))
    next_version = f"{major}.{minor}.{patch + 1}"
    initial = repository(work, "initial source", current_version)
    update = repository(work, "upgraded source", next_version)
    initial_zip = package(initial, work / "dist initial", current_version, env)
    update_zip = package(update, work / "dist update", next_version, env)
    # Identical sources create byte-identical archives; historical ZIPs cannot enter the bundle.
    again = package(initial, work / "dist again", current_version, env)
    assert initial_zip.read_bytes() == again.read_bytes()
    invoke([sys.executable, initial / "scripts/package.py", "--version", "v" + next_version,
            "--output", work / "must not package"], env, ok=False, contains="expected ID")

    install(env, "--local", initial_zip)
    assert_versions(env, current_version)
    before = snapshot(env)
    timestamps = tuple((path / "metadata.json").stat().st_mtime_ns for path in targets(env))
    install(env, "--local", initial_zip, contains="already installed")
    assert snapshot(env) == before
    assert timestamps == tuple((path / "metadata.json").stat().st_mtime_ns for path in targets(env))

    attacks = work / "attacks"
    attacks.mkdir()
    cases = []
    cases.append(altered_archive(initial_zip, attacks / "wrong-id.zip", lambda entries:
        metadata_attack(entries, "wallpaper", lambda value: value["KPlugin"].update(Id="org.kde.image"))))
    cases.append(altered_archive(initial_zip, attacks / "mismatched-version.zip", lambda entries:
        metadata_attack(entries, "kwin-script", lambda value: value["KPlugin"].update(Version=next_version))))
    cases.append(altered_archive(initial_zip, attacks / "runtime-override.zip", lambda entries:
        metadata_attack(entries, "kwin-script", lambda value: value.update(
            {"X-CityGrow-Runtime": "../../unrelated/main.qml"}))))
    for label, path in (("traversal", "wallpaper/contents/../../escaped"),
                        ("absolute", "/tmp/citygrow-unsafe-absolute"),
                        ("backslash", "wallpaper/contents/..\\escaped"),
                        ("unexpected-root", "unrelated/metadata.json")):
        cases.append(altered_archive(initial_zip, attacks / (label + ".zip"), lambda entries, path=path:
            entries + [(zipfile.ZipInfo(path), b"must not extract")]))
    cases.append(altered_archive(initial_zip, attacks / "duplicate.zip", lambda entries: entries + [entries[0]]))
    link = zipfile.ZipInfo("wallpaper/contents/link")
    link.create_system = 3
    link.external_attr = (stat.S_IFLNK | 0o777) << 16
    cases.append(altered_archive(initial_zip, attacks / "symlink.zip", lambda entries: entries + [(link, b"/tmp/elsewhere")]))
    for archive in cases:
        install(env, "--local", archive, ok=False)
        assert snapshot(env) == before, archive
    assert not (work / "escaped").exists()

    bad_sums = work / "bad checksum"
    bad_sums.mkdir()
    bad_archive = bad_sums / initial_zip.name
    shutil.copyfile(initial_zip, bad_archive)
    (bad_sums / "SHA256SUMS").write_text("0" * 64 + "  " + bad_archive.name + "\n")
    install(env, "--local", bad_archive, ok=False, contains="SHA256 mismatch")
    assert snapshot(env) == before
    install(env, "--local", initial, "--version", "v" + current_version, ok=False)
    install(env, "--unexpected", ok=False)
    install(env, "--version", "../bad", ok=False)
    assert snapshot(env) == before

    missing = work / "missing prerequisite"
    missing.mkdir()
    for binary in ("python3", "kpackagetool6", "dbus-send", "plasmashell", "kwin_wayland"):
        executable = shutil.which(binary, path=os.environ["PATH"])
        assert executable, f"Required test host prerequisite missing: {binary}"
        (missing / binary).symlink_to(executable)
    missing_env = dict(env, PATH=str(missing))
    install(missing_env, "--local", initial_zip, ok=False, contains="Missing prerequisites: kscreen-doctor")
    assert snapshot(env) == before

    fault = work / "real kpackage failure"
    fault.mkdir()
    fault_log = work / "kpackage-calls"
    wrapper = fault / "kpackagetool6"
    # Fault injection removes staged metadata immediately before the actual second package
    # call. The real kpackagetool6 performs both the first mutation and the second failure.
    # No package-manager success/failure return value is stubbed.
    wrapper.write_text(
        '#!/usr/bin/env python3\nimport json, os, pathlib, sys\n'
        f'real = {KPACKAGE!r}\nlog = pathlib.Path({str(fault_log)!r})\n'
        'args = sys.argv[1:]\n'
        'with log.open("a") as output: output.write(json.dumps(args) + "\\n")\n'
        'if "KWin/Script" in args:\n'
        '    for action in ("--install", "--upgrade"):\n'
        '        if action in args:\n'
        '            (pathlib.Path(args[args.index(action) + 1]) / "metadata.json").unlink()\n'
        'os.execv(real, [real, *args])\n'
    )
    wrapper.chmod(0o755)
    fault_env = dict(env, PATH=str(fault) + os.pathsep + env["PATH"])
    install(fault_env, "--local", update_zip, ok=False, contains="were restored")
    assert snapshot(env) == before, "Rollback did not restore both prior package copies/configuration"
    calls = [json.loads(line) for line in fault_log.read_text().splitlines()]
    assert any("Plasma/Wallpaper" in call and "--upgrade" in call for call in calls)
    assert any("KWin/Script" in call and "--upgrade" in call for call in calls)

    install(env, "--local", update_zip)
    previous_entry = assert_versions(env, next_version)
    assert files(Path(env["XDG_CONFIG_HOME"])) == baseline_config
    changed = repository(work, "same version changed source", next_version, marker="same-version replacement")
    install(env, "--local", changed)
    changed_entry = assert_versions(env, next_version)
    assert changed_entry != previous_entry, "Changed helper code must have a fresh QML URL"
    assert not (targets(env)[1] / "contents" / previous_entry).exists()
    for target, entry in zip(targets(env), ("ui/main.qml", changed_entry)):
        assert "same-version replacement" in (target / "contents" / entry).read_text()
    # Explicit local downgrade exercises remove/install rather than KPackage's version policy.
    install(env, "--local", initial_zip)
    assert_versions(env, current_version)
    install(env, "--uninstall")
    assert all(not target.exists() for target in targets(env))
    assert files(Path(env["XDG_CONFIG_HOME"])) == baseline_config
    for relative in ("plasma/wallpapers/org.kde.image", "kwin/scripts/unrelated-test-script"):
        assert (Path(env["XDG_DATA_HOME"]) / relative / "sentinel").read_text() == "unrelated package\n"
    # Also roll back an initial installation, where neither target existed before.
    empty_env = configure_environment(work / "empty xdg")
    empty_env.update(PATH=fault_env["PATH"], CITYGROW_FORBIDDEN_LOG=str(log))
    empty_before = snapshot(empty_env)
    install(empty_env, "--local", initial_zip, ok=False, contains="were restored")
    assert snapshot(empty_env) == empty_before
    assert not log.exists(), f"--no-enable/local unexpectedly called runtime/network tools: {log.read_text()}"
    print("Installer isolation passed: real install/upgrade/same-version replacement/downgrade/removal, archive/checksum rejection, both rollback cases, preserved settings/unrelated packages, and zero live KWin/network calls.")
PY
