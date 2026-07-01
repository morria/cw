import Testing
import Foundation
@testable import cw

// MARK: - Sample fixtures

/// Sample files are named sample_<wpm>_<hz>_<snr>_<TEXT_WITH_UNDERSCORES>.wav
private struct SampleFixture {
    let url: URL
    let wpm: Double
    let frequency: Double
    let snr: Double
    let text: String

    init?(url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: "_")
        guard parts.count > 4, parts[0] == "sample",
              let wpm = Double(parts[1]),
              let frequency = Double(parts[2]),
              let snr = Double(parts[3])
        else { return nil }
        self.url = url
        self.wpm = wpm
        self.frequency = frequency
        self.snr = snr
        self.text = parts[4...].joined(separator: " ")
    }
}

private func allSampleFixtures() throws -> [SampleFixture] {
    let urls = try #require(
        Bundle.module.urls(forResourcesWithExtension: "wav", subdirectory: "samples"),
        "samples resource directory missing"
    )
    let fixtures = urls.compactMap(SampleFixture.init)
    #expect(fixtures.count == urls.count, "some sample filenames failed to parse")
    try #require(!fixtures.isEmpty, "no sample WAV files found")
    return fixtures.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
}

private func decode(_ samples: [Float], sampleRate: Double) -> (text: String, decoder: CWDecoder) {
    let seconds = Double(samples.count) / sampleRate
    let decoder = CWDecoder(sampleRate: sampleRate, bufferSeconds: max(seconds, 1.0))
    decoder.feed(samples: samples)
    return (decoder.decodeBuffer(), decoder)
}

// MARK: - Provided sample decoding

@Test func decodesAllProvidedSamples() throws {
    for fixture in try allSampleFixtures() {
        let wav = try WavFile(contentsOf: fixture.url)
        let (text, decoder) = decode(wav.samples, sampleRate: wav.sampleRate)
        let name = fixture.url.lastPathComponent

        #expect(text == fixture.text, "wrong decode for \(name)")

        let frequency = try #require(decoder.estimatedFrequency, "no frequency for \(name)")
        #expect(abs(frequency - fixture.frequency) < 25, "frequency off for \(name): \(frequency)")

        let wpm = try #require(decoder.estimatedWPM, "no WPM for \(name)")
        #expect(abs(wpm - fixture.wpm) / fixture.wpm < 0.15, "WPM off for \(name): \(wpm)")
    }
}

@Test func decodesProvidedSamplesWithAddedNoise() throws {
    // Re-noise the clean (30 dB) samples down to a broadband SNR of 5 dB.
    for fixture in try allSampleFixtures() where fixture.snr == 30 {
        let wav = try WavFile(contentsOf: fixture.url)
        let noisy = addNoise(to: wav.samples, snrDB: 5.0, seed: 1)
        let (text, _) = decode(noisy, sampleRate: wav.sampleRate)
        #expect(text == fixture.text, "wrong decode for \(fixture.url.lastPathComponent) at 5 dB SNR")
    }
}

// MARK: - Synthetic cross-validation

@Test(arguments: [
    ("HELLO WORLD", 40.0, 700.0, nil),
    ("THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG 0123456789", 30.0, 450.0, nil),
    ("CQ TEST DE K1ABC K1ABC K", 15.0, 800.0, 10.0),
    ("73 GL ES TNX FER QSO", 20.0, 550.0, 5.0),
    ("E", 20.0, 600.0, nil),
    ("EEE TTT", 18.0, 600.0, nil),
    ("PARIS PARIS", 5.0, 350.0, 15.0),
    ("HI, HOW ARE YOU? FINE = OK / QRZ", 22.0, 650.0, 20.0),
] as [(String, Double, Double, Double?)])
func decodesSynthesizedCW(_ testCase: (String, Double, Double, Double?)) throws {
    let (text, wpm, frequency, snrDB) = testCase
    let sampleRate = 8000.0
    let samples = synthesizeCW(
        text: text, wpm: wpm, frequency: frequency, sampleRate: sampleRate, snrDB: snrDB
    )
    let (decoded, decoder) = decode(samples, sampleRate: sampleRate)
    #expect(decoded == text)
    let estimatedFrequency = try #require(decoder.estimatedFrequency)
    #expect(abs(estimatedFrequency - frequency) < 25)
    let estimatedWPM = try #require(decoder.estimatedWPM)
    #expect(abs(estimatedWPM - wpm) / wpm < 0.20)
}

// MARK: - Degenerate inputs

@Test func emptyBufferDecodesToEmptyString() {
    let decoder = CWDecoder()
    #expect(decoder.decodeBuffer() == "")
    #expect(decoder.estimatedFrequency == nil)
    #expect(decoder.estimatedWPM == nil)
}

@Test func silenceDecodesToEmptyString() {
    let decoder = CWDecoder()
    decoder.feed(samples: [Float](repeating: 0.0, count: 16000))
    #expect(decoder.decodeBuffer() == "")
}

@Test func noiseOnlyDecodesToEmptyString() {
    let decoder = CWDecoder()
    decoder.feed(samples: gaussianNoise(count: 16000, standardDeviation: 0.2, seed: 3))
    #expect(decoder.decodeBuffer() == "")
}

@Test func resetClearsBufferAndEstimates() {
    let samples = synthesizeCW(text: "CQ", wpm: 20, frequency: 600, sampleRate: 8000, snrDB: nil)
    let decoder = CWDecoder(sampleRate: 8000)
    decoder.feed(samples: samples)
    #expect(decoder.decodeBuffer() == "CQ")
    decoder.reset()
    #expect(decoder.decodeBuffer() == "")
    #expect(decoder.estimatedFrequency == nil)
    #expect(decoder.estimatedDotDuration == nil)
}

@Test func decodeLastSecondsDecodesOnlyRecentAudio() {
    // "HI HI" at 20 WPM: the last word starts 23 units in; an 18-unit tail
    // window cuts inside the inter-word gap and should decode just "HI".
    let unit = 1.2 / 20.0
    let samples = synthesizeCW(text: "HI HI", wpm: 20, frequency: 600, sampleRate: 8000, snrDB: nil)
    let decoder = CWDecoder(sampleRate: 8000)
    decoder.feed(samples: samples)
    #expect(decoder.decodeBuffer() == "HI HI")
    #expect(decoder.decodeBuffer(lastSeconds: 18.0 * unit) == "HI")
}

@Test func ringBufferKeepsMostRecentAudio() {
    // Feed two transmissions into a buffer that can only hold the second;
    // the decoder must decode the most recent audio, not the oldest.
    let sampleRate = 8000.0
    let first = synthesizeCW(text: "AAA AAA", wpm: 20, frequency: 600, sampleRate: sampleRate, snrDB: nil)
    let second = synthesizeCW(text: "K1ABC", wpm: 20, frequency: 600, sampleRate: sampleRate, snrDB: nil)
    let bufferSeconds = Double(second.count) / sampleRate + 0.5
    let decoder = CWDecoder(sampleRate: sampleRate, bufferSeconds: bufferSeconds)
    decoder.feed(samples: first)
    decoder.feed(samples: [Float](repeating: 0, count: Int(0.5 * sampleRate)))
    decoder.feed(samples: second)
    #expect(decoder.decodeBuffer() == "K1ABC")
}

// MARK: - WAV parsing

@Test func wavReaderParsesProvidedSample() throws {
    let fixture = try #require(try allSampleFixtures().first)
    let wav = try WavFile(contentsOf: fixture.url)
    #expect(wav.sampleRate == 8000)
    #expect(wav.channelCount == 1)
    #expect(wav.samples.count > Int(wav.sampleRate))  // at least a second
    #expect(wav.samples.allSatisfy { $0 >= -1.0 && $0 <= 1.0 })
}

@Test func wavReaderRejectsGarbage() {
    #expect(throws: WavError.self) {
        _ = try WavFile(data: Data("this is not a wav file at all".utf8))
    }
    #expect(throws: WavError.self) {
        _ = try WavFile(data: Data())
    }
}

// MARK: - Synthesis helpers

/// Deterministic PRNG (SplitMix64) so noise tests behave identically on
/// every platform and run.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func gaussianNoise(count: Int, standardDeviation: Double, seed: UInt64) -> [Float] {
    var generator = SplitMix64(seed: seed)
    var noise = [Float]()
    noise.reserveCapacity(count)
    while noise.count < count {
        // Box-Muller transform.
        let u1 = Double.random(in: Double.leastNonzeroMagnitude..<1, using: &generator)
        let u2 = Double.random(in: 0..<1, using: &generator)
        let radius = (-2.0 * log(u1)).squareRoot() * standardDeviation
        noise.append(Float(radius * cos(2.0 * .pi * u2)))
        if noise.count < count {
            noise.append(Float(radius * sin(2.0 * .pi * u2)))
        }
    }
    return noise
}

private func addNoise(to samples: [Float], snrDB: Double, seed: UInt64) -> [Float] {
    let signalPower = samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)
    let noisePower = signalPower / pow(10.0, snrDB / 10.0)
    let noise = gaussianNoise(count: samples.count, standardDeviation: noisePower.squareRoot(), seed: seed)
    return zip(samples, noise).map { $0 + $1 }
}

/// Synthesizes an on/off-keyed sine for `text` with standard 1/3/7 Morse
/// timing and 5 ms raised-cosine key edges.
private func synthesizeCW(
    text: String, wpm: Double, frequency: Double, sampleRate: Double, snrDB: Double?,
    seed: UInt64 = 2
) -> [Float] {
    let patterns: [String: String] = Dictionary(
        uniqueKeysWithValues: CWDecoder.morseTable.map { ($0.value, $0.key) }
    )
    let unit = 1.2 / wpm
    var samples = [Float]()

    func tone(units: Double) {
        let count = Int(units * unit * sampleRate)
        let edge = Int(0.005 * sampleRate)
        for i in 0..<count {
            var amplitude = 1.0
            if i < edge {
                amplitude = 0.5 * (1 - cos(.pi * Double(i) / Double(edge)))
            } else if i > count - edge {
                amplitude = 0.5 * (1 - cos(.pi * Double(count - i) / Double(edge)))
            }
            let phase = 2.0 * Double.pi * frequency * Double(samples.count) / sampleRate
            samples.append(Float(0.5 * amplitude * sin(phase)))
        }
    }

    func silence(units: Double) {
        samples.append(contentsOf: [Float](repeating: 0, count: Int(units * unit * sampleRate)))
    }

    silence(units: 3)
    for (wordIndex, word) in text.split(separator: " ").enumerated() {
        if wordIndex > 0 { silence(units: 7) }
        for (characterIndex, character) in word.enumerated() {
            if characterIndex > 0 { silence(units: 3) }
            guard let pattern = patterns[String(character)] else { continue }
            for (elementIndex, element) in pattern.enumerated() {
                if elementIndex > 0 { silence(units: 1) }
                tone(units: element == "." ? 1 : 3)
            }
        }
    }
    silence(units: 3)

    if let snrDB {
        return addNoise(to: samples, snrDB: snrDB, seed: seed)
    }
    return samples
}
