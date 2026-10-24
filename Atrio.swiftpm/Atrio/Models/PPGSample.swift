import Foundation

/// Unfiltered central-ROI intensity in 8-bit camera units, with the original media PTS.
struct PPGSample: Sendable, Codable, Identifiable {
    let timestamp: Double
    let red: Double
    let green: Double
    let blue: Double
    let condition: OpticalCondition
    var id: Double { timestamp }
}

enum OpticalCondition: String, Sendable, Codable {
    case unavailable, uncovered, tooDark, clipped, moving, suitable

    var guidance: String {
        switch self {
        case .unavailable: "Waiting for camera frames."
        case .uncovered: "Place finger over camera."
        case .tooDark: "Signal too dark."
        case .clipped: "Adjust finger placement or pressure."
        case .moving: "Keep your finger steady with gentle contact."
        case .suitable: "Finger detected. Optical coverage is preliminary, not proof of a physiological pulse."
        }
    }
}
