import Charts
import SwiftUI

struct HistoryView: View {
    let history: HistoryModel
    let onStartMeasurement: () -> Void
    @State private var pendingDeletion: MeasurementSummary?
    @State private var confirmDeletion = false
    @State private var operationError: String?

    var body: some View {
        List {
            if history.isLoading && !history.didLoad {
                ProgressView("Opening history…")
                    .listRowBackground(Color.clear)
            }
            if let message = history.errorMessage ?? operationError {
                Section {
                    Text(message).font(.callout)
                    Button("Try Again") {
                        operationError = nil
                        Task { await history.refresh() }
                    }
                }
                .listRowBackground(Color.clear)
            }
            if history.summaries.isEmpty && !history.isLoading {
                ContentUnavailableView {
                    Label("No saved recordings", systemImage: "waveform.path")
                } description: {
                    Text("Save a measurement after recording to review its waveform, quality, and report here.")
                } actions: {
                    Button("Start Measurement", action: onStartMeasurement)
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                if history.trend.count >= 2 {
                    Section {
                        HeartRateTrendView(summaries: history.trend)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(history.summaries) { summary in
                        NavigationLink(value: summary.id) {
                            HistoryRow(summary: summary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                pendingDeletion = summary
                                confirmDeletion = true
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("Saved measurements")
                } footer: {
                    Text("Stored on this device. Short recordings cannot confirm or exclude intermittent AFib. Only usable heart-rate estimates appear in the trend.")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .foregroundStyle(AppColors.heading)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(for: UUID.self) { id in
            SavedMeasurementView(id: id, history: history)
        }
        .task { if !history.didLoad { await history.refresh() } }
        .refreshable { await history.refresh() }
        .confirmationDialog("Delete this recording?", isPresented: $confirmDeletion, titleVisibility: .visible) {
            Button("Delete Recording", role: .destructive) {
                guard let id = pendingDeletion?.id else { return }
                Task {
                    do { try await history.delete(id) }
                    catch { operationError = "Recording could not be deleted. \(error.localizedDescription)" }
                    pendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("The saved waveform and report data will be removed from this iPhone. Previously exported copies will remain.")
        }
    }
}

private struct HistoryRow: View {
    let summary: MeasurementSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(summary.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.headline)
            HStack(alignment: .firstTextBaseline) {
                if let rate = summary.heartRate {
                    Text("\(rate, specifier: "%.0f") BPM").font(.subheadline.weight(.semibold))
                } else { Text("Heart rate unavailable").font(.subheadline) }
                Spacer()
                Text("\(summary.duration, specifier: "%.0f") s").font(.caption)
            }
            Text(summary.quality.title).font(.caption).foregroundStyle(AppColors.secondaryText)
            Text(summary.mode.title).font(.caption).foregroundStyle(AppColors.secondaryText)
            Text(summary.classification.title).font(.caption).foregroundStyle(AppColors.secondaryText)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct HeartRateTrendView: View {
    let summaries: [MeasurementSummary]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent heart-rate estimates").font(.headline)
            Chart(summaries) { summary in
                if let rate = summary.heartRate {
                    PointMark(x: .value("Date", summary.date), y: .value("BPM", rate))
                        .foregroundStyle(AppColors.accent).symbolSize(30)
                }
            }
            .chartYAxisLabel("BPM")
            .frame(height: 155)
            Text("Up to 30 usable measurements. These are separate recordings, not continuous monitoring.")
                .font(.caption).foregroundStyle(AppColors.secondaryText)
        }
        .padding(.vertical, 16)
    }
}

private struct SavedMeasurementView: View {
    let id: UUID
    let history: HistoryModel
    @State private var measurement: Measurement?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let measurement {
                MeasurementDetailView(measurement: measurement, history: history)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Recording unavailable", systemImage: "doc")
                } description: { Text(errorMessage) } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else { ProgressView("Opening recording…") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
        .task(id: id) { await load() }
    }

    private func load() async {
        errorMessage = nil
        do { measurement = try await history.load(id) }
        catch { errorMessage = error.localizedDescription }
    }
}
