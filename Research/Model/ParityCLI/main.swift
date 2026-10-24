import CoreML
import Foundation
struct Vector: Decodable { let features: [String: Double]; let expected: Double }
let compiled = try MLModel.compileModel(at: URL(fileURLWithPath: CommandLine.arguments[1]))
let configuration = MLModelConfiguration()
configuration.computeUnits = .cpuOnly
let model = try MLModel(contentsOf: compiled, configuration: configuration)
let lines = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8).split(separator: "\n")
var maximumError = 0.0
for line in lines {
    let vector = try JSONDecoder().decode(Vector.self, from: Data(line.utf8))
    let values = vector.features.mapValues { Double(Float($0)) }
    let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: values))
    guard let feature = prediction.featureValue(for: "afibProbability"), feature.type == .double else { fatalError("Unexpected Core ML output") }
    let error = abs(feature.doubleValue - vector.expected)
    maximumError = max(maximumError, error)
    guard error < 0.00001 else { fatalError("Core ML parity failed: \(error)") }
}
print("Core ML parity passed: \(lines.count) real and threshold-boundary vectors, max absolute error \(maximumError)")
