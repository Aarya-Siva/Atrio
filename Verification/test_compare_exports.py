import csv
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("compare_exports", Path(__file__).resolve().parents[1] / "Research/compare_exports.py")
comparison = importlib.util.module_from_spec(spec)
spec.loader.exec_module(comparison)


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.data = []
        for index, aid in enumerate(("unaided", "prototype")):
            data = {"recordingID": str(index), "source": "camera", "mode": "resting", "duration": 30,
                    "camera": {"positioningAid": aid, "deviceModel": "Test", "cameraID": "rear", "torchLevel": 0.25},
                    "captureQuality": {"droppedFrames": 0, "maximumFrameGap": 0.034},
                    "analysis": {"algorithmVersion": "pulse-v1", "quality": "usable", "coverage": 0.8 + index * 0.1}}
            self.data.append(data)

    def write(self):
        for index, data in enumerate(self.data):
            (self.root / f"{index}.json").write_text(json.dumps(data))
        path = self.root / "study.csv"
        with path.open("w", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(["participant_id", "pair_id", "metadata_path"])
            for index in range(2):
                writer.writerow(["P01", "01", f"{index}.json"])
        return path

    def test_computes_paired_coverage_without_inventing_missing_rate(self):
        rows = comparison.compare(self.write())
        self.assertEqual(len(rows), 1)
        self.assertAlmostEqual(rows[0]["coverage_difference_prototype_minus_unaided"], 0.1)
        self.assertEqual(rows[0]["unaided_estimated_bpm"], "")

    def test_rejects_synthetic_recording(self):
        self.data[0]["source"] = "syntheticUITest"
        with self.assertRaisesRegex(ValueError, "only camera"):
            comparison.compare(self.write())

    def test_rejects_different_camera_settings(self):
        self.data[1]["camera"]["torchLevel"] = 0.5
        with self.assertRaisesRegex(ValueError, "unmatched camera"):
            comparison.compare(self.write())

    def test_rejects_missing_condition(self):
        self.data[1]["camera"].pop("positioningAid")
        with self.assertRaisesRegex(ValueError, "condition is missing"):
            comparison.compare(self.write())


if __name__ == "__main__":
    unittest.main()
