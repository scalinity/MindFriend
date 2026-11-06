"""Offline command-contract regression checks; never contact a Supabase project."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MigrationCheckTests(unittest.TestCase):
    def setUp(self):
        artifacts = ROOT / "artifacts"
        artifacts.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="migration-check-", dir=artifacts)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        (self.root / "supabase/migrations").mkdir(parents=True)
        (self.root / "bin").mkdir()
        shutil.copy(ROOT / "scripts/check-migrations.sh", self.root / "scripts/check-migrations.sh")
        (self.root / "supabase/migrations/20260101000000_fixture.sql").write_text("select 1;\n")
        shim = self.root / "bin/supabase"
        shim.write_text('#!/bin/sh\nprintf "%s" "$FAKE_OUTPUT"\nexit "$FAKE_STATUS"\n')
        shim.chmod(0o755)
        self.addCleanup(self.temp.cleanup)

    def run_check(self, output, status=0, requested=True):
        env = dict(os.environ, PATH=str(self.root / "bin") + ":" + os.environ["PATH"],
                   FAKE_OUTPUT=output, FAKE_STATUS=str(status), CHECK_REMOTE_MIGRATIONS="1" if requested else "")
        return subprocess.run(["bash", str(self.root / "scripts/check-migrations.sh")],
                              env=env, text=True, capture_output=True)

    def test_array_and_agent_envelope_match(self):
        rows = [{"name": "fixture", "version": "20260101000000"}]
        for value in [rows, {"boundary": "synthetic", "rows": rows}]:
            with self.subTest(value=value):
                result = self.run_check(json.dumps(value))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("1 shared versions", result.stdout)

    def test_empty_real_ledger_is_explicit(self):
        result = self.run_check("[]")
        self.assertEqual(result.returncode, 0)
        self.assertIn("0 remote rows checked", result.stdout)

    def test_command_error_cannot_pass(self):
        result = self.run_check("[]", status=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unverified", result.stderr)

    def test_invalid_or_incomplete_json_cannot_pass(self):
        for output in ["", "not json", "{}", '[{"version":"20260101000000"}]']:
            with self.subTest(output=output):
                self.assertNotEqual(self.run_check(output).returncode, 0)

    def test_name_drift_fails(self):
        result = self.run_check('[{"version":"20260101000000","name":"different"}]')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Drift", result.stdout)

    def test_unrequested_remote_check_skips(self):
        result = self.run_check("", status=1, requested=False)
        self.assertEqual(result.returncode, 0)
        self.assertIn("skipped", result.stdout)

if __name__ == "__main__":
    unittest.main()
