import Foundation

/// Collection is bounded by host-clock time. PTS values remain unchanged in raw samples.
struct PPGRecordingAccumulator: Sendable {
    let targetDuration: Double
    let mode: MeasurementMode
    private(set) var state: RecordingState = .idle
    private(set) var samples: [PPGSample] = []
    private(set) var startHostTime: Double?
    private var startDate: Date?
    private var metadata: PPGCameraMetadata?
    private(set) var rejectedTimestamps = 0
    private(set) var maximumFrameGap = 0.0
    var droppedFrames = 0
    var extractionFailures = 0
    private var counts: [String: Int] = [:]
    private var firstCaptureHostTime: Double?
    private var lastCaptureHostTime: Double?

    init(duration: Double = 30, mode: MeasurementMode = .resting) {
        targetDuration = duration
        self.mode = mode
    }

    mutating func initialize() { if state == .idle { state = .initializing } }
    mutating func ready() { if state == .initializing { state = .ready } }

    mutating func start(at hostTime: Double, date: Date, camera: PPGCameraMetadata) {
        guard state == .ready, hostTime.isFinite else { return }
        startHostTime = hostTime
        startDate = date
        metadata = camera
        state = .recording
    }

    mutating func append(_ frame: OpticalFrame, condition: OpticalCondition, captureHostTime: Double) {
        guard state == .recording, let startHostTime,
              captureHostTime.isFinite, captureHostTime >= startHostTime,
              captureHostTime - startHostTime < targetDuration,
              frame.timestamp.isFinite, frame.red.isFinite, frame.green.isFinite, frame.blue.isFinite else { return }
        if let last = samples.last {
            guard frame.timestamp > last.timestamp else { rejectedTimestamps += 1; return }
            maximumFrameGap = max(maximumFrameGap, frame.timestamp - last.timestamp)
        }
        if firstCaptureHostTime == nil { firstCaptureHostTime = captureHostTime }
        lastCaptureHostTime = captureHostTime
        // Bounds memory even if the camera unexpectedly ignores the requested frame rate.
        guard samples.count < 3600 else { state = .failed; samples.removeAll(); return }
        samples.append(PPGSample(timestamp: frame.timestamp, red: frame.red, green: frame.green,
                                 blue: frame.blue, condition: condition))
        counts[condition.rawValue, default: 0] += 1
    }

    func elapsed(at hostTime: Double) -> Double {
        guard let startHostTime else { return 0 }
        return min(targetDuration, max(0, hostTime - startHostTime))
    }

    func isDue(at hostTime: Double) -> Bool {
        state == .recording && startHostTime.map { hostTime - $0 >= targetDuration } == true
    }

    mutating func complete(at hostTime: Double) -> PPGRecording? {
        guard isDue(at: hostTime), let startDate, let metadata, let startHostTime,
              let firstCaptureHostTime, let lastCaptureHostTime,
              let first = samples.first, let last = samples.last, samples.count >= 2 else { return nil }
        let span = last.timestamp - first.timestamp
        guard span > 0 else { return nil }
        // Include missing data at either boundary, not only gaps between retained frames.
        maximumFrameGap = max(maximumFrameGap, firstCaptureHostTime - startHostTime,
                              startHostTime + targetDuration - lastCaptureHostTime)
        let suitable = counts[OpticalCondition.suitable.rawValue, default: 0]
        var notes = ["Preliminary optical coverage only; no physiological pulse or clinical quality validation has run."]
        if suitable != samples.count { notes.append("Coverage or brightness was unsuitable in some frames.") }
        if maximumFrameGap > 0.2 || droppedFrames > 0 { notes.append("Frame gaps, incomplete boundary coverage, or dropped frames were observed.") }
        if !metadata.exposureLocked || !metadata.whiteBalanceLocked {
            notes.append("This camera did not lock every automatic adjustment.")
        }
        let result = PPGRecording(id: UUID(), startDate: startDate, duration: targetDuration,
                                 sampleDuration: span, samples: samples,
                                 averageFrameRate: Double(samples.count - 1) / span, frameCount: samples.count,
                                 camera: metadata,
                                 quality: PPGQualityMetadata(suitableFrames: suitable, conditionCounts: counts,
                                    droppedFrames: droppedFrames, extractionFailures: extractionFailures,
                                    rejectedTimestamps: rejectedTimestamps, maximumFrameGap: maximumFrameGap,
                                    potentiallyInvalid: suitable != samples.count || maximumFrameGap > 0.2 ||
                                        droppedFrames > 0 || extractionFailures > 0 || rejectedTimestamps > 0,
                                    notes: notes), mode: mode, source: .camera)
        state = .completed
        samples.removeAll(keepingCapacity: false)
        return result
    }

    mutating func discard(failed: Bool = false) {
        guard state != .completed && state != .cancelled else { return }
        samples.removeAll(keepingCapacity: false)
        startHostTime = nil
        startDate = nil
        metadata = nil
        firstCaptureHostTime = nil
        lastCaptureHostTime = nil
        counts.removeAll()
        state = failed ? .failed : .cancelled
    }
}
