import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class RecordingViewModel {
    private(set) var snapshot = RecordingSnapshot()
    private(set) var completedRecording: PPGRecording?
    private(set) var errorMessage: String?
    private(set) var cameraPreview: CGImage?
    private let service: PPGCameraService?
    private var started = false
    let isDevelopmentPreview: Bool

    init(isDevelopmentPreview: Bool = false, mode: MeasurementMode = .resting, positioningAid: PositioningAid = .unaided) {
        #if DEBUG && targetEnvironment(simulator)
        self.isDevelopmentPreview = isDevelopmentPreview
        #else
        self.isDevelopmentPreview = false
        #endif
        if self.isDevelopmentPreview {
            service = nil
            snapshot.message = "Development UI preview. Camera, flashlight, and countdown are inactive."
        } else {
            var info = utsname()
            uname(&info)
            let identifier = withUnsafeBytes(of: &info.machine) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            service = PPGCameraService(configuration: PPGCaptureConfiguration(mode: mode, positioningAid: positioningAid),
                                       deviceModel: identifier, osVersion: UIDevice.current.systemVersion)
        }
        snapshot.duration = mode.duration
    }

    var hasCollectedData: Bool { snapshot.frameCount > 0 && snapshot.state == .recording }
    var statusTitle: String {
        switch snapshot.state {
        case .idle: "Signal unavailable"
        case .initializing: "Initializing"
        case .ready: snapshot.condition == .suitable ? "Finger detected" : "Adjust finger"
        case .recording: snapshot.condition == .suitable ? "Recording" : "Adjust finger"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        case .failed: "Signal unavailable"
        }
    }

    func run() async {
        guard !started else { return }
        started = true
        guard let service else { return }
        let previewTask = Task { [weak self] in
            for await image in service.previewFrames {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                if self.snapshot.state != .cancelled && self.snapshot.state != .failed {
                    self.cameraPreview = image
                }
            }
        }
        defer {
            previewTask.cancel()
            cameraPreview = nil
            service.stop()
        }
        service.start()
        for await event in service.events {
            guard !Task.isCancelled else { break }
            switch event {
            case .update(let value): snapshot = value
            case .completed(let recording):
                completedRecording = recording
                snapshot.state = .completed
                snapshot.elapsed = recording.duration
                snapshot.frameCount = recording.frameCount
            case .failed(let message):
                errorMessage = message
                snapshot = RecordingSnapshot(state: .failed, duration: snapshot.duration, message: message)
            case .cancelled:
                snapshot = RecordingSnapshot(state: .cancelled, duration: snapshot.duration, message: "Unsaved recording discarded.")
            }
        }
    }

    func cancel() {
        service?.stop()
        cameraPreview = nil
        completedRecording = nil
        snapshot = RecordingSnapshot(state: .cancelled, duration: snapshot.duration, message: "Unsaved recording discarded.")
    }

    func releaseCamera() {
        cameraPreview = nil
        service?.stop()
    }

    deinit { service?.stop() }
}
