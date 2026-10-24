import SwiftUI

struct SignalStatusIndicator: View {
    let title: String
    let state: RecordingState

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(AppColors.accent).frame(width: 7, height: 7)
            Text(title).font(AppTypography.caption.weight(.semibold))
            Spacer(minLength: 0)
            if state == .recording {
                Image(systemName: "camera.fill").accessibilityHidden(true)
            }
        }
        .foregroundStyle(AppColors.accent)
        .padding(12)
        .background(AppColors.softBlue.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppColors.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
