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

/// GLM on Together always thinks before answering and, left to its default,
/// can think for minutes. It takes `reasoning_effort` low / medium / high / max.
/// Its levels run much heavier than Claude's or GPT's, so the app's levels map
/// one step lighter: the default High becomes GLM medium.
enum TogetherReasoning {
    static func effort(for model: String, appEffort: AIEffort) -> String? {
        guard model.lowercased().hasPrefix("zai-org/glm-") else { return nil }
        switch appEffort {
        case .low, .medium: return "low"
        case .high: return "medium"
        case .xhigh: return "high"
        case .max: return "max"
        }
    }
}
