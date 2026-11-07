"""Offline tests for supervisor.scan_once (no Ollama needed). Run: python -m unittest -v"""
import json
import os
import tempfile
import unittest
from pathlib import Path

import supervisor


class ScanTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        root = Path(self._tmp.name)
        self.logs, self.reports = root / "logs", root / "reports"
        self.logs.mkdir()
        self.reports.mkdir()
        self.calls = []
        self.state = {}

    def tearDown(self):
        self._tmp.cleanup()

    def ask(self, text):
        self.calls.append(text)
        return "analysis of: " + text.strip()[:20]

    def write(self, rel, text, mtime):
        path = self.logs / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        os.utime(path, (mtime, mtime))
        return path

    def scan(self, **kw):
        return supervisor.scan_once(self.logs, self.reports, self.state, ask=self.ask, **kw)

    def test_unchanged_files_are_skipped(self):
        self.write("map.log", "line one", 1000)
        self.assertTrue(self.scan())
        self.assertEqual(len(self.calls), 1)
        self.assertFalse(self.scan())
        self.assertEqual(len(self.calls), 1)

    def test_changed_size_or_mtime_is_reanalyzed(self):
        path = self.write("map.log", "line one", 1000)
        self.scan()
        path.write_text("line one\nline two")
        os.utime(path, (1000, 1000))  # same mtime, different size
        self.scan()
        self.assertEqual(len(self.calls), 2)
        os.utime(path, (2000, 2000))  # same size, different mtime
        self.scan()
        self.assertEqual(len(self.calls), 3)

    def test_same_name_in_different_folders_do_not_collide(self):
        self.write("char/server.log", "char text", 1000)
        self.write("map/server.log", "map text", 1001)
        self.scan()
        a = json.loads((self.reports / "char" / "server.log.analysis.json").read_text())
        b = json.loads((self.reports / "map" / "server.log.analysis.json").read_text())
        self.assertEqual((a["source_file"], b["source_file"]), ("char/server.log", "map/server.log"))
        self.assertNotEqual(a["analysis"], b["analysis"])

    def test_top_level_report_name_is_unchanged(self):
        self.write("map.log", "x", 1000)
        self.scan()
        self.assertTrue((self.reports / "map.log.analysis.json").is_file())

    def test_only_newest_files_considered(self):
        for i in range(8):
            self.write(f"f{i}.log", f"text {i}", 1000 + i)
        self.scan(newest=5)
        self.assertEqual(len(self.calls), 5)
        self.assertFalse((self.reports / "f2.log.analysis.json").exists())
        self.assertTrue((self.reports / "f7.log.analysis.json").exists())

    def test_failed_analysis_is_retried(self):
        self.write("map.log", "x", 1000)
        def boom(_text):
            raise RuntimeError("ollama down")
        supervisor.scan_once(self.logs, self.reports, self.state, ask=boom)
        self.assertEqual(self.state, {})
        self.scan()
        self.assertEqual(len(self.calls), 1)

    def test_empty_file_recorded_without_report(self):
        self.write("empty.log", "  \n", 1000)
        self.scan()
        self.assertEqual(self.calls, [])
        self.assertIn("empty.log", self.state)
        self.assertFalse((self.reports / "empty.log.analysis.json").exists())

    def test_deleted_files_are_forgotten(self):
        path = self.write("map.log", "x", 1000)
        self.scan()
        path.unlink()
        self.assertTrue(self.scan())
        self.assertEqual(self.state, {})

    def test_state_round_trip_and_corrupt_state(self):
        self.write("map.log", "x", 1000)
        self.scan()
        state_file = self.reports / supervisor.STATE_FILE_NAME
        supervisor.write_atomic(state_file, json.dumps(self.state))
        self.assertEqual(supervisor.load_state(state_file), self.state)
        state_file.write_text("{not json")
        self.assertEqual(supervisor.load_state(state_file), {})
        self.assertEqual(supervisor.load_state(self.reports / "missing.json"), {})


if __name__ == "__main__":
    unittest.main()
