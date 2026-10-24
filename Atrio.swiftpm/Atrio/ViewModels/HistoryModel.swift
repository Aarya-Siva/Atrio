import Foundation
import Observation

@MainActor
@Observable
final class HistoryModel {
    private(set) var summaries: [MeasurementSummary] = []
    private(set) var trend: [MeasurementSummary] = []
    private(set) var isLoading = false
    private(set) var didLoad = false
    var errorMessage: String?
    private let repository: MeasurementRepository
    private var mutationRevision = 0

    init(repository: MeasurementRepository = MeasurementRepository()) { self.repository = repository }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        let revision = mutationRevision
        defer { isLoading = false }
        do {
            let result = try await repository.loadHistory()
            if revision == mutationRevision {
                summaries = result.summaries
                updateTrend()
            }
            didLoad = true
            errorMessage = result.unreadableCount > 0
                ? "\(result.unreadableCount) saved recording(s) could not be read. They have not been deleted."
                : nil
        } catch is CancellationError { }
        catch { errorMessage = "History could not be opened. Unlock your device and try again. \(error.localizedDescription)" }
    }

    func save(_ measurement: Measurement) async throws {
        try await repository.save(measurement)
        mutationRevision += 1
        summaries.removeAll { $0.id == measurement.id }
        summaries.append(measurement.summary)
        summaries.sort { $0.date > $1.date }
        updateTrend()
    }

    func load(_ id: UUID) async throws -> Measurement { try await repository.load(id: id) }

    func delete(_ id: UUID) async throws {
        try await repository.delete(id: id)
        mutationRevision += 1
        summaries.removeAll { $0.id == id }
        updateTrend()
    }

    func contains(_ id: UUID) -> Bool { summaries.contains { $0.id == id } }

    private func updateTrend() {
        trend = Array(summaries.filter { $0.heartRate != nil && $0.quality == .usable }.prefix(30).reversed())
    }
}
