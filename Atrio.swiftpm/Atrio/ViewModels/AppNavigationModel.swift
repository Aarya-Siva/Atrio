import Observation

@MainActor
@Observable
final class AppNavigationModel {
    var selectedTab: AppTab = .home
    var homePath: [HomeDestination] = []
}
