import CoreVideo
import Foundation
import Testing
@testable import AtrioCore

struct CaptureTests {
    @Test(arguments: [kCVPixelFormatType_32BGRA, kCVPixelFormatType_32ARGB])
    func extractsCentralROIWithCorrectChannelOrder(format: OSType) throws {
        var optional: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil, 8, 8, format, nil, &optional) == kCVReturnSuccess)
        let buffer = try #require(optional)
        #expect(CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess)
        let bytes = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<8 {
            for x in 0..<8 {
                let central = (2..<6).contains(x) && (2..<6).contains(y)
                let r: UInt8 = central ? 180 : 20
                let g: UInt8 = central ? 60 : 20
                let b: UInt8 = central ? 40 : 20
                let pixel: [UInt8] = format == kCVPixelFormatType_32BGRA ? [b, g, r, 255] : [255, r, g, b]
                for channel in 0..<4 { bytes[y * rowBytes + x * 4 + channel] = pixel[channel] }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let extractor = PPGSignalExtractor(configuration: PPGROIConfiguration(fraction: 0.5, stride: 1))
        let frame = try #require(extractor.extract(buffer, timestamp: 123.45))
        #expect(frame.timestamp == 123.45)
        #expect(frame.red == 180 && frame.green == 60 && frame.blue == 40)
        #expect(frame.redClippingFraction == 0 && frame.spatialVariation < 0.000001)
        #expect(extractor.extract(buffer, timestamp: .nan) == nil)
    }

    @Test(arguments: [30.0, 60.0])
    func collectionUsesHostDeadlineAndPreservesRawSamples(duration: Double) throws {
        var collector = prepared(duration: duration)
        for index in 0..<Int(duration * 30) {
            let time = Double(index) / 30
            collector.append(frame(timestamp: 100 + time), condition: .suitable, captureHostTime: 50 + time)
        }
        collector.append(frame(timestamp: 100 + duration), condition: .suitable, captureHostTime: 50 + duration)
        #expect(!collector.isDue(at: 50 + duration - 0.001))
        let premature = collector.complete(at: 50 + duration - 0.001)
        #expect(premature == nil)
        let completed = collector.complete(at: 50 + duration)
        let recording = try #require(completed)
        #expect(recording.duration == duration)
        #expect(recording.frameCount == Int(duration * 30))
        #expect(abs(recording.averageFrameRate - 30) < 0.001)
        #expect(recording.samples[0].timestamp == 100)
        #expect(recording.samples[0].red == 180)
        #expect(recording.camera.positioningAid == .prototype)
        #expect(recording.source == .camera)
        #expect(!recording.quality.potentiallyInvalid)
        #expect(collector.samples.isEmpty)
    }

    @Test func boundaryGapsAndDuplicateTimestampsAreFlagged() throws {
        var collector = prepared()
        collector.append(frame(timestamp: 102), condition: .suitable, captureHostTime: 52)
        collector.append(frame(timestamp: 102), condition: .suitable, captureHostTime: 52.1)
        collector.append(frame(timestamp: 110), condition: .moving, captureHostTime: 60)
        let completed = collector.complete(at: 80)
        let result = try #require(completed)
        #expect(result.quality.rejectedTimestamps == 1)
        #expect(result.quality.maximumFrameGap == 20)
        #expect(result.quality.potentiallyInvalid)
        #expect(result.samples.last?.condition == .moving)
    }

    @Test func cancellationClearsCollectedData() {
        var collector = prepared()
        collector.append(frame(timestamp: 100), condition: .suitable, captureHostTime: 50)
        collector.discard()
        #expect(collector.state == .cancelled)
        #expect(collector.samples.isEmpty && collector.startHostTime == nil)
        let completed = collector.complete(at: 80)
        #expect(completed == nil)
    }

    @Test func olderMetadataRemainsReadable() throws {
        let camera = Fixture.recording().camera
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(camera)) as? [String: Any])
        object.removeValue(forKey: "positioningAid")
        let decoded = try JSONDecoder().decode(PPGCameraMetadata.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.positioningAid == nil)
    }

    private func prepared(duration: Double = 30) -> PPGRecordingAccumulator {
        var camera = Fixture.recording().camera
        camera.positioningAid = .prototype
        var collector = PPGRecordingAccumulator(duration: duration)
        collector.initialize()
        collector.ready()
        collector.start(at: 50, date: Date(), camera: camera)
        return collector
    }

    private func frame(timestamp: Double) -> OpticalFrame {
        OpticalFrame(timestamp: timestamp, red: 180, green: 60, blue: 40,
                     brightness: 0.36, spatialVariation: 0, redClippingFraction: 0,
                     allChannelClippingFraction: 0, blackFraction: 0)
    }
}
