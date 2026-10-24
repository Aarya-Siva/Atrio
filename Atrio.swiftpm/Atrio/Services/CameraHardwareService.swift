import AVFoundation

enum CameraHardwareAvailability: Equatable {
    case available
    case simulator
    case rearCameraUnavailable
    case torchUnsupported
    case torchUnavailable

    var isAvailable: Bool { self == .available }

    var guidance: String? {
        switch self {
        case .available:
            nil
        case .simulator:
            "Real camera-based measurement requires a physical iPhone with a rear camera and flashlight."
        case .rearCameraUnavailable:
            "A connected rear wide-angle camera is required for fingertip pulse capture. This device cannot begin a measurement."
        case .torchUnsupported:
            "The rear camera does not support the flashlight needed to illuminate your fingertip. This device cannot perform the intended measurement."
        case .torchUnavailable:
            "The flashlight is currently unavailable. Let the device cool down or close other camera apps, then try again."
        }
    }
}

/// Inspects hardware only. Does not create a session or enable the torch.
@MainActor
struct CameraHardwareService {
    private let inspect: @MainActor () -> CameraHardwareAvailability

    init(inspect: @escaping @MainActor () -> CameraHardwareAvailability = CameraHardwareService.inspectDevice) {
        self.inspect = inspect
    }

    func checkAvailability() -> CameraHardwareAvailability { inspect() }

    static func inspectDevice() -> CameraHardwareAvailability {
        #if targetEnvironment(simulator)
        return .simulator
        #else
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              camera.isConnected else {
            return .rearCameraUnavailable
        }
        guard camera.hasTorch, camera.isTorchModeSupported(.on) else {
            return .torchUnsupported
        }
        guard camera.isTorchAvailable else { return .torchUnavailable }
        return .available
        #endif
    }
}
