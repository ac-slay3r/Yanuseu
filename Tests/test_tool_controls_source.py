"""Supplemental source guard; native compilation is checked in iOS CI."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ToolControlsSourceTests(unittest.TestCase):
    def test_controls_use_registry_members(self):
        registry = (ROOT / "Sources/Yanuseu/Runtime/ToolPolicy.swift").read_text()
        view = (ROOT / "Sources/Yanuseu/ToolControlsView.swift").read_text()
        self.assertIn("static let descriptions:", registry)
        self.assertIn("let summary: String", registry)
        self.assertIn("ToolRegistry.descriptions", view)
        self.assertIn("tool.summary", view)


if __name__ == "__main__":
    unittest.main()
