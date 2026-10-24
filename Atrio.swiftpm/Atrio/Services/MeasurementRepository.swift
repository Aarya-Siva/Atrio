import Foundation

struct HistoryLoad: Sendable {
    let summaries: [MeasurementSummary]
    let unreadableCount: Int
}

/// Serializes file operations off the main actor. Each recording is an atomic file, so
/// a failed write cannot replace the user's entire history. Files use iOS Data Protection.
actor MeasurementRepository {
    private let directory: URL
    private let maximumRecords = 500

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("Measurements", isDirectory: true)
    }

    func loadHistory() throws -> HistoryLoad {
        try prepareDirectory()
        let urls = try recordURLs()
        var summaries: [MeasurementSummary] = []
        var unreadable = 0
        for url in urls {
            try Task.checkCancellation()
            do { summaries.append(try read(url).summary) }
            catch { unreadable += 1 }
        }
        return HistoryLoad(summaries: summaries.sorted { $0.date > $1.date }, unreadableCount: unreadable)
    }

    func load(id: UUID) throws -> Measurement { try read(fileURL(id)) }

    func save(_ measurement: Measurement) throws {
        try prepareDirectory()
        let url = fileURL(measurement.id)
        let recordCount = try recordURLs().count
        guard FileManager.default.fileExists(atPath: url.path) || recordCount < maximumRecords else {
            throw StorageError("History is full (500 recordings). Export and delete older recordings before saving another.")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(measurement)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        var protectedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
    }

    func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: fileURL(id))
    }

    private func prepareDirectory() throws {
        #if os(iOS)
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        #else
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #endif
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func recordURLs() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey],
                                                   options: .skipsHiddenFiles).filter { $0.pathExtension == "json" }
    }

    private func fileURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }

    private func read(_ url: URL) throws -> Measurement {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size < 10_000_000 else { throw StorageError("This recording has an unsupported file size.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let measurement = try decoder.decode(Measurement.self, from: Data(contentsOf: url))
        guard measurement.schemaVersion == 1, measurement.id.uuidString == url.deletingPathExtension().lastPathComponent,
              measurement.recording.samples.count <= 7200 else { throw StorageError("This recording uses an unsupported format.") }
        return measurement
    }
}

struct StorageError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
