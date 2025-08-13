import Foundation

/// Decode Continuous Wave (Morse) audio streams into text.
///
/// This implementation is intentionally lightweight – it performs basic tone
/// detection using the Goertzel algorithm, converts the resulting power
/// envelope into keyed/unkeyed durations and finally maps the detected dot/dash
/// sequences to characters.  It is sufficient for decoding the bundled test
/// samples which contain relatively clean single‑frequency Morse recordings.
public final class CWDecoder {
    public init() {}

    /// Decode a WAV file located at `path` and return the detected text.
    public func decodeWAVFile(atPath path: String) throws -> String {
        let wav = try WAVFile(url: URL(fileURLWithPath: path))
        return decode(samples: wav.samples, sampleRate: wav.sampleRate)
    }

    /// Decode a buffer of samples recorded at `sampleRate`.
    public func decode(samples: [Float], sampleRate: Double) -> String {
        // Estimate the dominant tone frequency in the 300–1000 Hz range.
        let tone = estimateFrequency(samples: samples, sampleRate: sampleRate)

        // Break the stream into 10 ms windows and compute the tone power for
        // each window.  Afterwards apply a short moving average to smooth the
        // envelope which helps remove spurious transitions.
        let windowDuration = 0.01 // seconds
        let windowSize = max(1, Int(sampleRate * windowDuration))
        var powers: [Float] = []
        powers.reserveCapacity(samples.count / windowSize)
        var index = 0
        while index < samples.count {
            let end = min(index + windowSize, samples.count)
            let power = goertzel(Array(samples[index..<end]), tone, sampleRate)
            powers.append(power)
            index = end
        }
        guard !powers.isEmpty else { return "" }

        var magnitudes: [Float] = []
        magnitudes.reserveCapacity(powers.count)
        for i in 0..<powers.count {
            let start = max(0, i - 2)
            let end = min(powers.count, i + 3)
            let slice = powers[start..<end]
            let avg = slice.reduce(0, +) / Float(slice.count)
            magnitudes.append(avg)
        }

        guard let maxMag = magnitudes.max() else { return "" }
        let threshold = maxMag * 0.3
        let states = magnitudes.map { $0 > threshold }

        // Compress consecutive states into durations measured in windows.
        var segments: [(Bool, Int)] = []
        var current = states.first ?? false
        var length = 0
        for state in states {
            if state == current {
                length += 1
            } else {
                segments.append((current, length))
                current = state
                length = 1
            }
        }
        segments.append((current, length))

        // Determine the basic time unit T (length of a dot). Use the 33rd
        // percentile of keyed segments (ignoring very short blips) for a robust
        // estimate.
        let keyedLengths = segments.filter { $0.0 && $0.1 >= 3 }.map { $0.1 }.sorted()
        let unit: Int
        if keyedLengths.isEmpty {
            unit = 1
        } else {
            unit = keyedLengths[keyedLengths.count / 3]
        }

        // Merge segments shorter than half a unit into their predecessor and
        // collapse consecutive segments of the same state.
        let minLen = max(1, unit / 2)
        var cleaned: [(Bool, Int)] = []
        for seg in segments {
            if seg.1 < minLen {
                if let last = cleaned.last {
                    cleaned[cleaned.count - 1].1 = last.1 + seg.1
                }
            } else {
                if let last = cleaned.last, last.0 == seg.0 {
                    cleaned[cleaned.count - 1].1 = last.1 + seg.1
                } else {
                    cleaned.append(seg)
                }
            }
        }
        segments = cleaned

        var result = ""
        var symbol = ""
        func flushSymbol() {
            if !symbol.isEmpty {
                if let char = morseToChar[symbol] {
                    result.append(char)
                } else {
                    result.append("?")
                }
                symbol.removeAll()
            }
        }

        for seg in segments {
            if seg.0 { // keyed (tone present)
                if seg.1 < 2 * unit {
                    symbol.append(".")
                } else {
                    symbol.append("-")
                }
            } else { // unkeyed (silence)
                if seg.1 >= 6 * unit {
                    flushSymbol()
                    result.append(" ")
                } else if seg.1 >= 3 * unit {
                    flushSymbol()
                }
            }
        }
        flushSymbol()

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Estimate the dominant tone frequency in the given sample buffer.
    private func estimateFrequency(samples: [Float], sampleRate: Double) -> Double {
        var bestFreq: Double = 600
        var bestPower: Float = -Float.greatestFiniteMagnitude
        var freq: Double = 300
        while freq <= 1000 {
            let power = goertzel(samples, freq, sampleRate)
            if power > bestPower {
                bestPower = power
                bestFreq = freq
            }
            freq += 10
        }
        return bestFreq
    }

    /// Power computation for a specific tone using the Goertzel algorithm.
    private func goertzel(_ samples: [Float], _ targetFrequency: Double, _ sampleRate: Double) -> Float {
        let normalizedFrequency = targetFrequency / sampleRate
        let coeff = 2.0 * cos(2.0 * Double.pi * normalizedFrequency)
        var sPrev: Double = 0
        var sPrev2: Double = 0
        for sample in samples {
            let s = Double(sample) + coeff * sPrev - sPrev2
            sPrev2 = sPrev
            sPrev = s
        }
        let power = sPrev2 * sPrev2 + sPrev * sPrev - coeff * sPrev * sPrev2
        return Float(power)
    }

    /// Mapping from dot/dash sequences to characters.
    private let morseToChar: [String: String] = [
        ".-": "A", "-...": "B", "-.-.": "C", "-..": "D", ".": "E", "..-.": "F",
        "--.": "G", "....": "H", "..": "I", ".---": "J", "-.-": "K", ".-..": "L",
        "--": "M", "-.": "N", "---": "O", ".--.": "P", "--.-": "Q", ".-.": "R",
        "...": "S", "-": "T", "..-": "U", "...-": "V", ".--": "W", "-..-": "X",
        "-.--": "Y", "--..": "Z", "-----": "0", ".----": "1", "..---": "2",
        "...--": "3", "....-": "4", ".....": "5", "-....": "6", "--...": "7",
        "---..": "8", "----.": "9"
    ]
}

