import Testing
import Foundation
@testable import cw

/// Verify that the decoder can recover the expected text from one of the
/// bundled sample recordings.
@Test func testDecodeSample() throws {
    let decoder = CWDecoder()
    let url = Bundle.module.url(forResource: "sample_12_600_10_CQ_CQ_CQ_DE_W2ASM_K",
                                withExtension: "wav",
                                subdirectory: "samples")!
    let text = try decoder.decodeWAVFile(atPath: url.path)
    #expect(text == "CQ CQ CQ DE W2ASM K")
}

