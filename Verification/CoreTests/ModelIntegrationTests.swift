import CoreML
import Foundation
import Testing
@testable import AtrioCore

struct ModelIntegrationTests {
    @Test func sourceAndCameraNormalizationUseIdenticalFeatures() throws {
        let recording = Fixture.recording()
        let samples = Array(recording.samples.prefix(300))
        let times = samples.map { $0.timestamp - 100 }
        let source = samples.map { (180 - $0.red) / 10 + 0.5 }
        let sourceFeatures = try RhythmWindowExtractor.features(timestamps: times, intensities: source, positivePulses: true)
        let cameraFeatures = try RhythmWindowExtractor.features(timestamps: times, intensities: samples.map(\.red), positivePulses: false)
        let a = try #require(sourceFeatures)
        let b = try #require(cameraFeatures)
        for name in RhythmWindowExtractor.featureNames {
            #expect(abs(a.modelInputs[name]! - b.modelInputs[name]!) < 0.000001)
        }
        let windows = try RhythmWindowExtractor.cameraWindows(recording)
        #expect(windows.count == 3)
        #expect(recording.samples.first?.red == 180)
    }

    @Test func modelWindowsRejectFlatShortAndUncoveredSignals() throws {
        let times = (0..<300).map { Double($0) / 30 }
        #expect(try RhythmWindowExtractor.features(timestamps: times, intensities: Array(repeating: 0.5, count: 300), positivePulses: true) == nil)
        let recording = Fixture.recording(condition: { $0 < 15 ? .suitable : .uncovered })
        let windows = try RhythmWindowExtractor.cameraWindows(recording)
        #expect(windows.count == 1)
        let overall = try PulseAnalyzer().analyze(recording)
        #expect(overall.quality != .usable)
    }

    @Test func trainedForestParityAndExactShapleyAdditivity() throws {
        let directory = try modelArtifacts()
        let forest = try JSONDecoder().decode(ModelExplanationForest.self,
            from: Data(contentsOf: directory.appendingPathComponent("AFibResearch.explainer.json")))
        #expect(forest.isValid)
        struct Vector: Decodable { let features: [String: Double]; let expected: Double }
        let lines = try String(contentsOf: directory.appendingPathComponent("parity_vectors.jsonl"), encoding: .utf8).split(separator: "\n")
        for line in lines {
            let vector = try JSONDecoder().decode(Vector.self, from: Data(line.utf8))
            let inputs = forest.featureNames.map { Double(Float(vector.features[$0]!)) }
            let margin = forest.margin(inputs)
            #expect(abs(1 / (1 + exp(-margin)) - vector.expected) < 0.00001)
        }
        let vector = try JSONDecoder().decode(Vector.self, from: Data(lines[0].utf8))
        let values = forest.featureNames.map { Double(Float(vector.features[$0]!)) }
        let explanation = try forest.explain(values)
        #expect(abs(explanation.baseline + explanation.contributions.reduce(0, +) - forest.margin(values)) < 0.000001)
    }

    @Test func compiledModelRunsThroughProductionService() async throws {
        let artifacts = try modelArtifacts()
        let compiled = try await MLModel.compileModel(at: artifacts.appendingPathComponent("AFibResearch.mlmodel"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: compiled, to: directory.appendingPathComponent("AFibResearch.mlmodelc"))
        for name in ["AFibResearch.json", "AFibResearch.explainer.json"] {
            try FileManager.default.copyItem(at: artifacts.appendingPathComponent(name), to: directory.appendingPathComponent(name))
        }
        let recording = Fixture.recording()
        let analysis = try PulseAnalyzer().analyze(recording)
        let service = RhythmModelService(modelDirectory: directory)
        let output = await service.evaluate(analysis, recording: recording)
        #expect(output.classification != .unavailable)
        #expect(output.modelVersion == "liu-window-xgb-v1")
        #expect(output.evaluatedWindows == 3)
        let contributions = try #require(output.featureContributions)
        let baseline = try #require(output.explanationBaseline)
        let score = try #require(output.afibScore)
        #expect(abs(1 / (1 + exp(-(baseline + contributions.values.reduce(0, +)))) - score) < 0.00001)
        // Swift app package fallback compiles the bundled model on its service actor.
        try FileManager.default.removeItem(at: directory.appendingPathComponent("AFibResearch.mlmodelc"))
        try FileManager.default.copyItem(at: artifacts.appendingPathComponent("AFibResearch.mlmodel"),
            to: directory.appendingPathComponent("AFibResearch.modeldata"))
        let fallback = await RhythmModelService(modelDirectory: directory).evaluate(analysis, recording: recording)
        #expect(fallback.modelVersion == output.modelVersion)
        #expect(fallback.afibScore == output.afibScore)
        // Fail closed if a model manifest has not passed conversion parity checks.
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("AFibResearch.json"))) as? [String: Any])
        manifest["coreMLParityVerified"] = false
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("AFibResearch.json"))
        let incompatible = await RhythmModelService(modelDirectory: directory).evaluate(analysis, recording: recording)
        #expect(incompatible.classification == .unavailable)
        #expect(incompatible.afibScore == nil)
        let bad = Fixture.recording(amplitude: 0)
        #expect(await service.evaluate(try PulseAnalyzer().analyze(bad), recording: bad).classification == .inconclusive)
        let synthetic = PPGRecording(id: recording.id, startDate: recording.startDate, duration: recording.duration,
            sampleDuration: recording.sampleDuration, samples: recording.samples, averageFrameRate: recording.averageFrameRate,
            frameCount: recording.frameCount, camera: recording.camera, quality: recording.quality, source: .syntheticUITest)
        let processed = try await MeasurementProcessor().process(synthetic)
        #expect(processed.model.classification == .unavailable)
        #expect(processed.model.afibScore == nil)
    }

    private func modelArtifacts() throws -> URL {
        // Repository-relative artifact path; no network, downloads, or training during tests.
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Research/Model/artifacts")
    }
}
