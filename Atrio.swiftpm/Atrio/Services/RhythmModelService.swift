import CoreML
import Foundation

/// Trained source-sensor research model; never substitutes rules for absent/incompatible weights.
actor RhythmModelService {
    private var model: MLModel?
    private var manifest: ModelManifest?
    private var forest: ModelExplanationForest?
    private let modelDirectory: URL?

    init(modelDirectory: URL? = nil) { self.modelDirectory = modelDirectory }

    func evaluate(_ analysis: PulseAnalysis, recording: PPGRecording? = nil) -> ResearchModelOutput {
        guard analysis.quality == .usable, analysis.features != nil else {
            return output(.inconclusive, "Signal quality was insufficient for rhythm classification.")
        }
        #if SWIFT_PACKAGE && !ATRIO_CORE_TESTS
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        func resource(_ name: String, _ ext: String) -> URL? {
            if let modelDirectory {
                let url = modelDirectory.appendingPathComponent(name).appendingPathExtension(ext)
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            }
            return bundle.url(forResource: name, withExtension: ext)
        }
        let precompiledURL = resource("AFibResearch", "mlmodelc")
        let serializedURL = resource("AFibResearch", "modeldata")
        guard precompiledURL != nil || serializedURL != nil,
              let manifestURL = resource("AFibResearch", "json"),
              let explanationURL = resource("AFibResearch.explainer", "json") else {
            return output(.unavailable, "The rhythm model is not installed. Pulse estimates and signal analysis remain available.")
        }
        do {
            if model == nil {
                let metadata = try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: manifestURL))
                guard metadata.algorithmVersion == analysis.algorithmVersion,
                      metadata.featureVersion == RhythmWindowExtractor.version,
                      metadata.coreMLParityVerified, metadata.windowSeconds == 10, metadata.minimumWindows >= 2,
                      !metadata.version.isEmpty, !metadata.evaluationSummary.isEmpty,
                      metadata.lowerThreshold.isFinite, metadata.upperThreshold.isFinite,
                      metadata.lowerThreshold >= 0, metadata.upperThreshold <= 1,
                      metadata.lowerThreshold < metadata.upperThreshold else {
                    return output(.unavailable, "The model does not match this processing version or its verification metadata is incomplete.")
                }
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .cpuOnly
                let modelURL: URL
                if let precompiledURL { modelURL = precompiledURL }
                else if let serializedURL {
                    // Swift app packages otherwise schedule this model's compilation twice.
                    // Compile the bundled protobuf once on this background actor; no download.
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let source = directory.appendingPathComponent("AFibResearch.mlmodel")
                    try FileManager.default.copyItem(at: serializedURL, to: source)
                    modelURL = try MLModel.compileModel(at: source)
                } else { return output(.unavailable, "The model resource is missing.") }
                let loaded = try MLModel(contentsOf: modelURL, configuration: configuration)
                let inputs = loaded.modelDescription.inputDescriptionsByName
                let explanation = try JSONDecoder().decode(ModelExplanationForest.self, from: Data(contentsOf: explanationURL))
                guard Set(inputs.keys) == Set(RhythmWindowExtractor.featureNames),
                      inputs.values.allSatisfy({ $0.type == .double }),
                      loaded.modelDescription.outputDescriptionsByName["afibProbability"]?.type == .double,
                      explanation.isValid else {
                    return output(.unavailable, "The model or its explanation data has an incompatible format.")
                }
                model = loaded
                manifest = metadata
                forest = explanation
            }
            guard let model, let manifest, let forest, let recording else {
                return output(.unavailable, "Original camera samples are required for this model version.")
            }
            let windows = try RhythmWindowExtractor.cameraWindows(recording)
            guard windows.count >= manifest.minimumWindows else {
                return output(.inconclusive, "At least two usable, separate 10-second camera windows are needed. No missing signal was replaced.")
            }
            var margins: [Double] = [], scores: [Double] = [], explanations: [[Double]] = []
            var baseline: Double?
            for window in windows {
                try Task.checkCancellation()
                let inputs = window.modelInputs.mapValues { Double(Float($0)) }
                guard inputs.values.allSatisfy(\.isFinite) else { return output(.inconclusive, "Pulse features were not finite.") }
                let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: inputs))
                guard let value = prediction.featureValue(for: "afibProbability"), value.type == .double,
                      value.doubleValue.isFinite, (0...1).contains(value.doubleValue) else {
                    return output(.unavailable, "The model returned an invalid output.")
                }
                let ordered = forest.featureNames.map { inputs[$0]! }
                let margin = forest.margin(ordered)
                let score = 1 / (1 + exp(-margin))
                guard abs(score - value.doubleValue) < 0.00001 else {
                    return output(.unavailable, "Model predictions and explanation weights did not agree. No classification is shown.")
                }
                let explanation = try forest.explain(ordered)
                baseline = explanation.baseline
                margins.append(margin); scores.append(score); explanations.append(explanation.contributions)
            }
            let meanMargin = margins.reduce(0, +) / Double(margins.count)
            let score = 1 / (1 + exp(-meanMargin))
            let disagree = scores.contains { $0 >= manifest.upperThreshold } && scores.contains { $0 <= manifest.lowerThreshold }
            let classification: RhythmClassification = disagree ? .inconclusive : (score >= manifest.upperThreshold ? .afibLike
                : (score <= manifest.lowerThreshold ? .noAFibLike : .inconclusive))
            let contributions = Dictionary(uniqueKeysWithValues: forest.featureNames.enumerated().map { index, name in
                (name, explanations.reduce(0) { $0 + $1[index] } / Double(explanations.count))
            })
            return ResearchModelOutput(classification: classification,
                explanation: "Analyzed \(windows.count) usable signal windows. \(disagree ? "Windows disagreed, so the result is inconclusive." : "Conservative thresholds can leave a result inconclusive.")",
                modelVersion: manifest.version, afibScore: score, evaluatedWindows: windows.count,
                featureContributions: contributions, explanationBaseline: baseline,
                sourceDomain: manifest.sourceDomain)
        } catch {
            return output(.unavailable, "The rhythm model could not run. Your recording and signal analysis are still available.")
        }
    }

    private func output(_ classification: RhythmClassification, _ explanation: String) -> ResearchModelOutput {
        ResearchModelOutput(classification: classification, explanation: explanation, modelVersion: nil, afibScore: nil)
    }
}

private struct ModelManifest: Decodable {
    let version: String
    let algorithmVersion: String
    let featureVersion: String
    let evaluationSummary: String
    let lowerThreshold: Double
    let upperThreshold: Double
    let windowSeconds: Int
    let minimumWindows: Int
    let sourceDomain: String
    let coreMLParityVerified: Bool
}

/// Exact interventional Shapley values of the learned tree margin, using a fixed training-only
/// background. Five inputs require 32 coalitions. Values explain model behavior, not disease.
struct ModelExplanationForest: Decodable, Sendable {
    struct Node: Decodable, Sendable {
        let id: Int
        let feature: Int?
        let threshold: Double?
        let yes: Int?
        let no: Int?
        let leaf: Double?
    }
    let featureNames: [String]
    let baseMargin: Double
    let trees: [[Node]]
    let background: [[Double]]

    var isValid: Bool {
        guard featureNames == RhythmWindowExtractor.featureNames, baseMargin.isFinite,
              (1...1000).contains(trees.count), (1...64).contains(background.count),
              background.allSatisfy({ $0.count == 5 && $0.allSatisfy(\.isFinite) }) else { return false }
        return trees.allSatisfy { nodes in
            guard (1...1000).contains(nodes.count) else { return false }
            return nodes.enumerated().allSatisfy { index, node in
                guard node.id == index else { return false }
                if let leaf = node.leaf { return leaf.isFinite && node.feature == nil }
                guard let feature = node.feature, (0..<5).contains(feature), let threshold = node.threshold, threshold.isFinite,
                      let yes = node.yes, let no = node.no,
                      yes > index, no > index, yes < nodes.count, no < nodes.count else { return false }
                return true
            }
        }
    }

    func margin(_ features: [Double]) -> Double {
        var result = baseMargin
        for tree in trees {
            var index = 0
            while tree[index].leaf == nil {
                let node = tree[index]
                index = features[node.feature!] < node.threshold! ? node.yes! : node.no!
            }
            result += tree[index].leaf!
        }
        return result
    }

    func explain(_ features: [Double]) throws -> (baseline: Double, contributions: [Double]) {
        var coalition = [Double](repeating: 0, count: 32)
        for mask in 0..<32 {
            try Task.checkCancellation()
            for reference in background {
                let mixed = (0..<5).map { mask & (1 << $0) != 0 ? features[$0] : reference[$0] }
                coalition[mask] += margin(mixed) / Double(background.count)
            }
        }
        let weights = [0.2, 0.05, 1.0 / 30.0, 0.05, 0.2]
        let contributions = (0..<5).map { feature in
            (0..<32).filter { $0 & (1 << feature) == 0 }.reduce(0.0) { sum, mask in
                sum + weights[mask.nonzeroBitCount] * (coalition[mask | (1 << feature)] - coalition[mask])
            }
        }
        return (coalition[0], contributions)
    }
}
actor MeasurementProcessor {
    private let modelService = RhythmModelService()

    func process(_ recording: PPGRecording) async throws -> Measurement {
        let analysis = try PulseAnalyzer().analyze(recording)
        try Task.checkCancellation()
        let output: ResearchModelOutput
        if recording.source == .syntheticUITest {
            output = ResearchModelOutput(classification: .unavailable,
                explanation: "Synthetic UI fixture. No camera measurement or model prediction has been made.",
                modelVersion: nil, afibScore: nil)
        } else {
            output = await modelService.evaluate(analysis, recording: recording)
        }
        try Task.checkCancellation()
        return Measurement(schemaVersion: 1, recording: recording, analysis: analysis, model: output)
    }
}
