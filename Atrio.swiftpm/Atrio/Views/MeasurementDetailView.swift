import Charts
import SwiftUI

struct MeasurementDetailView: View {
    let measurement: Measurement
    let history: HistoryModel
    var onMeasureAgain: (() -> Void)? = nil
    @State private var exportFormat: ExportFormat?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showCaptureDetails = false
    @State private var confirmNewRecording = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 28) {
                RhythmResultHeader(output: measurement.model, quality: measurement.analysis.quality,
                                   date: measurement.recording.startDate)
                if measurement.analysis.quality != .usable {
                    SignalQualitySection(analysis: measurement.analysis)
                }
                if let contributions = measurement.model.featureContributions {
                    ModelExplanationView(contributions: contributions, windows: measurement.model.evaluatedWindows ?? 0)
                }
                Divider()
                AnalysisWaveformSection(points: measurement.analysis.waveform, peaks: measurement.analysis.peaks,
                                        duration: measurement.recording.duration)
                MeasurementMetrics(heartRate: measurement.analysis.estimatedHeartRate, quality: measurement.analysis.quality)
                ResearchDisclaimerView()
                NavigationLink {
                    HeartHealthView()
                } label: {
                    Label("Learn about AFib and find care", systemImage: "book")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .tint(AppColors.accent)
                MeasurementActionsView(isSaved: history.contains(measurement.id), isSaving: isSaving,
                                       save: { Task { await save() } },
                                       export: { exportFormat = $0 }, measureAgain: measureAgainAction)
                if let saveError {
                    Text(saveError).font(.callout).foregroundStyle(AppColors.heading)
                        .accessibilityIdentifier("saveError")
                }
                if measurement.recording.mode == .repeatMeasurement {
                    RepeatComparisonView(current: measurement.summary, previous: previousSummary)
                }
                Divider()
                if measurement.analysis.quality == .usable {
                    SignalQualitySection(analysis: measurement.analysis)
                }
                PulseTimingSection(intervals: measurement.analysis.intervals, features: measurement.analysis.features)
                DisclosureGroup("Capture details", isExpanded: $showCaptureDetails) {
                    CaptureDetailsView(recording: measurement.recording, version: measurement.analysis.algorithmVersion)
                        .padding(.top, 12)
                }
                .font(.subheadline.weight(.semibold))
                .tint(AppColors.accent)
                Divider()
                Text("Saved recordings stay on this device and are excluded from cloud backup. Export a copy before deleting the app.")
                    .font(.caption).foregroundStyle(AppColors.secondaryText)
            }
            .padding(24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(AppColors.background.ignoresSafeArea())
        .foregroundStyle(AppColors.heading)
        .navigationTitle("Heart Rhythm Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportFormat) { format in
            ExportView(measurement: measurement, format: format)
        }
        .confirmationDialog("Start another recording?", isPresented: $confirmNewRecording, titleVisibility: .visible) {
            Button("Discard and Measure Again", role: .destructive) { onMeasureAgain?() }
            Button("Keep This Recording", role: .cancel) { }
        } message: {
            Text("This recording has not been saved. Save it first if you want to keep it in History.")
        }
    }

    private func requestNewRecording() {
        if history.contains(measurement.id) { onMeasureAgain?() }
        else { confirmNewRecording = true }
    }

    private var measureAgainAction: (() -> Void)? {
        guard onMeasureAgain != nil else { return nil }
        return { requestNewRecording() }
    }

    private var previousSummary: MeasurementSummary? {
        history.summaries.first {
            $0.id != measurement.id && $0.date < measurement.recording.startDate && $0.mode != .rhythmStability
        }
    }

    private func save() async {
        guard !isSaving, !history.contains(measurement.id) else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do { try await history.save(measurement) }
        catch { saveError = "Recording was not saved. \(error.localizedDescription)" }
    }
}

private struct RepeatComparisonView: View {
    let current: MeasurementSummary
    let previous: MeasurementSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compared with your previous recording").font(.headline)
            if let previous, let earlier = previous.heartRate, let latest = current.heartRate {
                Text(previous.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption).foregroundStyle(AppColors.secondaryText)
                LabeledContent("Previous estimate", value: "\(earlier.formatted(.number.precision(.fractionLength(0)))) BPM")
                LabeledContent("This estimate", value: "\(latest.formatted(.number.precision(.fractionLength(0)))) BPM")
                Text("A difference between recordings can reflect breathing, activity, placement, or signal quality. It is not a measure of disease progression.")
                    .font(.caption).foregroundStyle(AppColors.secondaryText)
            } else {
                Text("Two saved or current recordings with usable estimates are needed for comparison. Complete and save a resting recording first.")
                    .font(.callout).foregroundStyle(AppColors.secondaryText)
            }
        }
        .font(.subheadline)
    }
}

private struct RhythmResultHeader: View {
    let output: ResearchModelOutput
    let quality: SignalQuality
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                .font(.caption).foregroundStyle(AppColors.secondaryText)
            Text("Rhythm analysis").font(.subheadline)
            Text(output.classification == .inconclusive && quality != .usable
                 ? "Inconclusive · Check signal" : output.classification.title)
                .font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text(output.explanation).font(.callout).foregroundStyle(AppColors.secondaryText)
            if let version = output.modelVersion {
                Text("Model \(version)").font(.caption).foregroundStyle(AppColors.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ModelExplanationView: View {
    let contributions: [String: Double]
    let windows: Int
    private let labels = ["mean_interval_ms": "Mean pulse interval", "sdnn_ms": "Interval spread",
                          "rmssd_ms": "Successive interval variation", "pnn50": "Intervals changing by >50 ms",
                          "interval_cv": "Relative interval variability"]

    var body: some View {
        DisclosureGroup("Why this model output?") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Exact interventional SHAP values, averaged across \(windows) usable windows. Positive values push this model toward its AFib class; negative values push away.")
                    .font(.caption)
                Chart(RhythmWindowExtractor.featureNames, id: \.self) { name in
                    BarMark(x: .value("Contribution in log-odds", contributions[name] ?? 0),
                            y: .value("Feature", labels[name] ?? name))
                        .foregroundStyle(AppColors.accent)
                }
                .frame(height: 190)
                .chartXAxisLabel("Contribution in model log-odds")
                Text("Compared with a fixed background of 32 training windows. These values explain the trained model, not a medical cause. The model has not been validated against ECG on iPhone recordings.")
                    .font(.caption)
            }
            .foregroundStyle(AppColors.secondaryText)
            .padding(.top, 12)
        }
        .font(.subheadline.weight(.semibold))
        .tint(AppColors.accent)
    }
}

struct ResearchDisclaimerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(ResearchNotice.title, systemImage: "info.circle").font(.subheadline.weight(.semibold))
            Text(ResearchNotice.detail).font(.caption)
        }
        .foregroundStyle(AppColors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MeasurementMetrics: View {
    let heartRate: Double?
    let quality: SignalQuality

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 32) {
                HeartRateMetric(value: heartRate)
                Spacer(minLength: 0)
                QualityMetric(quality: quality)
            }
            VStack(alignment: .leading, spacing: 20) {
                HeartRateMetric(value: heartRate)
                QualityMetric(quality: quality)
            }
        }
    }
}

private struct HeartRateMetric: View {
    let value: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Estimated heart rate").font(.caption).foregroundStyle(AppColors.secondaryText)
            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value, format: .number.precision(.fractionLength(0))).font(.largeTitle.weight(.semibold))
                    Text("BPM").font(.caption)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Estimated heart rate, \(Int(value.rounded())) beats per minute")
            } else { Text("Not estimated").font(.title3.weight(.semibold)) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct QualityMetric: View {
    let quality: SignalQuality
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Signal quality").font(.caption).foregroundStyle(AppColors.secondaryText)
            Text(quality.title).font(.subheadline.weight(.semibold))
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AnalysisWaveformSection: View {
    let points: [PulsePoint]
    let peaks: [PulsePoint]
    let duration: Double
    @State private var showPeaks = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pulse waveform").font(.headline).accessibilityAddTraits(.isHeader)
            if points.isEmpty {
                Text("A usable pulse waveform could not be extracted. Try again with warm hands and steady, gentle contact.")
                    .font(.callout).foregroundStyle(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Time (s)", point.time), y: .value("Normalized intensity", point.value),
                                 series: .value("Segment", point.segment))
                            .foregroundStyle(AppColors.accent).lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    if showPeaks {
                        ForEach(peaks) { peak in
                            PointMark(x: .value("Time (s)", peak.time), y: .value("Normalized intensity", peak.value))
                                .foregroundStyle(AppColors.heading).symbolSize(15)
                        }
                    }
                }
                .chartXScale(domain: 0...max(1, duration))
                .chartXAxisLabel("Seconds")
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 180)
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Filtered optical pulse waveform with \(peaks.count) detected peaks. Gaps are excluded sections.")
                Toggle("Mark detected pulses", isOn: $showPeaks).font(.subheadline)
            }
            Text("Filtered camera signal, not an ECG. Missing sections were excluded from analysis.")
                .font(.caption).foregroundStyle(AppColors.secondaryText)
        }
    }
}

private struct SignalQualitySection: View {
    let analysis: PulseAnalysis
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recording quality").font(.headline).accessibilityAddTraits(.isHeader)
            Text("\(analysis.usableDuration, specifier: "%.1f") seconds usable · \(analysis.coverage * 100, specifier: "%.0f")% coverage")
                .font(.subheadline)
            ForEach(analysis.reasons, id: \.self) { reason in
                Text(reason).font(.callout).foregroundStyle(AppColors.secondaryText)
            }
            if analysis.quality != .usable {
                Text("Try again with warm hands, your arm supported, and light, steady contact over the rear camera and flashlight. Keep Mac screen sharing off during capture.")
                    .font(.callout).foregroundStyle(AppColors.secondaryText)
            }
        }
    }
}

private struct PulseTimingSection: View {
    let intervals: [PulseInterval]
    let features: RhythmFeatures?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Between pulses").font(.headline).accessibilityAddTraits(.isHeader)
            if intervals.isEmpty {
                Text("No reliable pulse intervals were retained.").font(.callout)
            } else {
                Chart(intervals) { interval in
                    PointMark(x: .value("Time (s)", interval.time), y: .value("Interval (ms)", interval.milliseconds))
                        .foregroundStyle(AppColors.accent).symbolSize(24)
                }
                .chartYAxisLabel("Milliseconds")
                .chartXAxisLabel("Seconds")
                .frame(height: 150)
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
            }
            if let features {
                LabeledContent("Mean interval", value: "\(features.meanIntervalMS.formatted(.number.precision(.fractionLength(0)))) ms")
                LabeledContent("Interval variation (SDNN)", value: "\(features.sdnnMS.formatted(.number.precision(.fractionLength(1)))) ms")
                LabeledContent("Successive variation (RMSSD)", value: "\(features.rmssdMS.formatted(.number.precision(.fractionLength(1)))) ms")
            }
            Text("Spacing shows how pulse timing varied in this recording. Movement and other rhythms can also change these intervals; variation alone does not identify AFib. These pulse-timing features are not clinical HRV measurements.")
                .font(.caption).foregroundStyle(AppColors.secondaryText)
        }
        .font(.subheadline)
    }
}

private struct CaptureDetailsView: View {
    let recording: PPGRecording
    let version: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Duration", value: "\(recording.duration.formatted()) s")
            LabeledContent("Camera frames", value: recording.frameCount.formatted())
            LabeledContent("Observed frame rate", value: "\(recording.averageFrameRate.formatted(.number.precision(.fractionLength(1)))) FPS")
            LabeledContent("Dropped frames", value: recording.quality.droppedFrames.formatted())
            LabeledContent("Device", value: recording.camera.deviceModel)
            LabeledContent("Positioning", value: recording.camera.positioningAid?.title ?? "Not recorded")
            LabeledContent("Processing", value: version)
            Text("The raw export includes original timestamps, all three color channels, capture settings, quality checks, and model metadata.")
                .font(.caption).foregroundStyle(AppColors.secondaryText)
        }
        .font(.subheadline)
    }
}

private struct MeasurementActionsView: View {
    let isSaved: Bool
    let isSaving: Bool
    let save: () -> Void
    let export: (ExportFormat) -> Void
    let measureAgain: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            if isSaved {
                Label("Saved on this iPhone", systemImage: "checkmark").font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                PrimaryButton(title: isSaving ? "Saving…" : "Save Measurement", action: save)
                    .disabled(isSaving).accessibilityIdentifier("saveMeasurementButton")
            }
            Button { export(.pdf) } label: {
                Label("Export PDF Report", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("exportPDFButton")
            Button { export(.rawData) } label: {
                Label("Export Raw Data", systemImage: "doc.text").frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("exportCSVButton")
            if let measureAgain {
                Button("Measure Again", action: measureAgain).frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.plain)
        .foregroundStyle(AppColors.accent)
    }
}
