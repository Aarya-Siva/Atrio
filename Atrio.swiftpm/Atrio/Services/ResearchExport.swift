import Foundation

enum ExportFormat: String, Identifiable {
    case pdf, rawData
    var id: String { rawValue }
    var title: String { self == .pdf ? "Research report" : "Recording data" }
}

enum RecordingCSV {
    /// Original camera PTS and intensities, independent of the user's decimal locale.
    static func samples(_ recording: PPGRecording) -> String {
        var text = "timestamp,red,green,blue,condition\n"
        for sample in recording.samples {
            text += "\(sample.timestamp),\(sample.red),\(sample.green),\(sample.blue),\(sample.condition.rawValue)\n"
        }
        return text
    }

    static func intervals(_ analysis: PulseAnalysis) -> String {
        "time_seconds,interval_ms,segment\n" + analysis.intervals.map {
            "\($0.time),\($0.milliseconds),\($0.segment)\n"
        }.joined()
    }
}

actor ResearchExport {
    func prepare(_ measurement: Measurement, pdf: Data? = nil) throws -> [URL] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AtrioExports", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Remove only exports owned by this app that are older than a day (e.g. after termination).
        let previous = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])
        for url in previous {
            if let date = try url.resourceValues(forKeys: [.creationDateKey]).creationDate,
               Date().timeIntervalSince(date) > 86400 { try? FileManager.default.removeItem(at: url) }
        }
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let suffix = String(measurement.id.uuidString.prefix(8))
            if let pdf {
                return [try write(pdf, name: "Atrio-\(suffix).pdf", folder: folder)]
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let metadata = ExportMetadata(recording: measurement.recording, analysis: measurement.analysis, model: measurement.model)
            return [
                try write(Data(RecordingCSV.samples(measurement.recording).utf8), name: "\(suffix)-samples.csv", folder: folder),
                try write(Data(RecordingCSV.intervals(measurement.analysis).utf8), name: "\(suffix)-intervals.csv", folder: folder),
                try write(try encoder.encode(metadata), name: "\(suffix)-metadata.json", folder: folder)
            ]
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    func remove(_ urls: [URL]) {
        guard let folder = urls.first?.deletingLastPathComponent(),
              folder.deletingLastPathComponent().lastPathComponent == "AtrioExports" else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ data: Data, name: String, folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        return url
    }
}

private struct ExportMetadata: Encodable {
    let schemaVersion = 1
    let notice = ResearchNotice.title + ". " + ResearchNotice.detail
    let recordingID: UUID
    let startDate: Date
    let duration: Double
    let sampleDuration: Double
    let averageFrameRate: Double
    let frameCount: Int
    let camera: PPGCameraMetadata
    let captureQuality: PPGQualityMetadata
    let mode: MeasurementMode
    let source: RecordingSource
    let analysis: PulseAnalysis
    let model: ResearchModelOutput

    init(recording: PPGRecording, analysis: PulseAnalysis, model: ResearchModelOutput) {
        recordingID = recording.id
        startDate = recording.startDate
        duration = recording.duration
        sampleDuration = recording.sampleDuration
        averageFrameRate = recording.averageFrameRate
        frameCount = recording.frameCount
        camera = recording.camera
        captureQuality = recording.quality
        mode = recording.mode ?? .resting
        source = recording.source ?? .camera
        self.analysis = analysis
        self.model = model
    }
}
