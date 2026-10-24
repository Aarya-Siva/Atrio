import SwiftUI

/// A vector placement guide, not a camera feed. Uses design-system colors only.
struct FingerPlacementIllustration: View {
    var withAttachment = false

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.09)
                        .fill(AppColors.iconBackground)
                        .overlay(RoundedRectangle(cornerRadius: size * 0.09).stroke(AppColors.border, lineWidth: 1.5))
                        .frame(width: size * 0.49, height: size * 0.94)
                    // Keep the complete placement guide aligned as the camera
                    // housing is scaled to the phone's upper-left corner.
                    ZStack {
                        RoundedRectangle(cornerRadius: size * 0.06)
                            .fill(AppColors.background)
                            .frame(width: size * 0.34, height: size * 0.36)
                            .offset(x: -size * 0.045, y: -size * 0.26)
                        // iPhone 13: diagonal lenses, with the flash above the
                        // lower-right wide-angle camera. There is no LiDAR sensor.
                        cameraLens(size: size)
                            .offset(x: -size * 0.12, y: -size * 0.34)
                        cameraLens(size: size)
                            .offset(x: size * 0.035, y: -size * 0.18)
                        Circle().fill(.white)
                            .overlay(Circle().stroke(AppColors.accent, lineWidth: 1))
                            .frame(width: size * 0.048, height: size * 0.048)
                            .offset(x: size * 0.035, y: -size * 0.34)
                        if withAttachment {
                            attachment(size: size)
                        }
                        // Translucency reveals the covered lens and flash beneath the fingertip.
                        Capsule()
                            .fill(AppColors.accent.opacity(0.20))
                            .overlay(Capsule().stroke(AppColors.accent, lineWidth: 2))
                            .frame(width: size * 0.18, height: size * 0.55)
                            .offset(x: size * 0.035, y: -size * 0.15)
                        Capsule()
                            .stroke(AppColors.accent.opacity(0.55), lineWidth: 1.5)
                            .frame(width: size * 0.11, height: size * 0.14)
                            .offset(x: size * 0.035, y: -size * 0.30)
                        Image(systemName: withAttachment ? "arrow.down" : "hand.point.up.left")
                            .font(.system(size: size * 0.10))
                            .foregroundStyle(AppColors.accent)
                            .offset(x: size * 0.32, y: -size * 0.33)
                    }
                    .scaleEffect(0.64)
                    .offset(x: -size * 0.071, y: -size * 0.154)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 190)
            .clipped()
            .accessibilityHidden(true)
            Text(withAttachment
                 ? "Clip onto the side. Rest your fingertip in the cradle."
                 : "Cover the lower-right camera and flashlight")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .background(AppColors.softBlue.opacity(0.45), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(AppColors.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(withAttachment
            ? "Attachment placement guide: the clamp fits onto the left edge of the phone beside the camera module. The curved cradle faces outward around the cameras. Rest your index finger in the cradle, gently covering the lower-right camera and the flash above it."
            : "Placement guide: two diagonal rear camera lenses and a separate flash at the upper right. Rest your fingertip over the lower-right wide-angle lens and the flash above it.")
    }

    private func attachment(size: CGFloat) -> some View {
        ZStack {
            // Side clamp and its adjustment screw, matching the supplied clip.
            RoundedRectangle(cornerRadius: size * 0.025)
                .fill(AppColors.heading)
                .frame(width: size * 0.20, height: size * 0.24)
                .overlay(alignment: .trailing) {
                    RoundedRectangle(cornerRadius: size * 0.012)
                        .fill(AppColors.background)
                        .frame(width: size * 0.12, height: size * 0.13)
                }
                .offset(x: -size * 0.28, y: -size * 0.22)
            RoundedRectangle(cornerRadius: size * 0.012)
                .fill(AppColors.secondaryText)
                .frame(width: size * 0.10, height: size * 0.045)
                .overlay(Image(systemName: "minus").font(.system(size: size * 0.06)).foregroundStyle(AppColors.background))
                .offset(x: -size * 0.28, y: -size * 0.075)
            // An open collar leaves the camera and LED visible beneath the finger.
            Ellipse().trim(from: 0.10, to: 0.90)
                .stroke(AppColors.heading, style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round))
                .frame(width: size * 0.41, height: size * 0.39)
                .offset(x: -size * 0.045, y: -size * 0.26)
            Ellipse().trim(from: 0.10, to: 0.90)
                .stroke(AppColors.secondaryText, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .frame(width: size * 0.41, height: size * 0.39)
                .offset(x: -size * 0.045, y: -size * 0.26)
        }
    }

    private func cameraLens(size: CGFloat) -> some View {
        Circle().fill(AppColors.heading)
            .overlay(Circle().stroke(AppColors.accent, lineWidth: 2))
            .overlay(Circle().stroke(AppColors.secondaryText.opacity(0.6), lineWidth: 1).padding(size * 0.02))
            .frame(width: size * 0.115, height: size * 0.115)
    }
}
