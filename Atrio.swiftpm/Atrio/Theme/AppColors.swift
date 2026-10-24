import SwiftUI

enum AppColors {
    static let background = asset("AppBackground")
    static let accent = asset("AccentColor")
    static let heading = asset("HeadingColor")
    static let secondaryText = asset("SecondaryText")
    static let softBlue = asset("SoftBlue")
    static let border = asset("BorderColor")
    static let iconBackground = asset("IconBackground")

    private static func asset(_ name: String) -> Color {
        #if SWIFT_PACKAGE
        Color(name, bundle: .module)
        #else
        Color(name)
        #endif
    }
}
