import SwiftUI

struct RecordingTimerView: View {
    let remaining: Int
    let progress: Double
    let hasStarted: Bool
    var duration: Int = 30
    var cameraPreview: CGImage? = nil
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize = 52.0

    var body: some View {
        ZStack {
            if let cameraPreview {
                Image(decorative: cameraPreview, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 170, height: 170)
                    .overlay(Color.black.opacity(0.58))
                    .clipShape(Circle())
                    .accessibilityHidden(true)
            }
            Circle().stroke(AppColors.softBlue, lineWidth: 6)
            Circle().trim(from: 0, to: max(0, 1 - progress))
                .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text("\(remaining)")
                    .font(.system(size: countdownSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(cameraPreview == nil ? AppColors.accent : .white)
                    .minimumScaleFactor(0.6)
                Text(hasStarted ? "SECONDS REMAINING" : "NOT STARTED")
                    .font(AppTypography.section)
                    .foregroundStyle(cameraPreview == nil ? AppColors.secondaryText : .white)
                    .multilineTextAlignment(.center)
            }
            .padding(18)
        }
        .frame(width: 184, height: 184)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasStarted ? "\(remaining) seconds remaining" : "\(duration)-second recording has not started")
    }
}
