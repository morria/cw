import Foundation

/// Errors thrown while parsing a WAV file.
public enum WavError: Error, CustomStringConvertible {
    case notAWavFile
    case missingChunk(String)
    case unsupportedFormat(String)

    public var description: String {
        switch self {
        case .notAWavFile:
            return "Not a RIFF/WAVE file"
        case .missingChunk(let name):
            return "Missing required chunk: \(name)"
        case .unsupportedFormat(let detail):
            return "Unsupported WAV format: \(detail)"
        }
    }
}

/// A decoded WAV file: mono samples normalized to [-1, 1].
///
/// Walks the RIFF chunk list rather than assuming a fixed 44-byte header, so
/// files with extra chunks (LIST, fact, ...) parse correctly. Supports PCM
/// 8/16/24/32-bit and IEEE float 32-bit; multi-channel audio is averaged
/// down to mono.
public struct WavFile {
    public let sampleRate: Double
    public let channelCount: Int
    public let samples: [Float]

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        try self.init(data: data)
    }

    public init(data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 12,
              bytes[0...3].elementsEqual("RIFF".utf8),
              bytes[8...11].elementsEqual("WAVE".utf8)
        else {
            throw WavError.notAWavFile
        }

        func uint16(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
        }
        func uint32(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
                | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }

        var formatTag: Int?
        var channels = 0
        var rate = 0
        var bitsPerSample = 0
        var dataRange: Range<Int>?

        var offset = 12
        while offset + 8 <= bytes.count {
            let chunkID = String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self)
            let chunkSize = uint32(offset + 4)
            let body = offset + 8
            let available = min(chunkSize, bytes.count - body)
            switch chunkID {
            case "fmt ":
                guard available >= 16 else { throw WavError.missingChunk("fmt ") }
                formatTag = uint16(body)
                channels = uint16(body + 2)
                rate = uint32(body + 4)
                bitsPerSample = uint16(body + 14)
            case "data":
                dataRange = body..<(body + available)
            default:
                break
            }
            // Chunk bodies are padded to even sizes.
            offset = body + chunkSize + (chunkSize & 1)
        }

        guard let tag = formatTag else { throw WavError.missingChunk("fmt ") }
        guard let range = dataRange else { throw WavError.missingChunk("data") }
        guard channels >= 1, rate > 0 else {
            throw WavError.unsupportedFormat("channels=\(channels) sampleRate=\(rate)")
        }

        let bytesPerSample = bitsPerSample / 8
        guard bytesPerSample > 0 else {
            throw WavError.unsupportedFormat("bitsPerSample=\(bitsPerSample)")
        }
        let frameSize = bytesPerSample * channels
        let frameCount = (range.count) / frameSize

        func sampleValue(_ offset: Int) throws -> Float {
            switch (tag, bitsPerSample) {
            case (1, 8):
                // 8-bit PCM is unsigned.
                return (Float(bytes[offset]) - 128.0) / 128.0
            case (1, 16):
                let raw = Int16(truncatingIfNeeded: uint16(offset))
                return Float(raw) / 32768.0
            case (1, 24):
                var value = uint32(offset) & 0x00FF_FFFF
                if value & 0x0080_0000 != 0 { value -= 0x0100_0000 }
                return Float(value) / 8_388_608.0
            case (1, 32):
                let raw = Int32(truncatingIfNeeded: uint32(offset))
                return Float(Double(raw) / 2_147_483_648.0)
            case (3, 32):
                let pattern = UInt32(bitPattern: Int32(truncatingIfNeeded: uint32(offset)))
                return Float(bitPattern: pattern)
            default:
                throw WavError.unsupportedFormat("formatTag=\(tag) bitsPerSample=\(bitsPerSample)")
            }
        }

        var mono = [Float]()
        mono.reserveCapacity(frameCount)
        for frame in 0..<frameCount {
            let frameOffset = range.lowerBound + frame * frameSize
            var sum: Float = 0
            for channel in 0..<channels {
                sum += try sampleValue(frameOffset + channel * bytesPerSample)
            }
            mono.append(sum / Float(channels))
        }

        self.sampleRate = Double(rate)
        self.channelCount = channels
        self.samples = mono
    }
}
