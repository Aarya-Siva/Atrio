import Foundation

struct Input: Decodable {
    let signal: [Double]
    let sampleRate: Double
}
while let line = readLine() {
    do {
        let input = try JSONDecoder().decode(Input.self, from: Data(line.utf8))
        guard input.sampleRate.isFinite, input.sampleRate > 0 else { print("null"); continue }
        let times = input.signal.indices.map { Double($0) / input.sampleRate }
        if let features = try RhythmWindowExtractor.features(timestamps: times, intensities: input.signal, positivePulses: true) {
            print(String(decoding: try JSONEncoder().encode(features.modelInputs), as: UTF8.self))
        } else { print("null") }
    } catch { print("null") }
}
