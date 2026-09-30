#!/usr/bin/env python3
"""Record and verify signed helper/runtime hashes before sealing an app bundle."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import tempfile

MANIFEST = "x100vi_helper.provenance.json"
ARTIFACTS = {"helper": "x100vi_helper", "runtime": "libusb-1.0.0.dylib"}
MACHO_MAGICS = {
    bytes.fromhex(value)
    for value in ("feedface", "cefaedfe", "feedfacf", "cffaedfe",
                  "cafebabe", "bebafeca", "cafebabf", "bfbafeca")
}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_manifest(resources):
    manifest = json.loads((resources / MANIFEST).read_text())
    if not isinstance(manifest, dict):
        raise ValueError("packaged provenance must be a JSON object")
    if type(manifest.get("schema_version")) is not int or manifest["schema_version"] not in (1, 2):
        raise ValueError("unsupported packaged provenance schema")
    if manifest.get("runtime") != ARTIFACTS["runtime"]:
        raise ValueError("unexpected runtime in packaged provenance")
    for key in ("helper_source_sha256", "helper_sha256", "runtime_sha256"):
        if not isinstance(manifest.get(key), str) or not re.fullmatch(r"[0-9a-f]{64}", manifest[key]):
            raise ValueError(f"missing or invalid {key} in packaged provenance")
    if manifest["schema_version"] == 2:
        for key in ("build_helper_sha256", "build_runtime_sha256"):
            if not isinstance(manifest.get(key), str) or not re.fullmatch(r"[0-9a-f]{64}", manifest[key]):
                raise ValueError(f"missing or invalid {key} in packaged provenance")
    return manifest


def refresh(resources):
    """Preserve verified input hashes, then record the signed artifact hashes."""
    resources = Path(resources)
    manifest = load_manifest(resources)
    for artifact, name in ARTIFACTS.items():
        key = f"{artifact}_sha256"
        manifest.setdefault(f"build_{key}", manifest[key])
        manifest[key] = sha256(resources / name)
    manifest["schema_version"] = 2

    destination = resources / MANIFEST
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=resources, prefix=".provenance-", delete=False) as output:
            temporary = Path(output.name)
            json.dump(manifest, output, indent=2)
            output.write("\n")
        temporary.chmod(stat.S_IMODE(destination.stat().st_mode))
        os.replace(temporary, destination)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return manifest


def verify(resources):
    resources = Path(resources)
    manifest = load_manifest(resources)
    for artifact, name in ARTIFACTS.items():
        if sha256(resources / name) != manifest[f"{artifact}_sha256"]:
            raise ValueError(f"bundled {artifact} differs from packaged provenance")

    # Helper/runtime live only at the resource root. Extra Mach-O copies can
    # retain obsolete hashes/signatures and escape the explicit nested gates.
    expected = {resources / name for name in ARTIFACTS.values()}
    for resource in resources.rglob("*"):
        if not resource.is_file() or resource in expected:
            continue
        with resource.open("rb") as source:
            if source.read(4) in MACHO_MAGICS:
                raise ValueError(f"unexpected nested executable code: {resource.relative_to(resources)}")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("refresh", "verify"))
    parser.add_argument("--resources", required=True, type=Path)
    args = parser.parse_args()
    try:
        {"refresh": refresh, "verify": verify}[args.action](args.resources)
    except (OSError, ValueError, TypeError) as error:
        parser.exit(1, f"error: {error}\n")
    print(f"packaged provenance {args.action} passed")


if __name__ == "__main__":
    main()
