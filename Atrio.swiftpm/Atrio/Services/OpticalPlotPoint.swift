import Foundation

/// Display-only normalization. Raw PPGSample RGB values are never mutated.
struct OpticalPlotPoint: Identifiable, Sendable {
    let id: Double
    let seconds: Double
    let intensity: Double
    let segment: Int

    static func make(from samples: [PPGSample]) -> [OpticalPlotPoint] {
        guard let latest = samples.last else { return [] }
        let valid = samples.filter { $0.condition == .suitable && $0.red.isFinite && $0.timestamp >= latest.timestamp - 8 }
        guard valid.count >= 2 else { return [] }
        let mean = valid.reduce(0) { $0 + $1.red } / Double(valid.count)
        let span = max(1, (valid.map(\.red).max() ?? mean) - (valid.map(\.red).min() ?? mean))
        var result: [OpticalPlotPoint] = []
        var segment = 0, previous: Double?
        for sample in samples where sample.timestamp >= latest.timestamp - 8 {
            guard sample.condition == .suitable, sample.red.isFinite else { segment += 1; previous = nil; continue }
            if let previous, sample.timestamp - previous > 0.2 { segment += 1 }
            result.append(OpticalPlotPoint(id: sample.timestamp, seconds: sample.timestamp - latest.timestamp,
                                          intensity: (sample.red - mean) / span, segment: segment))
            previous = sample.timestamp
        }
        return result
    }
}
