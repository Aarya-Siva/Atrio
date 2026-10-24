import Foundation

enum SignalQuality: String, Codable, Sendable {
    case usable, limited, insufficient

    var title: String {
        switch self {
        case .usable: "Usable signal"
        case .limited: "Limited signal"
        case .insufficient: "Insufficient signal"
        }
    }
}

struct PulsePoint: Identifiable, Codable, Sendable {
    let time: Double
    let value: Double
    let segment: Int
    var id: Double { time }
}

struct PulseInterval: Identifiable, Codable, Sendable {
    let time: Double
    let milliseconds: Double
    let segment: Int
    var id: Double { time }
}

struct RhythmFeatures: Codable, Sendable {
    let meanIntervalMS: Double
    let sdnnMS: Double
    let rmssdMS: Double
    let pnn50: Double
    let intervalCV: Double

    /// Contract shared with the optional research model. No clinical interpretation is implied.
    var modelInputs: [String: Double] {
        ["mean_interval_ms": meanIntervalMS, "sdnn_ms": sdnnMS,
         "rmssd_ms": rmssdMS, "pnn50": pnn50, "interval_cv": intervalCV]
    }
}

struct PulseAnalysis: Codable, Sendable {
    static let currentVersion = "pulse-v1"
    let algorithmVersion: String
    let quality: SignalQuality
    let reasons: [String]
    let usableDuration: Double
    let coverage: Double
    let estimatedHeartRate: Double?
    let features: RhythmFeatures?
    let waveform: [PulsePoint]
    let peaks: [PulsePoint]
    let intervals: [PulseInterval]
}

enum RhythmClassification: String, Codable, Sendable {
    case unavailable, inconclusive, afibLike, noAFibLike

    var title: String {
        switch self {
        case .unavailable: "Model unavailable"
        case .inconclusive: "Inconclusive"
        case .afibLike: "AFib-like pattern identified"
        case .noAFibLike: "No AFib-like pattern identified"
        }
    }
}

struct ResearchModelOutput: Codable, Sendable {
    let classification: RhythmClassification
    let explanation: String
    let modelVersion: String?
    let afibScore: Double?
    var evaluatedWindows: Int? = nil
    var featureContributions: [String: Double]? = nil
    var explanationBaseline: Double? = nil
    var sourceDomain: String? = nil
}

struct Measurement: Codable, Identifiable, Sendable {
    let schemaVersion: Int
    let recording: PPGRecording
    let analysis: PulseAnalysis
    let model: ResearchModelOutput
    var id: UUID { recording.id }

    var summary: MeasurementSummary {
        MeasurementSummary(id: id, date: recording.startDate, duration: recording.duration,
                           heartRate: analysis.estimatedHeartRate, quality: analysis.quality,
                           classification: model.classification, mode: recording.mode ?? .resting)
    }
}

struct MeasurementSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let duration: Double
    let heartRate: Double?
    let quality: SignalQuality
    let classification: RhythmClassification
    let mode: MeasurementMode
}

enum ResearchNotice {
    static let title = "About your result"
    static let detail = "Atrio has not been clinically validated. It cannot diagnose or rule out AFib or predict stroke. An ECG is needed to confirm a rhythm diagnosis. Do not change treatment based on these results."
}
