import Testing
import Foundation
@testable import cw

@Test func testFrequencyDetection() throws {
    let samplesDirectory = "./Tests/samples"
    let files = try FileManager.default.contentsOfDirectory(atPath: samplesDirectory)
    for file in files.filter({ $0.contains("600") || $0.contains("300") || $0.contains("1000") }) {
        let path = "\(samplesDirectory)/\(file)"
        let samples = try readWavSamples(path: path)
        let decoder = CWDecoder()
        for s in samples { decoder.feed(sample: s) }
        _ = decoder.decodeBuffer()
        let expectedFreq = extractFrequency(from: file)
        #expect(decoder.estimatedFrequency != nil)
        if let freq = decoder.estimatedFrequency {
            #expect(abs(freq - expectedFreq) < 25)
        }
    }
}

@Test func testDecodingSample() throws {
    let path = "./Tests/samples/sample_12_600_10_CQ_CQ_CQ_DE_W2ASM_K.wav"
    let samples = try readWavSamples(path: path)
    let decoder = CWDecoder()
    for s in samples { decoder.feed(sample: s) }
    let decoded = decoder.decodeBuffer()
    #expect(decoded == "CQ CQ CQ DE W2ASM K")
}

private func extractFrequency(from file: String) -> Double {
    let parts = file.split(separator: "_")
    if parts.count > 2, let freq = Double(parts[2]) {
        return freq
    }
    return 0
}

private func readWavSamples(path: String) throws -> [Float] {
    struct WAVHeader {
        let sampleRate: UInt32
        let bitsPerSample: UInt16
        let dataOffset: Int
        let dataSize: Int
    }

    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    func readUInt32(_ offset: Int) -> UInt32 {
        return data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
    }
    func readUInt16(_ offset: Int) -> UInt16 {
        return data.subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: UInt16.self) }
    }

    // Parse minimal WAV header (PCM 16-bit little endian)
    let sampleRate = readUInt32(24)
    let bitsPerSample = readUInt16(34)
    let dataOffset = 44
    let dataSize = Int(readUInt32(40))
    let header = WAVHeader(sampleRate: sampleRate, bitsPerSample: bitsPerSample, dataOffset: dataOffset, dataSize: dataSize)

    var samples: [Float] = []
    samples.reserveCapacity(header.dataSize / Int(header.bitsPerSample / 8))
    for i in stride(from: header.dataOffset, to: header.dataOffset + header.dataSize, by: 2) {
        let value = Int16(littleEndian: data.subdata(in: i..<i+2).withUnsafeBytes { $0.load(as: Int16.self) })
        samples.append(Float(value) / Float(Int16.max))
    }
    return samples
}
