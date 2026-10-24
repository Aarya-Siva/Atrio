import SwiftUI

struct RecordingView: View {
    let onCompleted: (PPGRecording) -> Void
    let onCancelled: () -> Void
    @State private var viewModel: RecordingViewModel
    @State private var confirmDiscard = false
    @Environment(\.scenePhase) private var scenePhase

    init(isDevelopmentPreview: Bool = false, mode: MeasurementMode = .resting, positioningAid: PositioningAid = .unaided,
         onCompleted: @escaping (PPGRecording) -> Void,
         onCancelled: @escaping () -> Void) {
        self.onCompleted = onCompleted
        self.onCancelled = onCancelled
        _viewModel = State(initialValue: RecordingViewModel(isDevelopmentPreview: isDevelopmentPreview, mode: mode, positioningAid: positioningAid))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                SignalStatusIndicator(title: viewModel.statusTitle, state: viewModel.snapshot.state)
                if viewModel.isDevelopmentPreview {
                    Text("DEVELOPMENT UI PREVIEW · NO CAMERA OR RECORDING")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                RecordingTimerView(remaining: viewModel.snapshot.remaining, progress: viewModel.snapshot.progress,
                                   hasStarted: viewModel.snapshot.state == .recording || viewModel.snapshot.state == .completed,
                                   duration: Int(viewModel.snapshot.duration))
                    .padding(.vertical, 8)
                LivePPGChart(samples: viewModel.snapshot.samples, isRecording: viewModel.snapshot.state == .recording)

                if let sample = viewModel.snapshot.latestSample {
                    Text("Camera RGB intensity (0–255): R \(sample.red, specifier: "%.1f") · G \(sample.green, specifier: "%.1f") · B \(sample.blue, specifier: "%.1f")")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle").accessibilityHidden(true)
                    Text(viewModel.errorMessage ?? viewModel.snapshot.message)
                        .font(AppTypography.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(AppColors.heading)
                .padding(16)
                .background(AppColors.softBlue.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionHeading(title: "SESSION PROGRESS")
                        Spacer()
                        Text("\(Int(viewModel.snapshot.progress * 100))%")
                            .font(AppTypography.caption)
                    }
                    ProgressView(value: viewModel.snapshot.progress)
                    Text("\(viewModel.snapshot.elapsed, specifier: "%.1f") / \(Int(viewModel.snapshot.duration)) seconds · \(viewModel.snapshot.frameCount) frames")
                        .font(AppTypography.caption)
                }
                .foregroundStyle(AppColors.secondaryText)

                Button(action: requestCancellation) {
                    Text(viewModel.snapshot.state == .failed ? "Return to Preparation" : "Stop Recording")
                        .font(AppTypography.button)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .padding(16)
                        .foregroundStyle(AppColors.accent)
                        .background(AppColors.softBlue, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stopRecordingButton")

                Text("Stopping discards the unsaved session. Optical coverage checks are preliminary and do not establish a valid physiological pulse.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .clipped()
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(AppColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: requestCancellation) { Label("Back", systemImage: "chevron.left") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: requestCancellation) { Image(systemName: "xmark") }
                    .accessibilityLabel("Cancel recording")
            }
        }
        .confirmationDialog("Discard this recording?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Stop and Discard", role: .destructive) { cancelAndReturn() }
            Button("Keep Recording", role: .cancel) {}
        } message: { Text("The collected RGB samples have not been saved.") }
        .task { await viewModel.run() }
        .onDisappear { viewModel.releaseCamera() }
        .onChange(of: viewModel.snapshot.state) { _, state in
            if state == .completed, let recording = viewModel.completedRecording {
                confirmDiscard = false
                onCompleted(recording)
            } else if state == .cancelled { onCancelled() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { viewModel.cancel() }
        }
    }

    private func requestCancellation() {
        if viewModel.hasCollectedData { confirmDiscard = true }
        else { cancelAndReturn() }
    }

    private func cancelAndReturn() {
        viewModel.cancel()
        // State observation performs the single navigation callback.
    }
}


