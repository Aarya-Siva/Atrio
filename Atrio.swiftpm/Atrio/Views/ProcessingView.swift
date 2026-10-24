import SwiftUI

struct ProcessingView: View {
    let recording: PPGRecording
    let history: HistoryModel
    let onMeasureAgain: () -> Void
    @State private var measurement: Measurement?
    @State private var errorMessage: String?
    @State private var processor = MeasurementProcessor()
    @State private var confirmDiscard = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let measurement {
                MeasurementDetailView(measurement: measurement, history: history, onMeasureAgain: onMeasureAgain)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Analysis unavailable", systemImage: "waveform.path")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { Task { await process() } }
                    Button("Measure Again", action: onMeasureAgain)
                }
            } else {
                VStack(spacing: 20) {
                    ProgressView()
                    Text("Checking your recording").font(.title3.weight(.semibold))
                    Text("Assessing signal quality and measuring pulse intervals.")
                        .font(.body).foregroundStyle(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle(measurement == nil ? "Processing" : "Heart Rhythm Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if history.contains(recording.id) { dismiss() }
                    else { confirmDiscard = true }
                } label: { Label("Back", systemImage: "chevron.left") }
            }
        }
        .confirmationDialog("Discard this unsaved recording?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Recording", role: .destructive) { dismiss() }
            Button("Keep Recording", role: .cancel) { }
        } message: { Text("Save the result to keep it in History before leaving this screen.") }
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(AppColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task(id: recording.id) { await process() }
    }

    private func process() async {
        guard measurement == nil else { return }
        errorMessage = nil
        do { measurement = try await processor.process(recording) }
        catch is CancellationError { }
        catch { errorMessage = "Your recording could not be analyzed. Please try again. \(error.localizedDescription)" }
    }
}
