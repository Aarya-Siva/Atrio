import SwiftUI

struct CameraPermissionStatusView: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(AppColors.accent)
                .frame(width: 40, height: 40)
                .background(AppColors.iconBackground, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                SectionHeading(title: "CAMERA ACCESS")
                Text(title)
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundStyle(AppColors.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.softBlue.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cameraPermissionStatus")
    }
}
