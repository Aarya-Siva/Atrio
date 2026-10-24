import Foundation

/// Deterministic exploratory processing, not a validated medical algorithm.
/// Raw samples are never modified. Gaps and unsuitable frames split the signal;
/// no interval is measured across a rejected section.
struct PulseAnalyzer: Sendable {
    private let sampleRate = 30.0
    private let edgeTrim = 0.75

    func analyze(_ recording: PPGRecording) throws -> PulseAnalysis {
        try analyze(samples: recording.samples, duration: recording.duration, minimumUsableDuration: 20,
                    maximumFrameGap: recording.quality.maximumFrameGap,
                    droppedFrames: recording.quality.droppedFrames,
                    settingsLocked: recording.camera.exposureLocked && recording.camera.whiteBalanceLocked)
    }

    /// Shared deterministic processing for camera recordings and normalized model windows.
    fileprivate func analyze(samples: [PPGSample], duration: Double, minimumUsableDuration: Double,
                             maximumFrameGap: Double = 0, droppedFrames: Int = 0,
                             settingsLocked: Bool = true) throws -> PulseAnalysis {
        try Task.checkCancellation()
        guard samples.count >= 2, samples.count <= 7200,
              duration.isFinite, (5...120).contains(duration),
              samples.allSatisfy({ sample in
                  sample.timestamp.isFinite && [sample.red, sample.green, sample.blue].allSatisfy {
                      $0.isFinite && (0...255).contains($0)
                  }
              }), zip(samples, samples.dropFirst()).allSatisfy({ $1.timestamp > $0.timestamp }) else {
            return rejected("The recording contains missing, invalid, or out-of-order camera data.")
        }
        let origin = samples[0].timestamp
        let span = samples[samples.count - 1].timestamp - origin
        guard span <= duration + 0.5, span > 0,
              Double(samples.count - 1) / span >= 20 else {
            return rejected("The sample timing or frame rate is unsuitable for pulse analysis.")
        }

        var runs: [[PPGSample]] = []
        var run: [PPGSample] = []
        for sample in samples {
            if sample.condition != .suitable || run.last.map({ sample.timestamp - $0.timestamp > 0.15 }) == true {
                if !run.isEmpty { runs.append(run); run.removeAll(keepingCapacity: true) }
            }
            if sample.condition == .suitable { run.append(sample) }
        }
        if !run.isEmpty { runs.append(run) }

        var waveform: [PulsePoint] = []
        var peaks: [PulsePoint] = []
        var intervals: [PulseInterval] = []
        var usableDuration = 0.0
        var rejectedRuns = 0
        for (segment, values) in runs.enumerated() {
            try Task.checkCancellation()
            guard let first = values.first, let last = values.last,
                  last.timestamp - first.timestamp >= 6 else { rejectedRuns += 1; continue }
            let raw = resample(values)
            guard raw.count > 180 else { rejectedRuns += 1; continue }
            let filtered = bandpass(raw)
            let trim = Int(edgeTrim * sampleRate)
            let middle = Array(filtered[trim..<(filtered.count - trim)])
            let amplitude = rms(middle)
            // Signal must have measurable pulsation and not be dominated by rapid frame noise.
            let differences = zip(raw, raw.dropFirst()).map { $1 - $0 }
            let highFrequencyNoise = rms(differences) / max(amplitude, 0.0001)
            guard amplitude >= 0.05, highFrequencyNoise < 1.6 else { rejectedRuns += 1; continue }
            let normalized = filtered.map { $0 / amplitude }
            let indices = detectPeaks(normalized, trim: trim)
            var accepted: [PulseInterval] = []
            for (left, right) in zip(indices, indices.dropFirst()) {
                let seconds = Double(right - left) / sampleRate
                // Broad measurement bounds, not a "normal rhythm" range. Irregular intervals
                // inside these limits are retained, not replaced or forced toward a median.
                if (1.0 / 3.0...1.5).contains(seconds) {
                    accepted.append(PulseInterval(time: first.timestamp - origin + Double(right) / sampleRate,
                                                  milliseconds: seconds * 1000, segment: segment))
                }
            }
            let retainedDuration = accepted.reduce(0) { $0 + $1.milliseconds / 1000 }
            let availableDuration = Double(raw.count - 2 * trim) / sampleRate
            guard accepted.count >= 3, indices.count > 1,
                  Double(accepted.count) / Double(indices.count - 1) >= 0.85,
                  retainedDuration / availableDuration >= 0.65 else { rejectedRuns += 1; continue }
            let points = (trim..<(raw.count - trim)).map { i in
                PulsePoint(time: first.timestamp - origin + Double(i) / sampleRate,
                           value: normalized[i], segment: segment)
            }
            waveform.append(contentsOf: points)
            peaks.append(contentsOf: indices.map { i in
                PulsePoint(time: first.timestamp - origin + Double(i) / sampleRate,
                           value: normalized[i], segment: segment)
            })
            intervals.append(contentsOf: accepted)
            usableDuration += availableDuration
        }

        let coverage = min(1, usableDuration / duration)
        let sufficient = usableDuration >= minimumUsableDuration && coverage >= 0.75 && intervals.count >= (duration <= 10 ? 3 : 10)
        var reasons: [String] = []
        if !sufficient { reasons.append("At least \(minimumUsableDuration.formatted()) seconds and 75% usable coverage are needed to report an estimate.") }
        if rejectedRuns > 0 || samples.contains(where: { $0.condition != .suitable }) {
            reasons.append("Short, noisy, or uncovered sections were excluded; intervals do not cross these gaps.")
        }
        if maximumFrameGap > 0.15 || droppedFrames > 0 {
            reasons.append("Camera frame gaps were detected and assessed separately.")
        }
        if !settingsLocked {
            reasons.append("Some automatic camera adjustments remained active.")
        }
        if sufficient { reasons.insert("The recording passed exploratory optical and pulse checks. This is not clinical validation.", at: 0) }
        let features = sufficient ? features(from: intervals) : nil
        return PulseAnalysis(algorithmVersion: PulseAnalysis.currentVersion,
                             quality: sufficient ? .usable : (waveform.isEmpty ? .insufficient : .limited),
                             reasons: reasons, usableDuration: usableDuration, coverage: coverage,
                             estimatedHeartRate: features.map { 60000 / $0.meanIntervalMS },
                             features: features, waveform: waveform, peaks: peaks, intervals: intervals)
    }

    private func rejected(_ reason: String) -> PulseAnalysis {
        PulseAnalysis(algorithmVersion: PulseAnalysis.currentVersion, quality: .insufficient,
                      reasons: [reason], usableDuration: 0, coverage: 0, estimatedHeartRate: nil,
                      features: nil, waveform: [], peaks: [], intervals: [])
    }

    private func resample(_ samples: [PPGSample]) -> [Double] {
        let start = samples[0].timestamp
        let count = Int((samples[samples.count - 1].timestamp - start) * sampleRate) + 1
        var cursor = 0
        return (0..<count).map { i in
            let time = start + Double(i) / sampleRate
            while cursor + 1 < samples.count - 1 && samples[cursor + 1].timestamp < time { cursor += 1 }
            let a = samples[cursor], b = samples[cursor + 1]
            let weight = min(1, max(0, (time - a.timestamp) / (b.timestamp - a.timestamp)))
            // Increased absorption lowers reflected red intensity. Inversion gives positive pulses.
            return -(a.red + weight * (b.red - a.red))
        }
    }

    private func bandpass(_ input: [Double]) -> [Double] {
        let padding = min(60, input.count - 1)
        let mean = input.reduce(0, +) / Double(input.count)
        let centered = input.map { $0 - mean }
        var values = Array(centered[1...padding].reversed()) + centered + Array(centered.suffix(padding).reversed())
        // Forward/backward second-order Butterworth filters avoid phase-shifting peak times.
        for _ in 0..<2 {
            values = filter(values, cutoff: 0.5, highpass: true)
            values = filter(values, cutoff: 4, highpass: false)
            values.reverse()
        }
        return Array(values[padding..<(padding + input.count)])
    }

    private func filter(_ input: [Double], cutoff: Double, highpass: Bool) -> [Double] {
        let k = tan(.pi * cutoff / sampleRate)
        let norm = 1 / (1 + sqrt(2) * k + k * k)
        let b0 = (highpass ? 1 : k * k) * norm
        let b1 = (highpass ? -2 : 2) * b0
        let a1 = 2 * (k * k - 1) * norm
        let a2 = (1 - sqrt(2) * k + k * k) * norm
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        return input.map { x in
            let y = b0 * x + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }

    private func detectPeaks(_ values: [Double], trim: Int) -> [Int] {
        var peaks: [Int] = []
        for i in trim..<(values.count - trim) {
            guard values[i] > values[i - 1], values[i] >= values[i + 1], values[i] > 0.15 else { continue }
            let left = values[max(0, i - 9)...i].min() ?? values[i]
            let right = values[i...min(values.count - 1, i + 9)].min() ?? values[i]
            guard values[i] - max(left, right) > 0.5 else { continue }
            if let previous = peaks.last, i - previous < 9 {
                if values[i] > values[previous] { peaks[peaks.count - 1] = i }
            } else { peaks.append(i) }
        }
        return peaks
    }

    private func features(from intervals: [PulseInterval]) -> RhythmFeatures {
        let values = intervals.map(\.milliseconds)
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(max(1, values.count - 1))
        // Only adjacent retained intervals within a segment contribute to successive differences.
        let differences = zip(intervals, intervals.dropFirst()).compactMap { a, b -> Double? in
            guard a.segment == b.segment, abs((b.time - a.time) * 1000 - b.milliseconds) < 1 else { return nil }
            return b.milliseconds - a.milliseconds
        }
        return RhythmFeatures(meanIntervalMS: mean, sdnnMS: sqrt(variance), rmssdMS: rms(differences),
                              pnn50: Double(differences.filter { abs($0) > 50 }.count) / Double(max(1, differences.count)),
                              intervalCV: sqrt(variance) / mean)
    }

    private func rms(_ values: [Double]) -> Double {
        sqrt(values.reduce(0) { $0 + $1 * $1 } / Double(max(1, values.count)))
    }
}

/// Model-only 10-second windows. Whole-recording quality still requires >=20 usable seconds.
/// Training invokes this exact Swift code; original camera and dataset arrays are untouched.
enum RhythmWindowExtractor {
    static let version = "pulse-window-v1"
    static let featureNames = ["mean_interval_ms", "sdnn_ms", "rmssd_ms", "pnn50", "interval_cv"]

    static func features(timestamps: [Double], intensities: [Double], positivePulses: Bool,
                         conditions: [OpticalCondition]? = nil) throws -> RhythmFeatures? {
        guard timestamps.count == intensities.count, (200...2000).contains(timestamps.count),
              conditions == nil || conditions?.count == timestamps.count,
              let first = timestamps.first, let last = timestamps.last,
              (9.5...10.1).contains(last - first),
              timestamps.allSatisfy(\.isFinite), intensities.allSatisfy(\.isFinite),
              zip(timestamps, timestamps.dropFirst()).allSatisfy({ $1 > $0 && $1 - $0 <= 0.15 }) else { return nil }
        let mean = intensities.reduce(0, +) / Double(intensities.count)
        let deviation = sqrt(intensities.reduce(0) { $0 + pow($1 - mean, 2) } / Double(intensities.count))
        guard deviation > 0.000000001 else { return nil }
        // Native source sensor pulses are positive; reflected camera intensity is inverted.
        // Normalize scale before the identical 30 Hz filtering/peak/interval pipeline.
        let normalized = intensities.map { min(255, max(0, 127 + (positivePulses ? -1 : 1) * 12 * ($0 - mean) / deviation)) }
        let samples = timestamps.indices.map { index in
            PPGSample(timestamp: timestamps[index] - first, red: normalized[index], green: 0, blue: 0,
                      condition: conditions?[index] ?? .suitable)
        }
        let result = try PulseAnalyzer().analyze(samples: samples, duration: 10, minimumUsableDuration: 7.5)
        return result.quality == .usable ? result.features : nil
    }

    static func cameraWindows(_ recording: PPGRecording) throws -> [RhythmFeatures] {
        guard let origin = recording.samples.first?.timestamp else { return [] }
        var result: [RhythmFeatures] = []
        for index in 0..<Int(recording.duration / 10) {
            try Task.checkCancellation()
            let start = origin + Double(index) * 10
            let window = recording.samples.filter { $0.timestamp >= start && $0.timestamp < start + 10 }
            if let features = try features(timestamps: window.map(\.timestamp), intensities: window.map(\.red),
                                           positivePulses: false, conditions: window.map(\.condition)) {
                result.append(features)
            }
        }
        return result
    }
}
