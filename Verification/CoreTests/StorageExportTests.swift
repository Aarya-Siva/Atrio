import Foundation
import Testing
@testable import AtrioCore

struct StorageExportTests {
    @Test func saveReopenAndDeleteRecording() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = MeasurementRepository(directory: directory)
        let measurement = try Fixture.measurement()
        try await repository.save(measurement)
        try await repository.save(measurement)
        let reopened = MeasurementRepository(directory: directory)
        let history = try await reopened.loadHistory()
        #expect(history.summaries.count == 1)
        let result = try await reopened.load(id: measurement.id)
        #expect(result.recording.samples.count == 900)
        #expect(result.recording.samples[100].red == measurement.recording.samples[100].red)
        #expect(result.analysis.estimatedHeartRate == measurement.analysis.estimatedHeartRate)
        #expect(result.model.classification == .unavailable)
        try await reopened.delete(id: measurement.id)
        #expect(try await reopened.loadHistory().summaries.isEmpty)
    }

    @Test func corruptRecordDoesNotEraseGoodRecord() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = MeasurementRepository(directory: directory)
        try await repository.save(Fixture.measurement())
        let damaged = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        try Data("not JSON".utf8).write(to: damaged)
        let history = try await repository.loadHistory()
        #expect(history.summaries.count == 1)
        #expect(history.unreadableCount == 1)
        #expect(FileManager.default.fileExists(atPath: damaged.path))
    }

    @Test func failedSaveIsReported() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("file, not directory".utf8).write(to: file)
        let repository = MeasurementRepository(directory: file)
        do {
            try await repository.save(Fixture.measurement())
            Issue.record("Saving into a file unexpectedly succeeded")
        } catch { #expect(!error.localizedDescription.isEmpty) }
    }

    @Test func rawExportPreservesOriginalSamplesAndMetadata() async throws {
        let measurement = try Fixture.measurement()
        let service = ResearchExport()
        let files = try await service.prepare(measurement)
        #expect(files.count == 3)
        let csv = try String(contentsOf: files[0], encoding: .utf8)
        let lines = csv.split(separator: "\n")
        #expect(lines.count == measurement.recording.samples.count + 1)
        #expect(lines[0] == "timestamp,red,green,blue,condition")
        let first = lines[1].split(separator: ",")
        #expect(Double(first[0]) == measurement.recording.samples[0].timestamp)
        #expect(Double(first[1]) == measurement.recording.samples[0].red)
        let metadata = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: files[2])) as? [String: Any])
        #expect(metadata["recordingID"] as? String == measurement.id.uuidString)
        let notice = try #require(metadata["notice"] as? String)
        #expect(notice.contains("has not been clinically validated"))
        #expect(notice.contains("cannot diagnose or rule out AFib"))
        #expect(metadata["camera"] != nil)
        await service.remove(files)
        #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }
}
