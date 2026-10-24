import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np
from scipy.io import savemat

spec = importlib.util.spec_from_file_location("liu_import", Path(__file__).with_name("import_liu.py"))
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repository = self.root / "repo"
        (self.repository / "valid_testDataset").mkdir(parents=True)
        (self.repository / "validsubjects.txt").write_text("'MPA_1.mat'\n")
        (self.repository / "testsubjects.txt").write_text("'MPA_2.mat'\n")
        self.waves = np.tile(np.linspace(0, 1, 1000), (2, 1))
        for name in ("MPA_1.mat", "MPA_2.mat"):
            savemat(self.repository / "valid_testDataset" / name,
                    {"ppgseg": self.waves, "labels": np.array([[0], [5]], dtype=np.uint8)})

    def test_preserves_participants_labels_and_waveforms(self):
        report = adapter.audit(self.repository, self.root / "out", True)
        self.assertEqual(report["split_summary"]["test"]["segments"], 2)
        self.assertFalse(report["training_data_present"])
        data = np.load(self.root / "out/validation/MPA_1.npz", allow_pickle=False)
        np.testing.assert_array_equal(data["ppgseg"], self.waves)
        np.testing.assert_array_equal(data["labels"], [0, 5])
        self.assertEqual(data["sample_rate_hz"], 100)
        self.assertTrue((self.root / "out/inventory.json").exists())

    def test_rejects_participant_overlap(self):
        (self.repository / "testsubjects.txt").write_text("'MPA_1.mat'\n")
        with self.assertRaisesRegex(ValueError, "overlap"):
            adapter.audit(self.repository, self.root / "out")

    def test_rejects_unknown_labels(self):
        savemat(self.repository / "valid_testDataset/MPA_1.mat", {"ppgseg": self.waves, "labels": [[0], [6]]})
        with self.assertRaisesRegex(ValueError, "integers from 0 through 5"):
            adapter.audit(self.repository, self.root / "out")

    def test_rejects_nonfinite_waveforms(self):
        self.waves[0, 2] = np.nan
        savemat(self.repository / "valid_testDataset/MPA_1.mat", {"ppgseg": self.waves, "labels": [[0], [5]]})
        with self.assertRaisesRegex(ValueError, "non-finite"):
            adapter.audit(self.repository, self.root / "out")

    def test_rejects_mismatched_window_length(self):
        savemat(self.repository / "valid_testDataset/MPA_1.mat", {"ppgseg": self.waves[:, :500], "labels": [[0], [5]]})
        with self.assertRaisesRegex(ValueError, "1000-sample"):
            adapter.audit(self.repository, self.root / "out")


if __name__ == "__main__":
    unittest.main()
