import Foundation

/// Some models accept only part of the temperature / top_p range the Settings
/// sliders offer, and answer anything else with a 400. GLM and Kimi on
/// Together, for example, require top_p between 0.95 and 1. Values are pulled
/// into each model's range just before sending, so the user's settings stay as
/// they set them for every other model.
enum SamplingLimits {
    struct Range: Equatable {
        let temperature: ClosedRange<Double>
        let topP: ClosedRange<Double>
    }

    static let standard = Range(temperature: 0...2, topP: 0.01...1)

    static func range(for model: String) -> Range {
        let id = model.lowercased()
        if id.hasPrefix("zai-org/") || id.contains("glm-") || id.hasPrefix("moonshotai/") || id.contains("kimi-") {
            return Range(temperature: 0...1, topP: 0.95...1)
        }
        return standard
    }

    static func temperature(_ value: Double, model: String) -> Double {
        clamp(value, to: range(for: model).temperature)
    }

    static func topP(_ value: Double, model: String) -> Double {
        clamp(value, to: range(for: model).topP)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
