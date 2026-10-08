import XCTest
@testable import XRAiAssistant

/// React Three Fiber and Reactylon have no in-app playground; they always run
/// on CodeSandbox, and people are told so when they pick them.
@MainActor
final class CodeSandboxRequirementTests: XCTestCase {

    func testOnlyBuildFrameworksRequireCodeSandbox() {
        XCTAssertTrue(ChatViewModel.requiresCodeSandbox("reactThreeFiber"))
        XCTAssertTrue(ChatViewModel.requiresCodeSandbox("reactylon"))
        for id in ["babylonjs", "threejs", "aframe", "nova64"] {
            XCTAssertFalse(ChatViewModel.requiresCodeSandbox(id), id)
        }
    }

    func testPickingR3FExplainsCodeSandbox() {
        let viewModel = ChatViewModel()
        viewModel.selectLibrary(id: "babylonjs")
        viewModel.codeSandboxNotice = nil
        viewModel.selectLibrary(id: "reactThreeFiber")
        XCTAssertNotNil(viewModel.codeSandboxNotice)
        XCTAssertTrue(viewModel.codeSandboxNotice?.contains("CodeSandbox") == true)
    }
}
