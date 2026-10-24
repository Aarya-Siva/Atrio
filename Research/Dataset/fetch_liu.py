#!/usr/bin/env python3
"""Download pinned public research data; verify Git blob hashes. Never executes repository code."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import sys
from urllib.request import urlopen

COMMIT = "ab635cb4bdb604c8e99e8481f63b4d093f56f5a8"
REPO = "zdzdliu/PPGArrhythmiaDetection"


def fetch(root):
    with urlopen(f"https://api.github.com/repos/{REPO}/git/trees/{COMMIT}?recursive=1", timeout=60) as response:
        tree = json.load(response)
    items = [x for x in tree["tree"] if x["path"] in ("validsubjects.txt", "testsubjects.txt", "README.md", "readme.txt")
             or (x["path"].startswith("valid_testDataset/") and x["path"].endswith(".mat"))]

    def one(item):
        relative = Path(item["path"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("Unexpected repository path")
        path = root / relative
        def verified(data):
            return hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest() == item["sha"]
        if path.exists() and verified(path.read_bytes()):
            return
        with urlopen(f"https://raw.githubusercontent.com/{REPO}/{COMMIT}/{item['path']}", timeout=120) as response:
            data = response.read()
        if not verified(data):
            raise ValueError(f"Hash mismatch: {relative}")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    with ThreadPoolExecutor(max_workers=6) as pool:
        for index, _ in enumerate(pool.map(one, items), 1):
            if index % 10 == 0:
                print(f"Verified {index}/{len(items)} files", flush=True)
    (root / "source_commit.txt").write_text(COMMIT + "\n")
    print(f"Downloaded and verified {len(items)} files at {COMMIT}", flush=True)


if __name__ == "__main__":
    fetch(Path(sys.argv[1]))
