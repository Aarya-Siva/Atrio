import SwiftUI
import UIKit

@main
struct AtrioApp: App {
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(AppColors.background)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--ui-test-results") {
                ResearchUITestHarness()
                    .tint(AppColors.accent)
                    .preferredColorScheme(.light)
            } else {
                AppRootView()
                    .tint(AppColors.accent)
                    .preferredColorScheme(.light)
            }
            #else
            AppRootView()
                .tint(AppColors.accent)
                .preferredColorScheme(.light)
            #endif
        }
    }
}
