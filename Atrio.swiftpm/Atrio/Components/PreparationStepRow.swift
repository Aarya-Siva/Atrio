import SwiftUI

struct PreparationStepRow: View {
    let number: Int
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(AppColors.accent)
                .frame(width: 40, height: 40)
                .background(AppColors.iconBackground, in: RoundedRectangle(cornerRadius: 9))
                .overlay(alignment: .topLeading) {
                    Text("\(number)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(AppColors.heading, in: Circle())
                        .offset(x: -5, y: -5)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.body.weight(.semibold))
                    .foregroundStyle(AppColors.heading)
                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number). \(title). \(detail)")
    }
}
