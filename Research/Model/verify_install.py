#!/usr/bin/env python3
"""Verify native Core ML predictions before enabling and installing model resources."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('parity_executable', type=Path)
parser.add_argument('--artifacts', type=Path, default=Path(__file__).with_name('artifacts'))
args = parser.parse_args()
artifacts = args.artifacts.resolve()
model = artifacts / 'AFibResearch.mlmodel'
manifest_path = artifacts / 'AFibResearch.json'
manifest = json.loads(manifest_path.read_text())
if hashlib.sha256(model.read_bytes()).hexdigest() != manifest['modelSHA256']:
    raise ValueError('Trained model checksum does not match its manifest')
result = subprocess.run([str(args.parity_executable.resolve()), str(model), str(artifacts/'parity_vectors.jsonl')],
                        text=True, capture_output=True, check=True)
match = re.search(r'parity passed: (\d+).*max absolute error ([0-9.eE+-]+)', result.stdout)
if not match or int(match[1]) < 1000 or float(match[2]) >= 1e-5:
    raise ValueError('Insufficient or failed Core ML parity verification')
report = {'vectors': int(match[1]), 'maximumAbsoluteError': float(match[2]), 'tolerance': 1e-5,
          'includesRealWindowsAndFloat32ThresholdBoundaries': True}
(artifacts/'coreml_parity.json').write_text(json.dumps(report, indent=2)+'\n')
manifest['coreMLParityVerified'] = True
manifest_path.write_text(json.dumps(manifest, indent=2)+'\n')
root = Path(__file__).resolve().parents[2]
destination = root / 'Atrio.swiftpm/Atrio/Resources'
shutil.copy2(model, destination/'AFibResearch.modeldata')
for name in ['AFibResearch.json', 'AFibResearch.explainer.json']:
    shutil.copy2(artifacts/name, destination/name)
print(result.stdout.strip())
print('Installed verified local research model resources. iPhone validation is still required.')
