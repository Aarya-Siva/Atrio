import Foundation

enum RecordingState: String, Sendable {
    case idle, initializing, ready, recording, completed, cancelled, failed
    var isTerminal: Bool { self == .completed || self == .cancelled || self == .failed }
}

struct RecordingSnapshot: Sendable {
    var state: RecordingState = .idle
    var condition: OpticalCondition = .unavailable
    var elapsed: Double = 0
    var duration: Double = 30
    var frameCount: Int = 0
    var samples: [PPGSample] = []
    var message: String = "Camera is not running."
    var latestSample: PPGSample? = nil
    var progress: Double { min(1, max(0, elapsed / duration)) }
    var remaining: Int { max(0, Int(ceil(duration - elapsed))) }
}

enum PPGCameraEvent: Sendable {
    case update(RecordingSnapshot)
    case completed(PPGRecording)
    case failed(String)
    case cancelled
}
