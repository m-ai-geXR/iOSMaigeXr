import Foundation
import JavaScriptCore

/// The shared Nova64 cart kit (WebMaigeXr/nova64-kit, bundled as nova64-kit.js),
/// run in JavaScriptCore so the chat can check a reply the moment it arrives and
/// ask the model for a repair. The playground page runs the same kit again when
/// the cart is injected.
final class Nova64KitRunner {
    static let shared = Nova64KitRunner()

    struct Result {
        let code: String
        let problems: [String]
    }

    private let context: JSContext?
    private let kit: JSValue?

    init(source: String? = nil) {
        let js = source ?? Bundle.main.url(forResource: "nova64-kit", withExtension: "js")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        guard let js, let context = JSContext() else {
            self.context = nil
            self.kit = nil
            print("⚠️ Nova64 kit not available; replies are not checked for repair")
            return
        }
        context.exceptionHandler = { _, exception in
            print("⚠️ Nova64 kit error: \(exception?.toString() ?? "unknown")")
        }
        context.evaluateScript(js)
        self.context = context
        let kit = context.objectForKeyedSubscript("Nova64Kit")
        self.kit = (kit?.isUndefined ?? true) ? nil : kit
    }

    var isAvailable: Bool { kit != nil }

    /// Bounded number of repair attempts per user message.
    var maxRepairs: Int { Int(kit?.objectForKeyedSubscript("MAX_REPAIRS")?.toInt32() ?? 2) }

    func prepare(_ code: String) -> Result? {
        guard let value = kit?.invokeMethod("prepare", withArguments: [code]), value.isObject else { return nil }
        let prepared = value.objectForKeyedSubscript("code")?.toString() ?? code
        let problems = value.objectForKeyedSubscript("problems")?.toArray()?.compactMap { $0 as? String } ?? []
        return Result(code: prepared, problems: problems)
    }

    func repairPrompt(code: String, problems: [String]) -> String? {
        kit?.invokeMethod("repairPrompt", withArguments: [code, problems])?.toString()
    }
}
