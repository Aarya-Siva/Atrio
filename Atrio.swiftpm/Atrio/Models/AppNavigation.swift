enum AppTab: Hashable {
    case home
    case history
    case learn
}

enum HomeDestination: Hashable {
    case preparation
    case recording
    case processing
    #if DEBUG && targetEnvironment(simulator)
    case recordingPreview
    #endif
}
