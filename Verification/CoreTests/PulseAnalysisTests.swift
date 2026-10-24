import Foundation
import Testing
@testable import AtrioCore

struct PulseAnalysisTests {
    @Test(arguments: [45.0, 60.0, 72.0, 100.0, 150.0, 175.0])
    func estimatesKnownSyntheticPulseRates(bpm: Double) throws {
        let recording = Fixture.recording(bpm: bpm)
        let result = try PulseAnalyzer().analyze(recording)
        #expect(result.quality == .usable)
        let rate = try #require(result.estimatedHeartRate)
        #expect(abs(rate - bpm) < 2)
        #expect(result.coverage > 0.9)
        #expect(recording.samples.count == 900)
        #expect(recording.samples[0].red == 180)
    }

    @Test func rejectsFlatAndClippedSignals() throws {
        for recording in [Fixture.recording(amplitude: 0), Fixture.recording(condition: { _ in .clipped })] {
            let result = try PulseAnalyzer().analyze(recording)
            #expect(result.quality == .insufficient)
            #expect(result.estimatedHeartRate == nil)
            #expect(result.features == nil)
        }
    }

    @Test func rejectsInsufficientDurationAndCoverage() throws {
        for recording in [Fixture.recording(duration: 10), Fixture.recording(condition: { $0 < 15 ? .suitable : .uncovered })] {
            let result = try PulseAnalyzer().analyze(recording)
            #expect(result.quality != .usable)
            #expect(result.estimatedHeartRate == nil)
        }
    }

    @Test func rejectsHighFrequencyNoise() throws {
        let result = try PulseAnalyzer().analyze(Fixture.recording(noise: 10))
        #expect(result.quality == .insufficient)
        #expect(result.estimatedHeartRate == nil)
    }

    @Test func neverBridgesAnOpticalGap() throws {
        let result = try PulseAnalyzer().analyze(Fixture.recording(condition: { (14...15).contains($0) ? .moving : .suitable }))
        #expect(result.quality == .usable)
        #expect(Set(result.waveform.map(\.segment)).count == 2)
        #expect(result.intervals.allSatisfy { !($0.time > 14 && $0.time - $0.milliseconds / 1000 < 15) })
        #expect(result.intervals.allSatisfy { $0.milliseconds < 1000 })
    }

    @Test func rejectsInvalidAndDuplicateTimestamps() throws {
        let source = Fixture.recording()
        var duplicate = source.samples
        duplicate[20] = duplicate[19]
        var invalid = source.samples
        invalid[4] = PPGSample(timestamp: .nan, red: 180, green: 60, blue: 40, condition: .suitable)
        for samples in [duplicate, invalid, []] {
            let result = try PulseAnalyzer().analyze(Fixture.replacingSamples(source, samples: samples))
            #expect(result.quality == .insufficient)
            #expect(result.estimatedHeartRate == nil)
        }
    }

    @Test func toleratesSmallTimestampJitter() throws {
        let result = try PulseAnalyzer().analyze(Fixture.recording(jitter: true))
        let rate = try #require(result.estimatedHeartRate)
        #expect(abs(rate - 72) < 2)
    }

    @Test func preservesVariableIntervals() throws {
        let source = Fixture.recording()
        var phase = 0.0
        let samples = source.samples.map { sample in
            let time = sample.timestamp - 100
            let frequency = 1.2 + 0.25 * sin(2 * .pi * 0.16 * time)
            phase += 2 * .pi * frequency / 30
            return PPGSample(timestamp: sample.timestamp, red: 180 - 2 * sin(phase), green: 60, blue: 40, condition: .suitable)
        }
        let result = try PulseAnalyzer().analyze(Fixture.replacingSamples(source, samples: samples))
        let features = try #require(result.features)
        #expect(features.sdnnMS > 50)
        #expect(features.rmssdMS > 20)
    }

    @Test func absentModelDoesNotInventClassification() async throws {
        let service = RhythmModelService()
        let good = try PulseAnalyzer().analyze(Fixture.recording())
        let output = await service.evaluate(good)
        #expect(output.classification == .unavailable)
        #expect(output.afibScore == nil)
        let bad = try PulseAnalyzer().analyze(Fixture.recording(amplitude: 0))
        #expect(await service.evaluate(bad).classification == .inconclusive)
    }

    @Test func cancellationStopsAnalysis() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try PulseAnalyzer().analyze(Fixture.recording())
        }
        do {
            _ = try await task.value
            Issue.record("Canceled analysis unexpectedly completed")
        } catch { #expect(error is CancellationError) }
    }
}

enum Fixture {
    // Synthetic test data never enters normal app recording or saved history.
    static func recording(bpm: Double = 72, duration: Double = 30, amplitude: Double = 2,
                          noise: Double = 0, jitter: Bool = false,
                          condition: (Double) -> OpticalCondition = { _ in .suitable }) -> PPGRecording {
        let samples = (0..<Int(duration * 30)).map { index in
            let time = Double(index) / 30 + (jitter ? 0.002 * sin(Double(index)) : 0)
            let value = 180 - amplitude * sin(2 * .pi * bpm / 60 * time) + noise * sin(2 * .pi * 12 * time)
            return PPGSample(timestamp: 100 + time, red: value, green: 60, blue: 40, condition: condition(time))
        }
        return PPGRecording(id: UUID(), startDate: Date(timeIntervalSince1970: 1_700_000_000), duration: duration,
                            sampleDuration: Double(samples.count - 1) / 30, samples: samples, averageFrameRate: 30,
                            frameCount: samples.count,
                            camera: PPGCameraMetadata(deviceModel: "Synthetic test", osVersion: "Test", cameraName: "Test",
                                cameraID: "test", width: 640, height: 480, nominalFrameRate: 30, pixelFormat: "32BGRA",
                                roiFraction: 0.5, samplingStride: 4, torchLevel: 0.25, exposureLocked: true, whiteBalanceLocked: true),
                            quality: PPGQualityMetadata(suitableFrames: samples.count, conditionCounts: [:], droppedFrames: 0,
                                extractionFailures: 0, rejectedTimestamps: 0, maximumFrameGap: 1 / 30,
                                potentiallyInvalid: false, notes: ["Synthetic unit-test fixture"]))
    }

    static func replacingSamples(_ r: PPGRecording, samples: [PPGSample]) -> PPGRecording {
        PPGRecording(id: r.id, startDate: r.startDate, duration: r.duration, sampleDuration: r.sampleDuration,
                     samples: samples, averageFrameRate: r.averageFrameRate, frameCount: samples.count, camera: r.camera, quality: r.quality)
    }

    static func measurement() throws -> AtrioCore.Measurement {
        let recording = recording()
        return Measurement(schemaVersion: 1, recording: recording, analysis: try PulseAnalyzer().analyze(recording),
                           model: ResearchModelOutput(classification: .unavailable, explanation: "Test — no model", modelVersion: nil, afibScore: nil))
    }
}
