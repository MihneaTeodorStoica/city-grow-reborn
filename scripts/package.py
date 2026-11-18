#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mihnea Teodor Stoica
"""Build the two-package release without compilers or third-party Python modules."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = (
    ("package", "wallpaper", "io.github.mihneateodorstoica.citygrowreborn", "Plasma/Wallpaper"),
    ("kwin-script", "kwin-script", "citygrow-reborn-visibility", "KWin/Script"),
)
RUNTIME_SUFFIXES = {".qml", ".js", ".xml", ".json", ".mo"}


def package_files(source, package_id, package_type, version):
    if source.is_symlink() or not source.is_dir():
        raise ValueError(f"Not a real source package directory: {source}")
    metadata = source / "metadata.json"
    contents = source / "contents"
    if metadata.is_symlink() or contents.is_symlink() or not metadata.is_file() or not contents.is_dir():
        raise ValueError(f"Missing regular metadata.json or contents directory in {source}")
    manifest = json.loads(metadata.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict) or not isinstance(manifest.get("KPlugin"), dict):
        raise ValueError(f"Invalid KPlugin metadata: {source}")
    plugin = manifest["KPlugin"]
    if plugin.get("Id") != package_id or plugin.get("Version") != version:
        raise ValueError(f"{source}: expected ID {package_id} and metadata Version {version}")
    if manifest.get("KPackageStructure") != package_type:
        raise ValueError(f"{source}: expected KPackageStructure {package_type}")
    if package_type == "KWin/Script" and manifest.get("X-Plasma-API") != "declarativescript":
        raise ValueError(f"{source}: expected a declarative KWin script")
    if not (contents / "ui/main.qml").is_file() or not (contents / "LICENSE").is_file():
        raise ValueError(f"{source}: contents/ui/main.qml and contents/LICENSE are required")
    files = [metadata]
    for path in sorted(contents.rglob("*")):
        relative = path.relative_to(contents)
        if path.is_symlink() or any(part.startswith(".") or part in ("tests", "__pycache__") for part in relative.parts):
            raise ValueError(f"Refusing symlink, hidden, or non-runtime path: {path}")
        if path.is_dir():
            continue
        if not path.is_file() or (path.suffix not in RUNTIME_SUFFIXES and path.name not in ("qmldir", "LICENSE", "COPYING")):
            raise ValueError(f"Unexpected runtime file (do not bundle local backgrounds): {path}")
        files.append(path)
    return files


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="stable tag, for example v0.1.0")
    parser.add_argument("--output", type=Path, default=Path("dist"))
    args = parser.parse_args()
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", args.version):
        parser.error("--version must have the form vX.Y.Z")
    version = args.version[1:]
    inputs = [(source, name, package_files(ROOT / source, package_id, package_type, version))
              for source, name, package_id, package_type in PACKAGES]
    installer = ROOT / "docs/install.sh"
    if installer.is_symlink() or not installer.is_file():
        raise ValueError("The canonical docs/install.sh must be a regular file")
    output = args.output.resolve()
    for source, _, _ in inputs:
        source_path = (ROOT / source).resolve()
        if output == source_path or source_path in output.parents:
            raise ValueError("Release output must not be inside either source package")
    output.mkdir(parents=True, exist_ok=True)
    archive_name = f"city-grow-reborn-{args.version}.zip"
    # Fixed timestamps and modes make identical sources produce identical ZIP bytes.
    with tempfile.TemporaryDirectory(prefix=".citygrow-release-", dir=output) as work:
        temporary = Path(work)
        archive = temporary / archive_name
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
            for source, name, files in inputs:
                for path in files:
                    relative = path.relative_to(ROOT / source).as_posix()
                    info = zipfile.ZipInfo(f"{name}/{relative}", date_time=(1980, 1, 1, 0, 0, 0))
                    info.create_system = 3
                    info.external_attr = (stat.S_IFREG | 0o644) << 16
                    info.compress_type = zipfile.ZIP_DEFLATED
                    bundle.writestr(info, path.read_bytes(), compresslevel=9)
        shutil.copyfile(installer, temporary / "install.sh")
        (temporary / "install.sh").chmod(0o755)
        names = (archive_name, "install.sh")
        (temporary / "SHA256SUMS").write_text(
            "".join(f"{sha256(temporary / name)}  {name}\n" for name in names), encoding="utf-8",
        )
        for name in (*names, "SHA256SUMS"):
            os.replace(temporary / name, output / name)
    print(f"Created {output / archive_name}, install.sh, and SHA256SUMS")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as error:
        print(f"Packaging failed: {error}", file=sys.stderr)
        sys.exit(1)
