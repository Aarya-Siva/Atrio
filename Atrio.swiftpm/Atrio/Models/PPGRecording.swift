import Foundation

struct PPGRecording: Identifiable, Sendable, Codable {
    let id: UUID
    let startDate: Date
    /// Monotonic collection window; sampleDuration preserves the actual first/last PTS span.
    let duration: TimeInterval
    let sampleDuration: TimeInterval
    let samples: [PPGSample]
    let averageFrameRate: Double
    let frameCount: Int
    let camera: PPGCameraMetadata
    let quality: PPGQualityMetadata
    var mode: MeasurementMode? = nil
    var source: RecordingSource? = nil
}

enum RecordingSource: String, Codable, Sendable {
    case camera, syntheticUITest
}

enum MeasurementMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case resting, repeatMeasurement, rhythmStability

    var id: String { rawValue }
    var duration: Double { self == .rhythmStability ? 60 : 30 }
    var title: String {
        switch self {
        case .resting: "Resting pulse"
        case .repeatMeasurement: "Repeat measurement"
        case .rhythmStability: "Rhythm stability"
        }
    }
    var detail: String {
        switch self {
        case .resting: "A 30-second pulse recording while resting comfortably."
        case .repeatMeasurement: "Repeat a 30-second recording under similar conditions and compare with your previous saved resting or repeat measurement."
        case .rhythmStability: "A 60-second recording to observe pulse timing over a longer window. This is not a separate diagnostic test."
        }
    }
}

enum PositioningAid: String, CaseIterable, Identifiable, Codable, Sendable {
    case unaided, prototype
    var id: String { rawValue }
    var title: String { self == .unaided ? "Without attachment" : "With attachment" }
}

struct PPGCameraMetadata: Sendable, Codable {
    let deviceModel: String
    let osVersion: String
    let cameraName: String
    let cameraID: String
    let width: Int
    let height: Int
    let nominalFrameRate: Double
    let pixelFormat: String
    let roiFraction: Double
    let samplingStride: Int
    var torchLevel: Float
    var exposureLocked: Bool = false
    var whiteBalanceLocked: Bool = false
    var focusLocked: Bool = false
    var exposureSeconds: Double = 0
    var iso: Float = 0
    var whiteBalanceRedGain: Float = 0
    var whiteBalanceGreenGain: Float = 0
    var whiteBalanceBlueGain: Float = 0
    var detectorProfile: FingerDetectionConfiguration = .init()
    var thermalState: String = "nominal"
    /// Optional so recordings saved before accessory comparisons remain readable.
    var positioningAid: PositioningAid? = nil
}

struct PPGQualityMetadata: Sendable, Codable {
    let suitableFrames: Int
    let conditionCounts: [String: Int]
    let droppedFrames: Int
    let extractionFailures: Int
    let rejectedTimestamps: Int
    let maximumFrameGap: Double
    let potentiallyInvalid: Bool
    let notes: [String]
}
