# SPDX-License-Identifier: Apache-2.0
"""Regression checks for detecting an incomplete/modified Swift delivery."""
import contextlib
import io
from pathlib import Path
import tempfile
import unittest

from check_ipad_chat_044_delivery import EXPECTED, check, main

ROOT = Path(__file__).resolve().parents[1]
RECOVERY_SNAPSHOT = ROOT / 'dist' / 'ipad-chat-044-recovery-delivered'


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for name in EXPECTED:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            reference = RECOVERY_SNAPSHOT if RECOVERY_SNAPSHOT.is_dir() else ROOT
            target.write_bytes((reference / name).read_bytes())

    def test_complete_delivery(self):
        self.assertEqual([status for _, status, _ in check(self.root)], ['OK'] * 8)

    def test_missing_file(self):
        name = 'apple/App/Sources/AssistanceView.swift'
        (self.root / name).unlink()
        self.assertEqual([(p, s) for p, s, _ in check(self.root) if s != 'OK'], [(name, 'MISSING')])

    def test_local_correction_reported_and_preserved(self):
        name = 'apple/App/Sources/AssistanceView.swift'
        target = self.root / name
        changed = target.read_bytes() + b'\n// Local correction fixture\n'
        target.write_bytes(changed)
        self.assertEqual([(p, s) for p, s, _ in check(self.root) if s != 'OK'], [(name, 'DIFFERENT')])
        self.assertEqual(target.read_bytes(), changed)

    def test_stale_version_reported(self):
        name = 'apple/Sources/MeshCentralAgent/ConnectionDiagnostics.swift'
        target = self.root / name
        changed = target.read_bytes().replace(b'0.4.4', b'0.4.3')
        self.assertNotEqual(target.read_bytes(), changed)
        target.write_bytes(changed)
        self.assertIn((name, 'DIFFERENT'), [(p, s) for p, s, _ in check(self.root)])

    def test_wrong_root_reports_all_eight(self):
        self.assertEqual([status for _, status, _ in check(self.root / 'wrong')], ['MISSING'] * 8)

    def test_cli_exit_status(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(main(['--root', str(self.root)]), 0)
            self.assertEqual(main(['--root', str(self.root / 'wrong')]), 1)
        self.assertIn(str(self.root.resolve()), output.getvalue())


if __name__ == '__main__':
    unittest.main()
