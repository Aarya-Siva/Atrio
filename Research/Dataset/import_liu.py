#!/usr/bin/env python3
"""Audit Liu validation/test MATLAB data; optionally preserve each participant as NPZ.

Requires numpy and scipy. Never trains, changes splits, or creates app measurements.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

import numpy as np
from scipy.io import loadmat

LABELS = {0: "sinus rhythm", 1: "premature ventricular contraction",
          2: "premature atrial contraction", 3: "ventricular tachycardia",
          4: "supraventricular tachycardia", 5: "atrial fibrillation"}
COMMIT = "ab635cb4bdb604c8e99e8481f63b4d093f56f5a8"


def subject_names(path):
    names = [line.strip().strip("'\"") for line in path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
    if not names or len(set(names)) != len(names):
        raise ValueError(f"{path}: empty or duplicate subject list")
    if any(re.fullmatch(r"MPA_[0-9]+\.mat", name) is None for name in names):
        raise ValueError(f"{path}: unexpected participant filename")
    return names


def read_participant(path):
    data = loadmat(path)
    if not {"ppgseg", "labels"}.issubset(data):
        raise ValueError(f"{path}: missing ppgseg or labels")
    waves = np.asarray(data["ppgseg"])
    labels = np.asarray(data["labels"]).reshape(-1)
    if waves.ndim != 2 or waves.shape[1] != 1000 or waves.shape[0] != labels.size or labels.size == 0:
        raise ValueError(f"{path}: expected one label per 1000-sample segment")
    if not np.issubdtype(waves.dtype, np.number) or not np.isrealobj(waves) or not np.isfinite(waves).all():
        raise ValueError(f"{path}: non-finite or unsupported waveform data")
    if not np.isrealobj(labels) or not np.isfinite(labels).all() or not np.isin(labels, list(LABELS)).all():
        raise ValueError(f"{path}: labels must be integers from 0 through 5")
    return waves, labels.astype(np.uint8)


def audit(repository, output, preserve_npz=False):
    splits = {"validation": subject_names(repository / "validsubjects.txt"),
              "test": subject_names(repository / "testsubjects.txt")}
    if set(splits["validation"]) & set(splits["test"]):
        raise ValueError("Validation/test participant identifiers overlap")
    # Complete the audit before writing artifacts, so missing/corrupt inputs fail explicitly.
    records, totals = [], {}
    for split, names in splits.items():
        counts = Counter()
        for name in names:
            path = repository / "valid_testDataset" / name
            waves, labels = read_participant(path)
            histogram = Counter(map(int, labels))
            counts.update(histogram)
            records.append({"participant_id": path.stem, "split": split,
                            "segments": int(labels.size), "label_counts": dict(histogram),
                            "mat_sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
        totals[split] = {"participants": len(names), "label_counts": dict(counts),
                         "segments": sum(counts.values())}
    output.mkdir(parents=True, exist_ok=True)
    if preserve_npz:
        for record in records:
            waves, labels = read_participant(repository / "valid_testDataset" / (record["participant_id"] + ".mat"))
            directory = output / record["split"]
            directory.mkdir(exist_ok=True)
            np.savez_compressed(directory / (record["participant_id"] + ".npz"),
                                ppgseg=waves, labels=labels, sample_rate_hz=np.array(100),
                                participant_id=np.array(record["participant_id"]))
    report = {"repository": "https://github.com/zdzdliu/PPGArrhythmiaDetection",
              "reference_commit": COMMIT, "sample_rate_hz": 100, "segment_seconds": 10,
              "label_definitions": LABELS, "split_summary": totals, "participants": records,
              "training_data_present": False, "trained_model_present": False,
              "notice": "Validation/test inventory only. No model trained or iPhone clinical validation established. Verify reuse terms with the dataset owner."}
    (output / "inventory.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repository", type=Path, help="Downloaded repository with original subject lists and valid_testDataset")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--preserve-npz", action="store_true", help="Copy original arrays into participant/split-specific NPZ files")
    args = parser.parse_args()
    try:
        report = audit(args.repository, args.output, args.preserve_npz)
        print(json.dumps(report["split_summary"], indent=2))
    except (OSError, ValueError, TypeError) as error:
        parser.exit(1, f"Import failed: {error}\n")
