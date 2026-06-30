import XCTest
@testable import Llamatron

final class TTSTests: XCTestCase {

    func testIsConfiguredRequiresEnabledAndURL() {
        XCTAssertFalse(TTS.isConfigured(enabled: false, serverURL: "http://localhost:8880"))
        XCTAssertFalse(TTS.isConfigured(enabled: true, serverURL: ""))
        XCTAssertFalse(TTS.isConfigured(enabled: true, serverURL: "   "))
        XCTAssertTrue(TTS.isConfigured(enabled: true, serverURL: "http://localhost:8880"))
    }

    func testDecodeVoicesObjectShape() {
        let json = #"{"voices":[{"id":"af_heart","name":"Heart"},{"id":"am_adam"}]}"#
        let voices = KokoroTTSProvider.decodeVoices(Data(json.utf8))
        XCTAssertEqual(voices.map(\.id), ["af_heart", "am_adam"])
        XCTAssertEqual(voices.first?.name, "Heart")
        XCTAssertEqual(voices.last?.name, "am_adam")   // name falls back to the id
    }

    func testDecodeVoicesStringShape() {
        let voices = KokoroTTSProvider.decodeVoices(Data(#"{"voices":["af_heart","af_bella"]}"#.utf8))
        XCTAssertEqual(voices.map(\.id), ["af_heart", "af_bella"])
        XCTAssertEqual(voices.first?.name, "af_heart")
    }

    func testDecodeVoicesTolerantOfGarbage() {
        XCTAssertTrue(KokoroTTSProvider.decodeVoices(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(KokoroTTSProvider.decodeVoices(Data("{}".utf8)).isEmpty)
    }

    func testTTSEngineRoundTrip() {
        XCTAssertEqual(TTSEngine(rawValue: "apple"), .apple)
        XCTAssertEqual(TTSEngine(rawValue: "server"), .server)
        XCTAssertEqual(TTSEngine.allCases.count, 2)
    }
}
