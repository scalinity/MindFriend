"""Check that restoration hashes are attributed to the commit actually read."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class RestorationInventoryTests(unittest.TestCase):
    def setUp(self):
        artifacts = ROOT / "artifacts"
        artifacts.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="inventory-check-", dir=artifacts)
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.evidence = self.folder / "evidence"
        self.evidence.mkdir()
        self.recovery = self.folder / "recovery"
        self.baseline = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        self.source = subprocess.check_output(["git", "show", self.baseline + ":supabase/functions/chat/index.ts"], cwd=ROOT)
        snapshot = self.recovery / "deployed/supabase/functions/chat/index.ts"
        snapshot.parent.mkdir(parents=True)
        snapshot.write_bytes(self.source)
        fixtures = {
            "inventory.json": [],
            "deployed_functions.json": {"functions": [{"slug": slug, "version": 1, "status": "ACTIVE"} for slug in ["chat", "absent-test-fixture"]]},
            "workloads.json": [{"metadata": {"jobs": [], "buckets": [], "runs": [], "published_tables": []}}],
            "security.json": [],
            "advisor_security-parsed.json": {"lints": []},
            "advisor_performance-parsed.json": {"lints": []},
        }
        for name, value in fixtures.items():
            (self.evidence / name).write_text(json.dumps(value))

    def run_inventory(self, *args):
        return subprocess.run(["python3", str(ROOT / "scripts/restoration_inventory.py"),
                               "--evidence", str(self.evidence), "--recovery", str(self.recovery), *args],
                              capture_output=True, text=True)

    def test_explicit_commit_and_missing_source(self):
        result = self.run_inventory("--baseline", self.baseline)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads((self.evidence / "backend-inventory.json").read_text())
        self.assertEqual(output["baseline_commit"], self.baseline)
        present, missing = output["edge_functions"]
        self.assertEqual(present["baseline_sha256"], hashlib.sha256(self.source).hexdigest())
        self.assertTrue(present["baseline_exact_match"])
        self.assertFalse(missing["baseline_source_available"])
        self.assertIsNone(missing["baseline_sha256"])
        self.assertIsNone(missing["baseline_exact_match"])

    def test_default_commit_matches_its_hashes(self):
        result = self.run_inventory()
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads((self.evidence / "backend-inventory.json").read_text())
        source = subprocess.check_output(["git", "show", output["baseline_commit"] + ":supabase/functions/chat/index.ts"], cwd=ROOT)
        self.assertEqual(output["edge_functions"][0]["baseline_sha256"], hashlib.sha256(source).hexdigest())

    def test_invalid_baseline_fails_without_inventory(self):
        result = self.run_inventory("--baseline", "nonexistent-review-fixture-ref")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.evidence / "backend-inventory.json").exists())

if __name__ == "__main__":
    unittest.main()
