import UIKit

@MainActor
enum ResearchPDFRenderer {
    static func render(_ measurement: Measurement) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "Atrio recording report",
                               kCGPDFContextCreator as String: "Atrio"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792), format: format)
        return renderer.pdfData { context in
            let writer = ReportWriter(context: context, isSynthetic: measurement.recording.source == .syntheticUITest)
            writer.beginPage()
            writer.heading("Recording summary")
            writer.text(measurement.recording.startDate.formatted(date: .complete, time: .shortened))
            writer.text("Recording ID: \(measurement.id.uuidString)")
            writer.text("Mode: \((measurement.recording.mode ?? .resting).title)")
            writer.text("Estimated heart rate: \(measurement.analysis.estimatedHeartRate.map { String(format: "%.0f BPM", $0) } ?? "Unavailable — insufficient signal")")
            writer.text("Signal quality: \(measurement.analysis.quality.title)")
            writer.text(String(format: "Collection: %.1f s · usable signal: %.1f s (%.0f%%)",
                               measurement.recording.duration, measurement.analysis.usableDuration, measurement.analysis.coverage * 100))
            writer.heading("Rhythm analysis")
            writer.text(measurement.model.classification.title, bold: true)
            writer.text(measurement.model.explanation)
            if let version = measurement.model.modelVersion { writer.text("Model version: \(version)") }
            if let score = measurement.model.afibScore { writer.text(String(format: "Model score: %.3f (not personal risk or diagnostic confidence)", score)) }
            if let source = measurement.model.sourceDomain { writer.text("Model training domain: \(source)") }
            if let contributions = measurement.model.featureContributions {
                writer.text("Exact interventional SHAP contributions in model log-odds, averaged over retained windows; explains model behavior, not disease.")
                for name in RhythmWindowExtractor.featureNames {
                    writer.text(String(format: "%@: %+.4f", name, contributions[name] ?? 0))
                }
            }
            writer.heading("Pulse waveform")
            writer.waveform(measurement.analysis.waveform, peaks: measurement.analysis.peaks)
            writer.text("Filtered, normalized optical signal; not an ECG. Markers show detected pulse peaks. Gaps are excluded sections. Raw RGB values are available separately as CSV.")
            writer.heading("Quality assessment")
            for reason in measurement.analysis.reasons { writer.text("• \(reason)") }
            writer.heading("Pulse timing")
            writer.text("\(measurement.analysis.intervals.count) retained pulse intervals. These are exploratory pulse-rate variability features, not ECG-derived clinical HRV.")
            if let f = measurement.analysis.features {
                writer.text(String(format: "Mean interval: %.1f ms · SDNN: %.1f ms · RMSSD: %.1f ms", f.meanIntervalMS, f.sdnnMS, f.rmssdMS))
                writer.text(String(format: "pNN50: %.1f%% · Interval coefficient of variation: %.3f", f.pnn50 * 100, f.intervalCV))
            } else { writer.text("Summary timing features withheld because the signal did not pass quality checks.") }
            writer.heading("Capture details")
            let recording = measurement.recording
            writer.text("Device: \(recording.camera.deviceModel) · iOS \(recording.camera.osVersion)")
            writer.text("Positioning: \(recording.camera.positioningAid?.title ?? "Not recorded")")
            writer.text("Camera: \(recording.camera.cameraName) · \(recording.camera.width) × \(recording.camera.height) · \(recording.camera.pixelFormat)")
            writer.text(String(format: "Frames: %d · observed FPS: %.2f · sample span: %.2f s", recording.frameCount, recording.averageFrameRate, recording.sampleDuration))
            writer.text(String(format: "Dropped frames: %d · maximum gap: %.3f s · rejected timestamps: %d", recording.quality.droppedFrames, recording.quality.maximumFrameGap, recording.quality.rejectedTimestamps))
            writer.text("Extraction failures: \(recording.quality.extractionFailures) · preliminary suitable frames: \(recording.quality.suitableFrames)")
            writer.text(String(format: "Torch level: %.2f · exposure: %.5f s · ISO: %.0f", recording.camera.torchLevel, recording.camera.exposureSeconds, recording.camera.iso))
            writer.text("Exposure locked: \(recording.camera.exposureLocked ? "yes" : "no") · white balance locked: \(recording.camera.whiteBalanceLocked ? "yes" : "no")")
            writer.text("Processing version: \(measurement.analysis.algorithmVersion). Red-channel processing; resampled to 30 Hz; forward/backward Butterworth filters at 0.5–4 Hz. Quality thresholds are exploratory and require device/reference validation.")
            writer.heading("Interpretation and limitations")
            writer.text(ResearchNotice.detail)
            writer.text("Motion, pressure, camera adjustments, and other rhythms can affect pulse timing. A short recording cannot exclude an intermittent rhythm disturbance. This report is not a medical certificate or a treatment recommendation.")
            writer.text("ECG confirmation reference: NHLBI, Atrial Fibrillation — Diagnosis. https://www.nhlbi.nih.gov/health/atrial-fibrillation/diagnosis")
            writer.text("Generated \(Date().formatted(date: .abbreviated, time: .shortened)). Shared copies are controlled by their recipient and are not removed when you delete the recording in Atrio.")
        }
    }
}

@MainActor
private final class ReportWriter {
    private let context: UIGraphicsPDFRendererContext
    private var y: CGFloat = 0
    private var page = 0
    private let isSynthetic: Bool
    private let ink = UIColor(red: 24 / 255, green: 52 / 255, blue: 74 / 255, alpha: 1)
    private let accent = UIColor(red: 40 / 255, green: 108 / 255, blue: 154 / 255, alpha: 1)

    init(context: UIGraphicsPDFRendererContext, isSynthetic: Bool) {
        self.context = context
        self.isSynthetic = isSynthetic
    }

    func beginPage() {
        context.beginPage()
        page += 1
        y = 38
        draw("Atrio / Recording report", rect: CGRect(x: 42, y: y, width: 528, height: 25), size: 18, bold: true)
        y += 32
        draw(ResearchNotice.title.uppercased(), rect: CGRect(x: 42, y: y, width: 528, height: 20), size: 11, bold: true)
        y += 36
        if isSynthetic {
            draw("SYNTHETIC UI TEST — NOT A MEASUREMENT", rect: CGRect(x: 42, y: y, width: 528, height: 18), size: 11, bold: true)
            y += 24
        }
        draw("NOT A DIAGNOSIS                                               Page \(page)",
             rect: CGRect(x: 42, y: 753, width: 528, height: 18), size: 9)
    }

    func heading(_ value: String) {
        ensureSpace(65)
        y += 12
        draw(value, rect: CGRect(x: 42, y: y, width: 528, height: 23), size: 14, bold: true)
        y += 29
    }

    func text(_ value: String, bold: Bool = false) {
        let font = UIFont.systemFont(ofSize: 11, weight: bold ? .semibold : .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]
        let height = ceil((value as NSString).boundingRect(with: CGSize(width: 528, height: CGFloat.greatestFiniteMagnitude),
                                                          options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height)
        ensureSpace(height + 10)
        (value as NSString).draw(in: CGRect(x: 42, y: y, width: 528, height: height + 2), withAttributes: attributes)
        y += height + 10
    }

    func waveform(_ points: [PulsePoint], peaks: [PulsePoint]) {
        guard let first = points.first, let last = points.last, last.time > first.time else {
            text("No usable pulse waveform was extracted.")
            return
        }
        ensureSpace(156)
        let box = CGRect(x: 42, y: y + 5, width: 528, height: 115)
        let limit = max(1, points.map { abs($0.value) }.max() ?? 1)
        func position(_ point: PulsePoint) -> CGPoint {
            CGPoint(x: box.minX + (point.time - first.time) / (last.time - first.time) * box.width,
                    y: box.midY - point.value / limit * box.height * 0.45)
        }
        let line = UIBezierPath()
        var previous: Int?
        for point in points {
            if point.segment != previous { line.move(to: position(point)) }
            else { line.addLine(to: position(point)) }
            previous = point.segment
        }
        accent.setStroke()
        line.lineWidth = 1.3
        line.stroke()
        ink.setFill()
        for peak in peaks {
            let center = position(peak)
            UIBezierPath(ovalIn: CGRect(x: center.x - 1.7, y: center.y - 1.7, width: 3.4, height: 3.4)).fill()
        }
        draw(String(format: "%.1f s", first.time), rect: CGRect(x: 42, y: y + 126, width: 100, height: 18), size: 9)
        draw(String(format: "%.1f s", last.time), rect: CGRect(x: 520, y: y + 126, width: 50, height: 18), size: 9)
        y += 153
    }

    private func ensureSpace(_ height: CGFloat) { if y + height > 727 { beginPage() } }

    private func draw(_ value: String, rect: CGRect, size: CGFloat, bold: Bool = false) {
        (value as NSString).draw(in: rect, withAttributes: [
            .font: UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: ink
        ])
    }
}
