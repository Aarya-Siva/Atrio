import Foundation

/// Exploratory normalized limits, adjustable per camera/experiment and stored in metadata.
/// They are not validated device-independent medical or physiological thresholds.
struct FingerDetectionConfiguration: Sendable, Codable {
    var maximumRedClippingFraction = 0.8
    var maximumAllChannelClippingFraction = 0.05
    var maximumBlackFraction = 0.8
    var minimumMeanBrightness = 0.025
    var minimumNormalizedColorMargin = 0.06
    var maximumSpatialVariation = 0.4
    var minimumRelativeMotionFloor = 0.025
    var motionNoiseMultiplier = 5.0
    var windowSize = 30
}

struct FingerDetectionService: Sendable {
    var configuration = FingerDetectionConfiguration()
    private var previousRed: Double?
    private var stableDifferences: [Double] = []

    init(configuration: FingerDetectionConfiguration = .init()) { self.configuration = configuration }

    mutating func evaluate(_ frame: OpticalFrame) -> OpticalCondition {
        let colorSum = max(frame.red + frame.green + frame.blue, 1)
        let margin = (frame.red - max(frame.green, frame.blue)) / colorSum
        let difference = previousRed.map { abs(frame.red - $0) / max($0, 1) } ?? 0
        previousRed = frame.red
        let sorted = stableDifferences.sorted()
        let noise = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let motionLimit = max(configuration.minimumRelativeMotionFloor,
                              noise * configuration.motionNoiseMultiplier)
        if frame.blackFraction > configuration.maximumBlackFraction || frame.brightness < configuration.minimumMeanBrightness { return .tooDark }
        if frame.redClippingFraction > configuration.maximumRedClippingFraction ||
            frame.allChannelClippingFraction > configuration.maximumAllChannelClippingFraction { return .clipped }
        // Channel relationships and spatial homogeneity, not an absolute red byte cutoff.
        guard margin > configuration.minimumNormalizedColorMargin,
              frame.spatialVariation < configuration.maximumSpatialVariation else { return .uncovered }
        guard difference <= motionLimit else { return .moving }
        stableDifferences.append(difference)
        if stableDifferences.count > max(3, configuration.windowSize) { stableDifferences.removeFirst() }
        return .suitable
    }
}
