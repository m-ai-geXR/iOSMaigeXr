import XCTest
@testable import XRAiAssistant

/// The picker should offer what the user's Together key can actually use.
final class TogetherModelCatalogTests: XCTestCase {

    private let sample = """
    [
      {"id":"zai-org/GLM-5.3-Flash","type":"chat","display_name":"GLM-5.3 Flash","organization":"Z.ai","context_length":1000000,"pricing":{"input":0.15,"output":0.6,"hourly":0}},
      {"id":"moonshotai/Kimi-K3","type":"chat","display_name":"Kimi K3","organization":"Moonshot","context_length":1000000,"pricing":{"input":3,"output":9,"hourly":0}},
      {"id":"Qwen/Qwen3.7-Max","type":"chat","display_name":"Qwen3.7 Max","organization":"Qwen","context_length":262144,"pricing":{"input":1.2,"output":4,"hourly":0}},
      {"id":"acme/New-Model","type":"chat","display_name":"New Model","organization":"Acme","context_length":131072,"pricing":{"input":0.5,"output":1,"hourly":0}},
      {"id":"acme/Dedicated-Only","type":"chat","display_name":"Dedicated","pricing":{"input":0,"output":0,"hourly":4.5}},
      {"id":"BAAI/bge-base-en-v1.5","type":"embedding","pricing":{"input":0.01,"output":0}}
    ]
    """

    func testParseKeepsOnlyOnDemandChatModels() {
        let ids = TogetherModelCatalog.parse(Data(sample.utf8)).map(\.id)
        XCTAssertEqual(Set(ids), ["zai-org/GLM-5.3-Flash", "moonshotai/Kimi-K3", "Qwen/Qwen3.7-Max", "acme/New-Model"])
    }

    func testMergeDropsUnavailableCuratedAndAddsTheRest() {
        let live = TogetherModelCatalog.parse(Data(sample.utf8))
        let merged = TogetherModelCatalog.merge(curated: TogetherAIProvider.curatedModels, live: live)
        let ids = merged.map(\.id)
        XCTAssertTrue(ids.contains("zai-org/GLM-5.3-Flash"))
        XCTAssertFalse(ids.contains("zai-org/GLM-5.3"), "curated but not available to this key")
        XCTAssertEqual(merged.first(where: { $0.id == "acme/New-Model" })?.provider, TogetherModelCatalog.moreGroup)
        XCTAssertEqual(merged.first(where: { $0.id == "Qwen/Qwen3.7-Max" })?.provider, "Together.ai", "curated keeps its group")
    }

    func testWithoutALiveListTheBuiltInListIsUsed() {
        XCTAssertEqual(TogetherModelCatalog.merge(curated: TogetherAIProvider.curatedModels, live: nil).map(\.id),
                       TogetherAIProvider.curatedModels.map(\.id))
    }
}
