import AVFoundation
import Foundation

// Compiled with the production permission, hardware, and view-model files.
// Fixtures replace OS reads and permission sheets; no real permissions are requested.
@MainActor
private final class CameraFixture {
    var status: AVAuthorizationStatus
    var hardware: CameraHardwareAvailability
    var grantAccess = true
    var requests = 0
    var requestHook: (() async -> Void)?

    init(status: AVAuthorizationStatus = .notDetermined, hardware: CameraHardwareAvailability = .available) {
        self.status = status
        self.hardware = hardware
    }

    func makeModel() -> PreparationViewModel {
        PreparationViewModel(
            permissionManager: CameraPermissionManager(readStatus: { self.status }, requestAccess: {
                self.requests += 1
                await self.requestHook?()
                self.status = self.grantAccess ? .authorized : .denied
                return self.grantAccess
            }),
            hardwareService: CameraHardwareService(inspect: { self.hardware })
        )
    }
}

@main
private struct Phase2StateChecks {
    @MainActor
    static func main() async {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            guard condition else { fatalError("FAIL: \(message)") }
            checks += 1
        }

        let fresh = CameraFixture()
        let freshModel = fresh.makeModel()
        freshModel.refresh()
        expect(fresh.requests == 0, "Launch and refresh must never prompt")
        expect(freshModel.statusTitle == "Permission Required" && freshModel.canStartMeasurement,
               "First-use status must allow an intentional request")
        let firstResult = await freshModel.startMeasurement()
        expect(firstResult && fresh.requests == 1, "A granted first request must continue exactly once")
        expect(freshModel.statusTitle == "Permission Granted", "Granted state must update immediately")
        let secondResult = await freshModel.startMeasurement()
        expect(secondResult && fresh.requests == 1, "Authorized access must not prompt again")

        let denied = CameraFixture()
        denied.grantAccess = false
        let deniedModel = denied.makeModel()
        let deniedResult = await deniedModel.startMeasurement()
        expect(!deniedResult && denied.requests == 1, "A denial must block navigation")
        expect(deniedModel.statusTitle == "Permission Denied" && deniedModel.canOpenSettings && !deniedModel.canStartMeasurement,
               "A denial must show Settings guidance and disable measurement")
        let deniedRetry = await deniedModel.startMeasurement()
        expect(!deniedRetry && denied.requests == 1, "Denied permission must not be requested repeatedly")
        denied.status = .authorized
        deniedModel.refresh()
        expect(deniedModel.canStartMeasurement && !deniedModel.canOpenSettings && deniedModel.statusTitle == "Permission Granted",
               "Returning from Settings must refresh authorization")
        let settingsResult = await deniedModel.startMeasurement()
        expect(settingsResult && denied.requests == 1, "Settings authorization must continue without a new prompt")

        let restricted = CameraFixture(status: .restricted)
        let restrictedModel = restricted.makeModel()
        let restrictedResult = await restrictedModel.startMeasurement()
        expect(!restrictedResult && restricted.requests == 0 && !restrictedModel.canOpenSettings,
               "Restricted devices must block requests and explain managed restrictions")

        for hardware in [CameraHardwareAvailability.simulator, .rearCameraUnavailable, .torchUnsupported, .torchUnavailable] {
            let missing = CameraFixture(hardware: hardware)
            let model = missing.makeModel()
            let result = await model.startMeasurement()
            expect(!result && missing.requests == 0 && !model.canStartMeasurement && model.statusTitle == "Camera Unavailable",
                   "Unsupported hardware must block access before prompting: \(hardware)")
            expect(model.guidance != nil, "Unavailable hardware must have guidance")
        }

        let interrupted = CameraFixture()
        interrupted.requestHook = { interrupted.hardware = .torchUnavailable }
        let interruptedModel = interrupted.makeModel()
        let interruptedResult = await interruptedModel.startMeasurement()
        expect(!interruptedResult && interrupted.status == .authorized && !interruptedModel.canStartMeasurement,
               "Hardware must be rechecked after the permission dialog")
        interrupted.hardware = .available
        interruptedModel.refresh()
        expect(interruptedModel.canStartMeasurement, "Foreground refresh must restore usable hardware")

        let revoked = CameraFixture(status: .authorized)
        let revokedModel = revoked.makeModel()
        revoked.status = .denied
        let revokedResult = await revokedModel.startMeasurement()
        expect(!revokedResult && revoked.requests == 0, "Start must refresh stale authorization before navigation")
        revoked.status = .authorized
        revoked.hardware = .rearCameraUnavailable
        revokedModel.refresh()
        expect(!revokedModel.canStartMeasurement, "Foreground refresh must detect unavailable camera hardware")

        let concurrent = CameraFixture()
        var resumeRequest: CheckedContinuation<Void, Never>?
        concurrent.requestHook = {
            await withCheckedContinuation { resumeRequest = $0 }
        }
        let concurrentModel = concurrent.makeModel()
        let pending = Task { await concurrentModel.startMeasurement() }
        while resumeRequest == nil { await Task.yield() }
        expect(concurrentModel.isCheckingAccess && !concurrentModel.canStartMeasurement,
               "The action must be disabled while authorization is pending")
        let duplicate = await concurrentModel.startMeasurement()
        expect(!duplicate && concurrent.requests == 1, "Rapid repeated taps must not create duplicate requests")
        resumeRequest?.resume()
        let pendingResult = await pending.value
        expect(pendingResult && !concurrentModel.isCheckingAccess, "Pending authorization must complete and restore the action")

        print("PASS: \(checks) Phase 2 state checks (injected OS and hardware states; not physical-device validation).")
    }
}
