#!/usr/bin/env python3
"""Compare matched, locally exported real-camera recordings. No network or ML."""
import argparse
import csv
import json
import math
from pathlib import Path


def compare(log_path):
    groups = {}
    seen = set()
    with log_path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        if not {"participant_id", "pair_id", "metadata_path"}.issubset(reader.fieldnames or []):
            raise ValueError("Study log needs participant_id,pair_id,metadata_path columns")
        for row in reader:
            key = (row["participant_id"].strip(), row["pair_id"].strip())
            if not all(key):
                raise ValueError("Participant and pair IDs must not be empty")
            path = Path(row["metadata_path"])
            if not path.is_absolute():
                path = log_path.parent / path
            data = json.loads(path.read_text(encoding="utf-8"))
            if data.get("source") != "camera":
                raise ValueError(f"{path}: only camera recordings are accepted")
            recording_id = data["recordingID"]
            if recording_id in seen:
                raise ValueError("A recording cannot be reused in another pair")
            seen.add(recording_id)
            aid = data["camera"].get("positioningAid")
            if aid not in ("unaided", "prototype"):
                raise ValueError(f"{path}: accessory condition is missing")
            pair = groups.setdefault(key, {})
            if aid in pair:
                raise ValueError(f"{key}: duplicate condition {aid}")
            pair[aid] = data

    result = []
    for key, pair in groups.items():
        if set(pair) != {"unaided", "prototype"}:
            raise ValueError(f"{key}: each pair needs both accessory conditions")
        a, b = pair["unaided"], pair["prototype"]
        for field in ("deviceModel", "cameraID", "width", "height", "nominalFrameRate", "roiFraction", "samplingStride", "torchLevel", "detectorProfile"):
            if a["camera"].get(field) != b["camera"].get(field):
                raise ValueError(f"{key}: unmatched camera setting {field}")
        if a["mode"] != b["mode"] or a["duration"] != b["duration"]:
            raise ValueError(f"{key}: recording modes or durations differ")
        if a["analysis"]["algorithmVersion"] != b["analysis"]["algorithmVersion"]:
            raise ValueError(f"{key}: processing versions differ")
        out = {"participant_id": key[0], "pair_id": key[1]}
        for label, data in (("unaided", a), ("prototype", b)):
            analysis = data["analysis"]
            quality = data["captureQuality"]
            out.update({f"{label}_recording_id": data["recordingID"],
                        f"{label}_quality": analysis["quality"],
                        f"{label}_coverage": analysis["coverage"],
                        f"{label}_dropped_frames": quality["droppedFrames"],
                        f"{label}_maximum_gap_s": quality["maximumFrameGap"],
                        f"{label}_estimated_bpm": analysis.get("estimatedHeartRate", "")})
        difference = b["analysis"]["coverage"] - a["analysis"]["coverage"]
        if not math.isfinite(difference):
            raise ValueError(f"{key}: non-finite coverage")
        out["coverage_difference_prototype_minus_unaided"] = difference
        result.append(out)
    if not result:
        raise ValueError("No matched pairs found")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("study_csv", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        rows = compare(args.study_csv)
        with args.output.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        print(f"Compared {len(rows)} matched pairs. Exploratory metrics only; no clinical conclusions.")
    except (ValueError, KeyError, OSError, TypeError) as error:
        parser.exit(1, f"Comparison failed: {error}\n")
