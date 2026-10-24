#!/usr/bin/env python3
"""Extract each original 10-second source segment using production Swift code."""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import csv
import importlib.util
import json
from pathlib import Path
import subprocess

spec = importlib.util.spec_from_file_location('liu', Path(__file__).resolve().parents[1] / 'Dataset/import_liu.py')
liu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(liu)
NAMES = ['mean_interval_ms', 'sdnn_ms', 'rmssd_ms', 'pnn50', 'interval_cv']


def extract(root, executable, output):
    splits = {name: liu.subject_names(root / file) for name, file in [('development', 'validsubjects.txt'), ('test', 'testsubjects.txt')]}
    if set(splits['development']) & set(splits['test']):
        raise ValueError('Participant split overlap')
    tasks = [(split, name) for split, names in splits.items() for name in sorted(names)]
    def one(task):
        split, name = task
        waves, labels = liu.read_participant(root / 'valid_testDataset' / name)
        text = ''.join(json.dumps({'signal': wave.tolist(), 'sampleRate': 100}, separators=(',', ':')) + '\n' for wave in waves)
        process = subprocess.run([str(executable)], input=text, capture_output=True, text=True, check=True)
        lines = process.stdout.splitlines()
        if len(lines) != len(labels):
            raise ValueError(f'Feature extractor output length mismatch: {name}')
        rows = []
        for index, (line, label) in enumerate(zip(lines, labels)):
            features = json.loads(line)
            row = {'participant_id': Path(name).stem, 'source_split': split, 'segment': index,
                   'original_label': int(label), 'afib_label': int(label == 5), 'usable': int(features is not None)}
            row.update({key: features[key] if features else '' for key in NAMES})
            rows.append(row)
        return rows
    output.parent.mkdir(parents=True, exist_ok=True)
    counts = Counter()
    with output.open('w', newline='') as stream, ThreadPoolExecutor(max_workers=4) as pool:
        writer = csv.DictWriter(stream, fieldnames=['participant_id', 'source_split', 'segment', 'original_label', 'afib_label', 'usable'] + NAMES)
        writer.writeheader()
        for index, rows in enumerate(pool.map(one, tasks), 1):
            writer.writerows(rows)
            for row in rows:
                counts[(row['source_split'], row['usable'])] += 1
            print(f'Features: {index}/{len(tasks)} participants', flush=True)
    print(dict(counts), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repository', type=Path)
    parser.add_argument('executable', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    extract(args.repository, args.executable, args.output)
