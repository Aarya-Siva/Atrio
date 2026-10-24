#!/bin/bash
set -euo pipefail
verification_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$verification_root"
xcrun swiftc -swift-version 6 -parse-as-library \
  -module-cache-path /tmp/AtrioStateModuleCache \
  Atrio.swiftpm/Atrio/Services/CameraPermissionManager.swift \
  Atrio.swiftpm/Atrio/Services/CameraHardwareService.swift \
  Atrio.swiftpm/Atrio/ViewModels/PreparationViewModel.swift \
  Verification/Phase2StateChecks.swift \
  -o /tmp/AtrioPhase2StateChecks
/tmp/AtrioPhase2StateChecks
