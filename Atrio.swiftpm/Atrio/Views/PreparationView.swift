import SwiftUI

struct PreparationView: View {
    let onStartRecording: (MeasurementMode, PositioningAid) -> Void
    var onPreviewRecording: (() -> Void)? = nil
    @State private var viewModel = PreparationViewModel()
    @State private var mode = MeasurementMode.resting
    @State private var positioningAid = PositioningAid.unaided
    @State private var measurementTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(spacing: 12) {
                    Text("Before You Begin")
                        .font(.title.weight(.bold))
                        .foregroundStyle(AppColors.heading)
                        .accessibilityAddTraits(.isHeader)
                    Text("Proper finger placement helps improve pulse signal quality.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineSpacing(3)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

                Picker("Attachment", selection: $positioningAid) {
                    ForEach(PositioningAid.allCases) { aid in Text(aid.title).tag(aid) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("attachmentPicker")

                FingerPlacementIllustration(withAttachment: positioningAid == .prototype)
                    .frame(maxWidth: 300)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Recording mode", selection: $mode) {
                        ForEach(MeasurementMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.subheadline.weight(.semibold))
                    Text(mode.detail).font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                }

                VStack(alignment: .leading, spacing: 28) {
                    if positioningAid == .prototype {
                        PreparationStepRow(number: 1, symbol: "paperclip", title: "Fit the Attachment",
                            detail: "Slide the clamp onto the phone’s left edge beside the cameras. Face the open finger cradle outward, keeping the camera and flashlight clear.")
                        PreparationStepRow(number: 2, symbol: "hand.point.up.left", title: "Place Your Finger",
                            detail: "Rest your index finger inside the curved cradle, with the fingertip gently covering the lower-right camera and flashlight. Keep the fit comfortable.")
                    } else {
                        PreparationStepRow(number: 1, symbol: "camera", title: "Cover the Lens",
                            detail: "Place the tip of your index finger gently over the rear camera and flashlight.")
                    }
                    PreparationStepRow(number: positioningAid == .prototype ? 3 : 2, symbol: "bolt", title: "Enable Flashlight",
                        detail: "The app will activate the flashlight during recording to illuminate the fingertip.")
                    PreparationStepRow(number: positioningAid == .prototype ? 4 : 3, symbol: "hand.raised", title: "Stay Still",
                        detail: "Keep your finger steady and maintain consistent, gentle contact throughout the \(Int(mode.duration))-second recording.")
                }

                VStack(alignment: .leading, spacing: 12) {
                    CameraPermissionStatusView(title: viewModel.statusTitle, symbol: viewModel.statusSymbol)
                    if let guidance = viewModel.guidance {
                        Text(guidance)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if viewModel.canOpenSettings {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .font(AppTypography.body.weight(.semibold))
                        .padding(.vertical, 12)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("openCameraSettingsButton")
                    }
                    if viewModel.hardwareAvailability == .torchUnavailable {
                        Button("Check Again") { viewModel.refresh() }
                            .font(AppTypography.body.weight(.semibold))
                            .padding(.vertical, 12)
                            .frame(minHeight: 44)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(AppColors.accent)
                        .accessibilityHidden(true)
                    Text("Ensure your hands are warm and you are resting comfortably. Cold fingers, excessive pressure, or movement can affect signal quality.")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppColors.border, lineWidth: 1))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .clipped()
        .background(AppColors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomActions }
        .navigationTitle("Preparation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(AppColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { viewModel.refresh() }
        .onDisappear {
            measurementTask?.cancel()
            measurementTask = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.refresh() }
        }
    }

    private var bottomActions: some View {
        VStack(spacing: 12) {
            PrimaryButton(title: viewModel.isCheckingAccess ? "Checking Camera…" : "Start Measurement") {
                measurementTask = Task {
                    if await viewModel.startMeasurement(), !Task.isCancelled {
                        onStartRecording(mode, positioningAid)
                    }
                }
            }
            .disabled(!viewModel.canStartMeasurement)
            .accessibilityIdentifier("preparationStartMeasurementButton")

            #if DEBUG && targetEnvironment(simulator)
            if let onPreviewRecording {
                VStack(spacing: 4) {
                    Text("DEVELOPMENT ONLY · NO CAMERA")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
                    Button("Preview Recording Screen", action: onPreviewRecording)
                        .font(AppTypography.body.weight(.semibold))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("previewRecordingButton")
                }
            }
            #endif
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(AppColors.background)
        .overlay(alignment: .top) { Divider() }
    }
}
