import AVFoundation
import Observation

/// Reads authorization without prompting. Only the explicit start action requests access.
@MainActor
@Observable
final class CameraPermissionManager {
    private(set) var authorizationStatus: AVAuthorizationStatus
    private let readStatus: () -> AVAuthorizationStatus
    private let requestAccess: () async -> Bool

    init(
        readStatus: @escaping () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .video)
        },
        requestAccess: @escaping () async -> Bool = {
            await AVCaptureDevice.requestAccess(for: .video)
        }
    ) {
        self.readStatus = readStatus
        self.requestAccess = requestAccess
        authorizationStatus = readStatus()
    }

    func refresh() {
        authorizationStatus = readStatus()
    }

    func requestPermissionIfNeeded() async -> Bool {
        refresh()
        switch authorizationStatus {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await requestAccess()
            authorizationStatus = granted ? .authorized : .denied
            return granted
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
