#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Explicit launch-argument-only harness. Never compiled for a physical device or Release.
/// Synthetic data uses a separate repository and is labeled on screen and in every report.
struct ResearchUITestHarness: View {
    @State private var history = HistoryModel(repository: MeasurementRepository(
        directory: URL.applicationSupportDirectory.appendingPathComponent("UITestMeasurements")))
    @State private var measurement: Measurement?
    @State private var errorMessage: String?

    var body: some View {
        TabView {
            NavigationStack {
                if let measurement {
                    MeasurementDetailView(measurement: measurement, history: history)
                } else if let errorMessage {
                    Text(errorMessage)
                } else { ProgressView("Preparing synthetic UI fixture…") }
            }
            .tabItem { Label("Test Result", systemImage: "waveform.path") }
            NavigationStack {
                HistoryView(history: history, onStartMeasurement: {})
            }
            .tabItem { Label("Test History", systemImage: "clock") }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Text("UI TEST · SYNTHETIC DATA · NOT A MEASUREMENT")
                .font(.caption.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(10).frame(maxWidth: .infinity)
                .foregroundStyle(AppColors.heading).background(AppColors.softBlue)
        }
        .task {
            await history.refresh()
            guard measurement == nil else { return }
            do {
                measurement = try await MeasurementProcessor().process(Self.recording())
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private static func recording() -> PPGRecording {
        let insufficient = ProcessInfo.processInfo.arguments.contains("--ui-test-insufficient")
        let samples = (0..<900).map { i in
            let time = Double(i) / 30
            return PPGSample(timestamp: 100 + time,
                             red: 180 - (insufficient ? 0 : 2 * sin(2 * .pi * 1.2 * time)),
                             green: 60, blue: 40, condition: .suitable)
        }
        return PPGRecording(id: UUID(), startDate: Date(), duration: 30, sampleDuration: 899 / 30,
            samples: samples, averageFrameRate: 30, frameCount: samples.count,
            camera: PPGCameraMetadata(deviceModel: "Synthetic UI fixture", osVersion: "Test", cameraName: "No camera",
                cameraID: "test", width: 640, height: 480, nominalFrameRate: 30, pixelFormat: "32BGRA",
                roiFraction: 0.5, samplingStride: 4, torchLevel: 0, exposureLocked: true, whiteBalanceLocked: true),
            quality: PPGQualityMetadata(suitableFrames: samples.count, conditionCounts: [:], droppedFrames: 0,
                extractionFailures: 0, rejectedTimestamps: 0, maximumFrameGap: 1 / 30,
                potentiallyInvalid: false, notes: ["Synthetic UI fixture — not a measurement"]),
            source: .syntheticUITest)
    }
}
#endif
