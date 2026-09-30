import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("packaged_provenance", ROOT / "scripts/packaged-provenance.py")
provenance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provenance)


class PackagedProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="fuji-provenance-test-")
        self.addCleanup(self.directory.cleanup)
        self.resources = Path(self.directory.name)
        self.manifest = json.loads((ROOT / "macos/Resources" / provenance.MANIFEST).read_text())
        for artifact, name in provenance.ARTIFACTS.items():
            data = f"original {artifact}".encode()
            (self.resources / name).write_bytes(data)
            self.manifest[f"{artifact}_sha256"] = hashlib.sha256(data).hexdigest()
        self.write_manifest()

    def write_manifest(self):
        (self.resources / provenance.MANIFEST).write_text(json.dumps(self.manifest))

    def test_signed_hashes_replace_artifact_hashes_and_preserve_build_inputs(self):
        for name in provenance.ARTIFACTS.values():
            (self.resources / name).write_bytes(b"signed artifact")
        updated = provenance.refresh(self.resources)
        self.assertEqual(updated["schema_version"], 2)
        self.assertEqual(updated["helper_source_sha256"], self.manifest["helper_source_sha256"])
        for artifact in provenance.ARTIFACTS:
            self.assertEqual(updated[f"build_{artifact}_sha256"], self.manifest[f"{artifact}_sha256"])
            self.assertNotEqual(updated[f"{artifact}_sha256"], self.manifest[f"{artifact}_sha256"])
        self.assertEqual(provenance.verify(self.resources), updated)
        self.assertEqual(provenance.refresh(self.resources), updated)

    def test_modification_after_refresh_fails_verification(self):
        provenance.refresh(self.resources)
        with (self.resources / provenance.ARTIFACTS["helper"]).open("ab") as artifact:
            artifact.write(b"changed after signing")
        with self.assertRaisesRegex(ValueError, "helper differs"):
            provenance.verify(self.resources)

    def test_missing_source_hash_does_not_rewrite_manifest(self):
        del self.manifest["helper_source_sha256"]
        self.write_manifest()
        original = (self.resources / provenance.MANIFEST).read_bytes()
        with self.assertRaisesRegex(ValueError, "helper_source_sha256"):
            provenance.refresh(self.resources)
        self.assertEqual((self.resources / provenance.MANIFEST).read_bytes(), original)

    def test_unexpected_macho_copy_in_resource_bundle_is_rejected(self):
        nested = self.resources / "SwiftPM.bundle" / "x100vi_helper"
        nested.parent.mkdir()
        nested.write_bytes(bytes.fromhex("cafebabe") + b"extra executable")
        with self.assertRaisesRegex(ValueError, "unexpected nested executable code"):
            provenance.verify(self.resources)

    @unittest.skipUnless(sys.platform == "darwin" and shutil.which("codesign"), "requires macOS codesign")
    def test_hardened_runtime_resigning_records_valid_final_artifacts(self):
        self.manifest = json.loads((ROOT / "macos/Resources" / provenance.MANIFEST).read_text())
        self.write_manifest()
        for name in provenance.ARTIFACTS.values():
            destination = self.resources / name
            shutil.copy2(ROOT / "macos/Resources" / name, destination)
            subprocess.run(
                ["codesign", "--force", "--options", "runtime", "--identifier",
                 f"com.ant.fuji-recipes.provenance-test.{uuid.uuid4()}", "--sign", "-", str(destination)],
                check=True, capture_output=True, text=True,
            )
            subprocess.run(["codesign", "--verify", "--strict", str(destination)],
                           check=True, capture_output=True, text=True)
        updated = provenance.refresh(self.resources)
        for artifact in provenance.ARTIFACTS:
            self.assertNotEqual(updated[f"{artifact}_sha256"], updated[f"build_{artifact}_sha256"])
        provenance.verify(self.resources)


if __name__ == "__main__":
    unittest.main()
