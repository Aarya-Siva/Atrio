// swift-tools-version: 6.0
import PackageDescription

// Host-side tests compile the same production signal/storage code, without a simulator.
let package = Package(
    name: "AtrioVerification",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "AtrioCore",
            path: "Atrio.swiftpm/Atrio",
            exclude: ["App", "Views", "Components", "Theme", "Resources", "ViewModels",
                      "Models/AppNavigation.swift", "Services/CameraHardwareService.swift",
                      "Services/CameraPermissionManager.swift", "Services/PPGCameraService.swift",
                      "Services/ResearchPDFRenderer.swift", "Services/OpticalPlotPoint.swift"],
            sources: ["Models/PPGRecording.swift", "Models/PPGSample.swift", "Models/RecordingState.swift",
                      "Models/PulseAnalysis.swift", "Services/FingerDetectionService.swift",
                      "Services/PPGSignalExtractor.swift", "Services/PPGRecordingAccumulator.swift",
                      "Services/PulseAnalyzer.swift", "Services/MeasurementRepository.swift",
                      "Services/ResearchExport.swift", "Services/RhythmModelService.swift"],
            swiftSettings: [.define("ATRIO_CORE_TESTS")]
        ),
        .testTarget(name: "AtrioCoreTests", dependencies: ["AtrioCore"], path: "Verification/CoreTests")
    ]
)
