import AVFoundation
import CoreMedia
import CoreImage
import Foundation
import UIKit

struct PPGCaptureConfiguration: Sendable {
    var mode = MeasurementMode.resting
    var positioningAid = PositioningAid.unaided
    var duration: Double { mode.duration }
    var torchLevel: Float = 0.25
    var roi = PPGROIConfiguration()
    var detection = FingerDetectionConfiguration()
    var uiUpdatesPerSecond = 8.0
}

/// Safety invariant: session/device, detector, accumulator, and observers belong to `queue`.
/// The cancellation gate is the only cross-queue mutable value and is protected by a lock.
/// CMSampleBuffer/CVPixelBuffer never leave the delegate queue; only Sendable values do.
final class PPGCameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "Atrio.PPGCamera", qos: .userInitiated)
    private let cancellationLock = NSLock()
    private var stopRequested = false
    private let configuration: PPGCaptureConfiguration
    private let deviceModel: String
    private let osVersion: String
    let events: AsyncStream<PPGCameraEvent>
    /// Display-only images from the existing capture output; never saved or exported.
    let previewFrames: AsyncStream<CGImage>
    private let previewContinuation: AsyncStream<CGImage>.Continuation
    private let previewContext = CIContext(options: [.cacheIntermediates: false])
    private var lastPreviewTime = 0.0
    private let continuation: AsyncStream<PPGCameraEvent>.Continuation
    private var session: AVCaptureSession?
    private var device: AVCaptureDevice?
    private var output: AVCaptureVideoDataOutput?
    private var observers: [NSObjectProtocol] = []
    private var watchdog: DispatchSourceTimer?
    private var extractor: PPGSignalExtractor
    private var detector: FingerDetectionService
    private var collector: PPGRecordingAccumulator
    private var metadata: PPGCameraMetadata?
    private var lastSample: PPGSample?
    private var lastCondition = OpticalCondition.unavailable
    private var startupHostTime = 0.0
    private var lastArrivalHostTime = 0.0
    private var lastCollectedHostTime = 0.0
    private var stableSince: Double?
    private var settingsLockedAt: Double?
    private var lastUIUpdate = 0.0
    private var finished = false
    #if DEBUG
    private var diagnosticFrames = 0
    #endif

    init(configuration: PPGCaptureConfiguration = .init(), deviceModel: String, osVersion: String) {
        self.configuration = configuration
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        extractor = PPGSignalExtractor(configuration: configuration.roi)
        detector = FingerDetectionService(configuration: configuration.detection)
        collector = PPGRecordingAccumulator(duration: configuration.duration, mode: configuration.mode)
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        (previewFrames, previewContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        super.init()
        continuation.onTermination = { [weak self] _ in self?.stop() }
    }

    func start() {
        queue.async { [self] in
            guard collector.state == .idle, !cancelled else { return }
            collector.initialize()
            startupHostTime = Self.now
            emit(message: "Initializing rear camera…", force: true)
            do {
                try configureAndStart()
                if cancelled { cancelOnQueue(); return }
                installWatchdog()
            } catch { fail(error.localizedDescription) }
        }
    }

    /// Marks the stop immediately even if startRunning/configuration is still executing.
    func stop() {
        cancellationLock.lock()
        stopRequested = true
        cancellationLock.unlock()
        queue.async { [self] in cancelOnQueue() }
    }

    private var cancelled: Bool {
        cancellationLock.lock()
        defer { cancellationLock.unlock() }
        return stopRequested
    }
    private static var now: Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    private func configureAndStart() throws {
        #if targetEnvironment(simulator)
        throw CaptureError("Real camera capture requires a physical iPhone.")
        #else
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw CaptureError("Camera permission is required. Return to Preparation to enable access.")
        }
        guard ProcessInfo.processInfo.thermalState != .serious,
              ProcessInfo.processInfo.thermalState != .critical else {
            throw CaptureError("The device is too warm for capture. Let it cool down before trying again.")
        }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              camera.isConnected, camera.hasTorch, camera.isTorchModeSupported(.on), camera.isTorchAvailable else {
            throw CaptureError("The rear wide-angle camera or flashlight is unavailable.")
        }
        device = camera
        let capture = AVCaptureSession()
        session = capture
        capture.beginConfiguration()
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            guard capture.canAddInput(input) else { throw CaptureError("The rear camera cannot be connected.") }
            capture.addInput(input)
            // Let the session negotiate a standard video format with its output.
            // Selecting an arbitrary activeFormat by dimensions alone also admits
            // device-specific formats that are unsuitable for this output pipeline.
            guard let preset = [AVCaptureSession.Preset.vga640x480, .medium, .high]
                .first(where: { capture.canSetSessionPreset($0) }) else {
                throw CaptureError("Camera format configuration is unavailable.")
            }
            capture.sessionPreset = preset
            guard camera.activeFormat.videoSupportedFrameRateRanges.contains(where: {
                $0.minFrameRate <= 30 && $0.maxFrameRate >= 30
            }) else { throw CaptureError("No supported 30 FPS rear-camera format was found.") }
            try camera.lockForConfiguration()
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
            if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { camera.whiteBalanceMode = .continuousAutoWhiteBalance }
            if camera.isFocusModeSupported(.locked) { camera.focusMode = .locked }
            camera.unlockForConfiguration()
            let video = AVCaptureVideoDataOutput()
            guard video.availableVideoPixelFormatTypes.contains(kCVPixelFormatType_32BGRA) else {
                throw CaptureError("BGRA camera output is unavailable on this device.")
            }
            video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            video.alwaysDiscardsLateVideoFrames = true
            video.setSampleBufferDelegate(self, queue: queue)
            guard capture.canAddOutput(video) else { throw CaptureError("Video-frame output is unavailable.") }
            capture.addOutput(video)
            output = video
            capture.commitConfiguration()
        } catch {
            capture.commitConfiguration()
            throw error
        }
        installObservers(capture)
        guard !cancelled else { return }
        capture.startRunning() // Deliberately off the main actor.
        guard capture.isRunning, !cancelled else { return }
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }
        guard !cancelled else { return }
        guard camera.isTorchAvailable else { throw CaptureError("The flashlight became unavailable.") }
        try camera.setTorchModeOn(level: min(AVCaptureDevice.maxAvailableTorchLevel, max(0.05, configuration.torchLevel)))
        let dimensions = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
        metadata = PPGCameraMetadata(deviceModel: deviceModel, osVersion: osVersion,
            cameraName: camera.localizedName, cameraID: camera.uniqueID,
            width: Int(dimensions.width), height: Int(dimensions.height), nominalFrameRate: 30,
            pixelFormat: "32BGRA", roiFraction: configuration.roi.fraction,
            samplingStride: configuration.roi.stride, torchLevel: camera.torchLevel,
            detectorProfile: configuration.detection,
            thermalState: String(describing: ProcessInfo.processInfo.thermalState),
            positioningAid: configuration.positioningAid)
        #endif
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !finished, !cancelled else { return }
        let now = Self.now
        lastArrivalHostTime = now
        emitPreview(sampleBuffer, at: now)
        guard let frame = extractor.extract(sampleBuffer), let clock = session?.synchronizationClock else {
            if collector.state == .recording { collector.extractionFailures += 1 }
            return
        }
        let hostPTS = CMSyncConvertTime(CMSampleBufferGetPresentationTimeStamp(sampleBuffer), from: clock,
                                       to: CMClockGetHostTimeClock()).seconds
        guard hostPTS.isFinite, hostPTS <= now + 0.1, now - hostPTS < 1 else {
            fail("Camera timestamps are stale or unavailable. Please try again.")
            return
        }
        if collector.state == .initializing { collector.ready() }
        lastCondition = detector.evaluate(frame)
        lastSample = PPGSample(timestamp: frame.timestamp, red: frame.red, green: frame.green,
                               blue: frame.blue, condition: lastCondition)
        #if DEBUG
        diagnosticFrames += 1
        if diagnosticFrames == 1 || diagnosticFrames % 90 == 0 {
            // Local development diagnostics only; never log images or pulse samples.
            let dimensions = device.map { CMVideoFormatDescriptionGetDimensions($0.activeFormat.formatDescription) }
            print("PPG capture: frames=\(diagnosticFrames) size=\(dimensions?.width ?? 0)x\(dimensions?.height ?? 0) allBlack=\(frame.blackFraction == 1) exposure=\(device?.exposureDuration.seconds ?? 0) iso=\(device?.iso ?? 0) torch=\(device?.torchLevel ?? 0)")
            fflush(stdout)
        }
        #endif
        if collector.state == .ready {
            if lastCondition == .suitable {
                if stableSince == nil { stableSince = now }
                let settled = device.map { !$0.isAdjustingExposure && !$0.isAdjustingWhiteBalance } ?? false
                if now - startupHostTime >= 1.5, now - (stableSince ?? now) >= 0.75,
                   settled || now - startupHostTime >= 8 {
                    do {
                        if settingsLockedAt == nil { try lockCameraSettings(); settingsLockedAt = now }
                        if now - (settingsLockedAt ?? now) >= 0.3, let metadata {
                            collector.start(at: hostPTS, date: Date().addingTimeInterval(hostPTS - now), camera: metadata)
                        }
                    } catch { fail(error.localizedDescription); return }
                }
            } else { stableSince = nil }
        }
        if collector.state == .recording {
            let previousCount = collector.samples.count
            collector.append(frame, condition: lastCondition, captureHostTime: hostPTS)
            if collector.samples.count > previousCount { lastCollectedHostTime = now }
            if collector.state == .failed { fail("The camera produced more frames than the bounded capture buffer supports."); return }
        }
        emit(message: lastCondition == .suitable && collector.state == .ready ? "Finger detected. Stabilizing camera settings…" : lastCondition.guidance)
        if collector.isDue(at: now) { finishRecording(at: now) }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if collector.state == .recording { collector.droppedFrames += 1 }
    }

    private func emitPreview(_ buffer: CMSampleBuffer, at time: Double) {
        // Keep rendering bounded and off the main thread. The signal extractor
        // still receives every original frame, unaffected by display resizing.
        guard time - lastPreviewTime >= 1 / configuration.uiUpdatesPerSecond,
              let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        lastPreviewTime = time
        let source = CIImage(cvPixelBuffer: pixels).oriented(.right)
        let scale = 320 / max(source.extent.width, source.extent.height)
        let thumbnail = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        if let image = previewContext.createCGImage(thumbnail, from: thumbnail.extent) {
            previewContinuation.yield(image)
        }
    }

    private func lockCameraSettings() throws {
        guard let camera = device else { throw CaptureError("The camera was disconnected.") }
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }
        if camera.isExposureModeSupported(.locked) { camera.exposureMode = .locked }
        if camera.isWhiteBalanceModeSupported(.locked) { camera.whiteBalanceMode = .locked }
        if camera.isFocusModeSupported(.locked) { camera.focusMode = .locked }
        metadata?.exposureLocked = camera.exposureMode == .locked
        metadata?.whiteBalanceLocked = camera.whiteBalanceMode == .locked
        metadata?.focusLocked = camera.focusMode == .locked
        metadata?.exposureSeconds = camera.exposureDuration.seconds
        metadata?.iso = camera.iso
        let gains = camera.deviceWhiteBalanceGains
        metadata?.whiteBalanceRedGain = gains.redGain
        metadata?.whiteBalanceGreenGain = gains.greenGain
        metadata?.whiteBalanceBlueGain = gains.blueGain
    }

    private func emit(message: String, force: Bool = false) {
        let now = Self.now
        guard force || now - lastUIUpdate >= 1 / max(1, configuration.uiUpdatesPerSecond) else { return }
        lastUIUpdate = now
        let cutoff = (collector.samples.last?.timestamp ?? 0) - 8
        let recent = collector.samples.filter { $0.timestamp >= cutoff }
        continuation.yield(.update(RecordingSnapshot(state: collector.state, condition: lastCondition,
            elapsed: collector.elapsed(at: now), duration: configuration.duration,
            frameCount: collector.samples.count, samples: recent,
            message: message, latestSample: lastSample)))
    }

    private func installWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        watchdog = timer
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            guard let self, !self.finished else { return }
            if self.cancelled { self.cancelOnQueue(); return }
            let now = Self.now
            let thermal = ProcessInfo.processInfo.thermalState
            if thermal == .serious || thermal == .critical {
                self.fail("The device became too warm. Capture stopped and the flashlight was turned off."); return
            }
            if let camera = self.device {
                if !camera.isConnected || !camera.isTorchAvailable || camera.torchMode != .on {
                    self.fail("The camera or flashlight became unavailable. Please try again."); return
                }
                let pressure = camera.systemPressureState.level
                if pressure == .serious || pressure == .critical || pressure == .shutdown {
                    self.fail("Camera system pressure is too high. Let the device cool down before retrying."); return
                }
            }
            if self.lastArrivalHostTime == 0 && now - self.startupHostTime > 10 {
                self.fail("No camera frames were received."); return
            }
            if self.lastArrivalHostTime > 0 && now - self.lastArrivalHostTime > 2 {
                self.fail("Camera frames stopped arriving. The unsaved recording was discarded."); return
            }
            if self.collector.state == .initializing && now - self.startupHostTime > 10 {
                self.fail("Camera frames could not be decoded or timestamped. Please try again."); return
            }
            if self.collector.state == .recording && self.lastCollectedHostTime > 0 && now - self.lastCollectedHostTime > 2 {
                self.fail("Usable camera timestamps stopped advancing. The unsaved recording was discarded."); return
            }
            if self.collector.isDue(at: now) { self.finishRecording(at: now); return }
            if self.collector.state == .ready && now - self.startupHostTime > 45 {
                self.fail("No suitable fingertip coverage was found. Adjust your placement and try again."); return
            }
            self.emit(message: self.lastCondition.guidance)
        }
        timer.resume()
    }

    private func installObservers(_ capture: AVCaptureSession) {
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification,
                     AVCaptureSession.didStopRunningNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: capture, queue: nil) { [weak self] notification in
                let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
                    ?? "Camera capture was interrupted. The unsaved recording was discarded."
                self?.queue.async { [weak self] in self?.fail(message) }
            })
        }
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.stop()
            })
        }
    }

    private func finishRecording(at time: Double) {
        guard !finished else { return }
        guard let result = collector.complete(at: time) else { fail("Insufficient camera frames were captured. Please try again."); return }
        finished = true
        let cleanupError = releaseResources()
        if let cleanupError { continuation.yield(.failed(cleanupError)) }
        else { continuation.yield(.completed(result)) }
        continuation.finish()
    }

    private func cancelOnQueue() {
        guard !finished else { return }
        finished = true
        collector.discard()
        _ = releaseResources()
        continuation.yield(.cancelled)
        continuation.finish()
    }

    private func fail(_ message: String) {
        guard !finished else { return }
        finished = true
        collector.discard(failed: true)
        let cleanupError = releaseResources()
        continuation.yield(.failed(cleanupError.map { message + " " + $0 } ?? message))
        continuation.finish()
    }

    @discardableResult private func releaseResources() -> String? {
        previewContinuation.finish()
        previewContext.clearCaches()
        watchdog?.setEventHandler {}
        watchdog?.cancel()
        watchdog = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        output?.setSampleBufferDelegate(nil, queue: nil)
        var torchError: Error?
        func disableTorch() {
            guard let device, device.hasTorch, device.isTorchModeSupported(.off) else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.torchMode = .off
                torchError = nil
            } catch { torchError = error }
        }
        disableTorch()
        if session?.isRunning == true { session?.stopRunning() }
        if torchError != nil { disableTorch() }
        if let session {
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            for output in session.outputs { session.removeOutput(output) }
            session.commitConfiguration()
        }
        session = nil
        output = nil
        device = nil
        lastSample = nil
        return torchError == nil ? nil : "Flashlight cleanup could not be confirmed. Close the app and check the flashlight before retrying."
    }
}

private struct CaptureError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
