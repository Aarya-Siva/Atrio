import AVFoundation
import Observation

@MainActor
@Observable
final class PreparationViewModel {
    let permissionManager: CameraPermissionManager
    private let hardwareService: CameraHardwareService
    private(set) var hardwareAvailability: CameraHardwareAvailability
    private(set) var isCheckingAccess = false

    init(
        permissionManager: CameraPermissionManager = CameraPermissionManager(),
        hardwareService: CameraHardwareService = CameraHardwareService()
    ) {
        self.permissionManager = permissionManager
        self.hardwareService = hardwareService
        hardwareAvailability = hardwareService.checkAvailability()
    }

    var statusTitle: String {
        guard hardwareAvailability.isAvailable else { return "Camera Unavailable" }
        switch permissionManager.authorizationStatus {
        case .authorized: return "Permission Granted"
        case .notDetermined: return "Permission Required"
        case .denied, .restricted: return "Permission Denied"
        @unknown default: return "Permission Required"
        }
    }

    var statusSymbol: String {
        if !hardwareAvailability.isAvailable { return "camera.badge.ellipsis" }
        return permissionManager.authorizationStatus == .authorized ? "checkmark.circle" : "camera"
    }

    var guidance: String? {
        if let message = hardwareAvailability.guidance { return message }
        switch permissionManager.authorizationStatus {
        case .denied:
            return "Camera access is needed to capture fingertip pulse signals. Enable Camera for Atrio in Settings, then return here."
        case .restricted:
            return "Camera access is restricted on this device. Check Screen Time or contact the device administrator."
        case .notDetermined:
            return "Camera access will be requested when you tap Start Measurement."
        case .authorized:
            return nil
        @unknown default:
            return "Camera access is unavailable. Check your device settings."
        }
    }

    var canOpenSettings: Bool {
        hardwareAvailability.isAvailable && permissionManager.authorizationStatus == .denied
    }

    var canStartMeasurement: Bool {
        guard hardwareAvailability.isAvailable, !isCheckingAccess else { return false }
        switch permissionManager.authorizationStatus {
        case .authorized, .notDetermined: return true
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }

    /// Also called on scene activation, including returns from Settings.
    func refresh() {
        permissionManager.refresh()
        hardwareAvailability = hardwareService.checkAvailability()
    }

    func startMeasurement() async -> Bool {
        guard !isCheckingAccess else { return false }
        refresh()
        guard canStartMeasurement else { return false }
        isCheckingAccess = true
        defer { isCheckingAccess = false }
        guard await permissionManager.requestPermissionIfNeeded() else { return false }
        // Hardware can become unavailable while the permission sheet is open.
        hardwareAvailability = hardwareService.checkAvailability()
        return hardwareAvailability.isAvailable
    }
}
