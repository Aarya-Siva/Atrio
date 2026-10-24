import SwiftUI

/// Static optical pulse illustration. Never presented as a recording or result.
struct PPGWaveformView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "OPTICAL PULSE SIGNAL")

            ZStack {
                Canvas { context, size in
                    var grid = Path()
                    for row in 1...3 {
                        let y = size.height * CGFloat(row) / 4
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(grid, with: .color(AppColors.border), lineWidth: 1)
                }
                IllustrativePPGTrace()
                    .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .aspectRatio(2.8, contentMode: .fit)
            .accessibilityHidden(true)

            Text("Illustrative PPG · Not a live recording")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppColors.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustrative optical PPG pulse waveform. Not a live recording.")
    }
}

private struct IllustrativePPGTrace: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let samples = 600
        for index in 0...samples {
            let progress = Double(index) / Double(samples)
            let cycle = progress * 5.0
            let phase = cycle - floor(cycle)
            // Rounded systolic rise, dicrotic notch, and smaller diastolic wave.
            // These are design samples, not physiological measurements.
            let systolic = pow(phase / 0.075, 3) * exp(3 - phase / 0.075) / 27
            let diastolic = 0.14 * exp(-pow((phase - 0.52) / 0.075, 2))
            let notch = 0.055 * exp(-pow((phase - 0.43) / 0.035, 2))
            let amplitude = 0.94 + 0.035 * sin(cycle * 1.3)
            let signal = (systolic + diastolic - notch) * amplitude
            let point = CGPoint(
                x: rect.minX + rect.width * progress,
                y: rect.minY + rect.height * (0.86 - signal * 0.70)
            )
            if index == 0 { path.move(to: point) }
            else { path.addLine(to: point) }
        }
        return path
    }
}

#Preview {
    PPGWaveformView()
        .padding(24)
        .background(AppColors.background)
}
