"""Source-level regression for the saved setup summary (not a SwiftUI interaction test)."""
from pathlib import Path
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "Sources/Yanuseu/YanuseuApp.swift"


class SavedProviderSummaryTests(unittest.TestCase):
    def test_saved_model_reads_persisted_profile_not_editable_field(self):
        source = SOURCE.read_text()
        saved_section = source.split('if profiles.selected.isConfigured {\n                    Section {', 1)[1].split('\n                }\n', 1)[0]
        self.assertIn('LabeledContent("Saved model", value: profiles.selected.model)', saved_section)
        self.assertNotIn('LabeledContent("Model", value: model)', saved_section)


if __name__ == "__main__":
    unittest.main()
