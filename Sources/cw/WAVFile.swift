import Foundation

/// Minimal WAV (RIFF) reader supporting 16‑bit PCM mono files.  It is sufficient
/// for loading the bundled test samples without relying on platform specific
/// audio frameworks.
struct WAVFile {
    let sampleRate: Double
    let samples: [Float]

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.count > 44 else {
            throw NSError(domain: "WAVFile", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "File too small to be a WAV file"])
        }

        func readUInt32(_ offset: Int) -> UInt32 {
            let range = offset..<(offset + 4)
            return data.subdata(in: range).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        }

        func readUInt16(_ offset: Int) -> UInt16 {
            let range = offset..<(offset + 2)
            return data.subdata(in: range).withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
        }

        // Basic RIFF/WAVE validation
        let riff = String(bytes: data[0..<4], encoding: .ascii)
        let wave = String(bytes: data[8..<12], encoding: .ascii)
        guard riff == "RIFF", wave == "WAVE" else {
            throw NSError(domain: "WAVFile", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid WAV file header"])
        }

        var offset = 12
        var foundData = false
        var dataOffset = 0
        var dataSize = 0
        var sampleRate: Int = 0
        var bitsPerSample: Int = 0
        var channels: Int = 0

        while offset + 8 <= data.count {
            let chunkID = String(bytes: data[offset..<(offset + 4)], encoding: .ascii)
            let chunkSize = Int(readUInt32(offset + 4))
            if chunkID == "fmt " {
                channels = Int(readUInt16(offset + 10))
                sampleRate = Int(readUInt32(offset + 12))
                bitsPerSample = Int(readUInt16(offset + 22))
            } else if chunkID == "data" {
                dataOffset = offset + 8
                dataSize = chunkSize
                foundData = true
                break
            }
            offset += 8 + chunkSize + (chunkSize % 2)
        }

        guard foundData else {
            throw NSError(domain: "WAVFile", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "WAV file missing data chunk"])
        }

        let bytesPerSample = bitsPerSample / 8
        let totalSamples = dataSize / bytesPerSample / max(channels, 1)
        var result: [Float] = []
        result.reserveCapacity(totalSamples)

        for i in 0..<totalSamples {
            let start = dataOffset + i * bytesPerSample * max(channels, 1)
            switch bitsPerSample {
            case 16:
                let value = Int16(littleEndian: data.subdata(in: start..<(start + 2)).withUnsafeBytes { $0.load(as: Int16.self) })
                result.append(Float(value) / Float(Int16.max))
            default:
                throw NSError(domain: "WAVFile", code: 4,
                              userInfo: [NSLocalizedDescriptionKey: "Unsupported bit depth: \(bitsPerSample)"])
            }
        }

        self.sampleRate = Double(sampleRate)
        self.samples = result
    }
}

