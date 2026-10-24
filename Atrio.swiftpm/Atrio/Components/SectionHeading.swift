import SwiftUI

struct SectionHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTypography.section)
            .tracking(0.4)
            .foregroundStyle(AppColors.heading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}
