import XCTest
@testable import XRAiAssistant

/// The Swift port of the Nova64 kit's template picker must agree with the JS kit
/// (WebMaigeXr/nova64-kit), which generated `Nova64TemplateData.testVectors`.
final class Nova64TemplatesTests: XCTestCase {

    func testChooseMatchesTheJavaScriptKit() {
        XCTAssertFalse(Nova64TemplateData.testVectors.isEmpty)
        for v in Nova64TemplateData.testVectors {
            XCTAssertEqual(Nova64Templates.choose(message: v.message, currentTemplateId: v.current), v.expected,
                           "\"\(v.message)\" with current \(v.current ?? "none")")
        }
    }

    func testEveryTemplateConfigNamesItself() {
        XCTAssertEqual(Nova64Templates.all.count, 6)
        for t in Nova64Templates.all {
            XCTAssertEqual(Nova64Templates.templateId(of: t.config), t.id)
            XCTAssertTrue(t.config.contains(Nova64Templates.configMark), t.id)
            XCTAssertFalse(t.config.contains(Nova64Templates.engineMark), t.id)
        }
    }

    func testPromptBlockCarriesOnlyTheConfig() throws {
        let block = try XCTUnwrap(Nova64Templates.promptBlock(message: "make a dungeon crawler about monks", currentCode: nil))
        XCTAssertTrue(block.contains("GAME TEMPLATE MODE"))
        XCTAssertTrue(block.contains("// NOVA64 TEMPLATE: fp-dungeon-wizardry"))
        XCTAssertFalse(block.contains("{config}"))
        XCTAssertFalse(block.contains(Nova64Templates.engineMark))
        XCTAssertLessThan(block.count, 8000)
    }

    func testFollowUpEditsTheConfigInTheEditor() throws {
        let edited = try XCTUnwrap(Nova64Templates.template("lane-runner-grid")).config
            .replacingOccurrences(of: "title: 'SHARDGRID RUN'", with: "title: 'EMBER DASH'")
        // The editor holds the spliced cart: imports, CONFIG, then the engine.
        let cart = "const { sfx } = nova64.audio;\n\n" + edited + "\n" + Nova64Templates.engineMark + "\nfunction init() {}\n"
        let block = try XCTUnwrap(Nova64Templates.promptBlock(message: "make it faster", currentCode: cart))
        XCTAssertTrue(block.contains("title: 'EMBER DASH'"))
        XCTAssertFalse(block.contains("function init() {}"))
    }

    func testNonGameRequestsStayFreeForm() {
        XCTAssertNil(Nova64Templates.promptBlock(message: "a spinning cube with a glowing orb", currentCode: nil))
    }

    func testNova64LibraryAddsTheTemplatePromptOnlyForGames() {
        let manager = Library3DManager()
        manager.selectLibrary(Nova64Library())
        // The system prompt itself mentions GAME TEMPLATE MODE, so look for the CONFIG's marker line.
        XCTAssertTrue(manager.getLibrarySpecificPrompt(for: "an endless runner in a lava mine").contains("// NOVA64 TEMPLATE: lane-runner-corridor"))
        XCTAssertFalse(manager.getLibrarySpecificPrompt(for: "a glowing planet with rings").contains("// NOVA64 TEMPLATE:"))
    }

    func testNova64ExamplesIncludeTheGameTemplates() {
        let ids = Nova64Library().examples.map(\.id)
        for t in Nova64Templates.all { XCTAssertTrue(ids.contains("nova64-template-\(t.id)"), t.id) }
    }
}
