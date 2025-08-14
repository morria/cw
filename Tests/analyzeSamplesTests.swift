#if canImport(AVFoundation)
import Testing
import Foundation
@testable import cw

@Test func testAnalyzeSamples() throws {
    let samplesDirectory = "./Tests/samples"
    let files = try FileManager.default.contentsOfDirectory(atPath: samplesDirectory)
    guard let file = files.first else {
        #expect(Bool(false), "No sample files found")
        return
    }
    let streamer = try FileStreamer(filePath: "\(samplesDirectory)/\(file)")
    try streamer.startStreaming { _ in }
    streamer.stopStreaming()
}
#endif
