#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$task_root"
dataset_root="${1:?Provide the local downloaded Liu dataset directory}"
research_python="${2:?Provide the Python executable from the research virtual environment}"
build_directory="$(mktemp -d /tmp/AtrioModelTools.XXXXXX)"
source_root="Atrio.swiftpm/Atrio"

xcrun swiftc -O -swift-version 6 \
  "$source_root/Models/PPGSample.swift" "$source_root/Models/PPGRecording.swift" \
  "$source_root/Models/PulseAnalysis.swift" "$source_root/Services/FingerDetectionService.swift" \
  "$source_root/Services/PPGSignalExtractor.swift" "$source_root/Services/PulseAnalyzer.swift" \
  Research/Model/FeatureCLI/main.swift -o "$build_directory/features"
"$research_python" Research/Model/extract_features.py "$dataset_root" "$build_directory/features" \
  --output Research/Model/artifacts/features.csv
"$research_python" Research/Model/train_model.py Research/Model/artifacts/features.csv \
  --output Research/Model/artifacts
xcrun swiftc -O -swift-version 6 Research/Model/ParityCLI/main.swift -o "$build_directory/parity"
"$research_python" Research/Model/verify_install.py "$build_directory/parity"
