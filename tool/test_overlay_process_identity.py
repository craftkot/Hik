"""Source-level regression checks for Windows HUD process identity guards.

Run with: python3 -m unittest tool/test_overlay_process_identity.py
"""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parent / "windows-overlay" / "Program.cs").read_text(encoding="utf-8")


class OverlayIdentityTest(unittest.TestCase):
    def test_refresh_matches_process_start_time(self):
        self.assertIn("ProcessStartTicks(x.GetProperty(\"pid\").GetInt32())", SOURCE)
        self.assertIn("oldGame.StartTicks == start", SOURCE)
        self.assertIn("candidate.StartTicks is long start", SOURCE)

    def test_write_and_undo_fail_closed(self):
        self.assertGreaterEqual(SOURCE.count("if (!IsSameProcess(pid))"), 2)
        self.assertIn("if (!IsSameProcess(restore.Pid))", SOURCE)
        self.assertIn("game.StartTicks is long start", SOURCE)
        self.assertIn("ProcessStartTicks(pid) == start", SOURCE)


if __name__ == "__main__":
    unittest.main()
