import SwiftUI

struct PrimaryButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            .font(AppTypography.button)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
