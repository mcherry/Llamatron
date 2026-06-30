import XCTest
import AVFoundation
@testable import Llamatron

final class AudioExportTests: XCTestCase {

    /// Empty/invalid audio data fails cleanly rather than producing a bogus file.
    /// (The full encode path — Apple synth and Kokoro WAV → AAC `.m4a` — is verified at
    /// runtime; AAC encoding behaves differently in the headless test host.)
    func testEmptyWavThrows() {
        XCTAssertThrowsError(try AudioExport.writeM4A(wav: Data(), to:
            FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).m4a")))
    }
}
