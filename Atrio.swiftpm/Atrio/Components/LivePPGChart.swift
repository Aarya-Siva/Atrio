import Charts
import SwiftUI

struct LivePPGChart: View {
    let samples: [PPGSample]
    let isRecording: Bool

    private var points: [OpticalPlotPoint] { OpticalPlotPoint.make(from: samples) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("LIVE PPG STREAM", systemImage: "waveform.path")
                    .font(AppTypography.section)
                Spacer(minLength: 8)
                Text(isRecording ? "CAMERA DATA" : "WAITING")
                    .font(AppTypography.caption)
            }
            .foregroundStyle(AppColors.accent)

            if points.count >= 2 {
                Chart(points) { point in
                    LineMark(x: .value("Time", point.seconds), y: .value("Normalized red", point.intensity),
                             series: .value("Continuous segment", point.segment))
                        .foregroundStyle(AppColors.accent)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                }
                .chartXScale(domain: -8.0...0.0)
                .chartYScale(domain: -0.65...0.65)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: [-8.0, -4.0, 0.0]) { value in
                        AxisTick()
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) { Text("\(Int(seconds))s") }
                        }
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("Camera-derived normalized red optical intensity, most recent eight seconds. No pulse validation has been performed.")
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera")
                    Text("Waiting for usable camera frames")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(AppTypography.body)
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 180)
            }
            Text("Normalized red intensity · last 8 seconds")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(16)
        .background(AppColors.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppColors.border, lineWidth: 1))
    }
}
