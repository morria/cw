import Testing
import Foundation
@testable import cw

@Test func testAnalyzeSamples() throws {
    let fileManager = FileManager.default
    let samplesDirectory = "./Tests/samples"

    do {
        let files = try fileManager.contentsOfDirectory(atPath: samplesDirectory)
        for file in files {
            print("Found file: \(file)")
        }
    } catch {
        #expect(Bool(false), "Failed to list files in directory: \(error)")
    }
}