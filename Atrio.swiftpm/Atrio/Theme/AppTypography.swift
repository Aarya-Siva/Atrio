import SwiftUI

enum AppTypography {
    static let brand = Font.system(.title3, design: .default).weight(.bold)
    static let headline = Font.system(.largeTitle, design: .default).weight(.bold)
    static let body = Font.system(.subheadline, design: .default)
    static let button = Font.system(.subheadline, design: .default).weight(.semibold)
    static let section = Font.system(.caption2, design: .default).weight(.semibold)
    static let caption = Font.system(.caption2, design: .default)
}
