import SwiftUI

struct RecordingTimerView: View {
    let remaining: Int
    let progress: Double
    let hasStarted: Bool
    var duration: Int = 30
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize = 52.0

    var body: some View {
        ZStack {
            Circle().stroke(AppColors.softBlue, lineWidth: 6)
            Circle().trim(from: 0, to: max(0, 1 - progress))
                .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text("\(remaining)")
                    .font(.system(size: countdownSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.accent)
                    .minimumScaleFactor(0.6)
                Text(hasStarted ? "SECONDS REMAINING" : "NOT STARTED")
                    .font(AppTypography.section)
                    .foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(18)
        }
        .frame(width: 184, height: 184)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasStarted ? "\(remaining) seconds remaining" : "\(duration)-second recording has not started")
    }
}
