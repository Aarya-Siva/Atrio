import CoreMedia
import CoreVideo
import Foundation

struct PPGROIConfiguration: Sendable, Codable {
    var fraction: Double = 0.5
    var stride: Int = 4
}

struct OpticalFrame: Sendable {
    let timestamp: Double
    let red: Double
    let green: Double
    let blue: Double
    let brightness: Double
    let spatialVariation: Double
    let redClippingFraction: Double
    let allChannelClippingFraction: Double
    let blackFraction: Double
}

/// No pixel buffer escapes this synchronous call. Camera output requests BGRA explicitly.
struct PPGSignalExtractor: Sendable {
    var configuration = PPGROIConfiguration()

    func extract(_ sampleBuffer: CMSampleBuffer) -> OpticalFrame? {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        return extract(buffer, timestamp: timestamp)
    }

    func extract(_ buffer: CVPixelBuffer, timestamp: Double) -> OpticalFrame? {
        guard timestamp.isFinite, !CVPixelBufferIsPlanar(buffer) else { return nil }
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard format == kCVPixelFormatType_32BGRA || format == kCVPixelFormatType_32ARGB,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0, rowBytes >= width * 4 else { return nil }
        let fraction = min(1, max(0.1, configuration.fraction))
        let roiWidth = max(1, Int(Double(width) * fraction))
        let roiHeight = max(1, Int(Double(height) * fraction))
        let startX = (width - roiWidth) / 2, startY = (height - roiHeight) / 2
        let step = max(1, configuration.stride)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var r = 0.0, g = 0.0, b = 0.0, luminance = 0.0, squares = 0.0
        var count = 0, clippedRed = 0, clippedAll = 0, black = 0
        for y in Swift.stride(from: startY, to: startY + roiHeight, by: step) {
            for x in Swift.stride(from: startX, to: startX + roiWidth, by: step) {
                let offset = y * rowBytes + x * 4
                let red = Double(bytes[offset + (format == kCVPixelFormatType_32BGRA ? 2 : 1)])
                let green = Double(bytes[offset + (format == kCVPixelFormatType_32BGRA ? 1 : 2)])
                let blue = Double(bytes[offset + (format == kCVPixelFormatType_32BGRA ? 0 : 3)])
                let light = (red + green + blue) / 3
                r += red; g += green; b += blue; luminance += light; squares += light * light
                // Digital rail checks, not a skin-color or universal fingertip RGB threshold.
                if red >= 254 { clippedRed += 1 }
                if min(red, green, blue) >= 254 { clippedAll += 1 }
                if max(red, green, blue) <= 2 { black += 1 }
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let n = Double(count), mean = luminance / n
        let variation = sqrt(max(0, squares / n - mean * mean)) / max(mean, 1)
        return OpticalFrame(timestamp: timestamp, red: r / n, green: g / n, blue: b / n,
                            brightness: mean / 255, spatialVariation: variation,
                            redClippingFraction: Double(clippedRed) / n,
                            allChannelClippingFraction: Double(clippedAll) / n,
                            blackFraction: Double(black) / n)
    }
}
