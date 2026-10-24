import SwiftUI

/// Each tab owns its navigation stack, so switching tabs preserves its position.
struct AppRootView: View {
    @State private var navigation = AppNavigationModel()
    @State private var recording: PPGRecording?
    @State private var history = HistoryModel()
    @State private var measurementMode = MeasurementMode.resting
    @State private var positioningAid = PositioningAid.unaided

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            NavigationStack(path: $navigation.homePath) {
                HomeView {
                    navigation.homePath.append(.preparation)
                }
                .navigationDestination(for: HomeDestination.self) { destination in
                    switch destination {
                    case .preparation:
                        PreparationView(onStartRecording: { mode, aid in
                            measurementMode = mode
                            positioningAid = aid
                            navigation.homePath.append(.recording)
                        }, onPreviewRecording: {
                            #if DEBUG && targetEnvironment(simulator)
                            navigation.homePath.append(.recordingPreview)
                            #endif
                        })
                    case .recording:
                        RecordingView(mode: measurementMode, positioningAid: positioningAid, onCompleted: finishRecording, onCancelled: cancelRecording)
                    #if DEBUG && targetEnvironment(simulator)
                    case .recordingPreview:
                        RecordingView(isDevelopmentPreview: true, mode: measurementMode, positioningAid: positioningAid, onCompleted: finishRecording, onCancelled: cancelRecording)
                    #endif
                    case .processing:
                        if let recording {
                            ProcessingView(recording: recording, history: history) {
                                navigation.homePath = [.preparation]
                            }
                        }
                    }
                }
            }
            .toolbar(navigation.homePath.isEmpty ? .visible : .hidden, for: .tabBar)
            .tabItem { Label("Home", systemImage: "house") }
            .tag(AppTab.home)

            NavigationStack {
                HistoryView(history: history) {
                    navigation.homePath = [.preparation]
                    navigation.selectedTab = .home
                }
            }
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            .tag(AppTab.history)

            NavigationStack {
                HeartHealthView()
            }
            .tabItem { Label("Learn", systemImage: "book") }
            .tag(AppTab.learn)
        }
        .toolbarBackground(AppColors.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task { await history.refresh() }
        .onChange(of: navigation.homePath) { _, path in
            if !path.contains(.processing) { recording = nil }
        }
    }

    private func finishRecording(_ result: PPGRecording) {
        guard !navigation.homePath.isEmpty else { return }
        recording = result
        navigation.homePath[navigation.homePath.count - 1] = .processing
    }

    private func cancelRecording() {
        guard let destination = navigation.homePath.last else { return }
        switch destination {
        case .recording:
            navigation.homePath.removeLast()
        #if DEBUG && targetEnvironment(simulator)
        case .recordingPreview:
            navigation.homePath.removeLast()
        #endif
        default: break
        }
    }
}

#Preview("Atrio") {
    AppRootView()
        .tint(AppColors.accent)
        .preferredColorScheme(.light)
}
