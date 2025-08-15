import Foundation

public class CWDecoder {
    private let sampleRate: Double
    private let bufferSize: Int
    private var buffer: [Float]
    private var writeIndex: Int = 0
    private var filled: Bool = false

    public private(set) var estimatedFrequency: Double?
    public private(set) var estimatedDotDuration: Double?

    public init(sampleRate: Double = 8000.0, bufferSeconds: Double = 20.0) {
        self.sampleRate = sampleRate
        self.bufferSize = Int(sampleRate * bufferSeconds)
        self.buffer = Array(repeating: 0.0, count: bufferSize)
    }

    public func feed(sample: Float) {
        buffer[writeIndex] = sample
        writeIndex += 1
        if writeIndex >= bufferSize {
            writeIndex = 0
            filled = true
        }
    }

    private func collectSamples(lastSeconds: Double? = nil) -> [Float] {
        let available = filled ? bufferSize : writeIndex
        let count: Int
        if let seconds = lastSeconds {
            count = min(Int(sampleRate * seconds), available)
        } else {
            count = available
        }
        var result: [Float] = Array(repeating: 0.0, count: count)
        let start = (filled ? writeIndex : 0)
        for i in 0..<count {
            let idx = (start + i) % bufferSize
            result[i] = buffer[idx]
        }
        return result
    }

    public func decodeBuffer(lastSeconds: Double? = nil) -> String {
        let samples = collectSamples(lastSeconds: lastSeconds)
        return decodeSamples(samples)
    }

    private func decodeSamples(_ samples: [Float]) -> String {
        guard !samples.isEmpty else { return "" }
        // Estimate frequency on first 4096 samples
        let freq = estimateFrequency(samples: Array(samples.prefix(4096)))
        self.estimatedFrequency = freq

        // Envelope detection using RMS over a sliding window
        var envelope = [Float](repeating: 0.0, count: samples.count)
        let window = Int(sampleRate * 0.01) // 10ms window
        var sum: Float = 0.0
        for i in 0..<samples.count {
            let s = samples[i]
            sum += s * s
            if i >= window {
                let old = samples[i - window]
                sum -= old * old
            }
            let denom = Float(min(i + 1, window))
            envelope[i] = sqrt(sum / denom)
        }
        guard let maxEnv = envelope.max(), maxEnv > 0 else { return "" }
        let threshold = maxEnv * 0.3

        var runs: [(Bool, Int)] = []
        var state = envelope[0] > threshold
        var length = 1
        for i in 1..<envelope.count {
            let s = envelope[i] > threshold
            if s == state {
                length += 1
            } else {
                runs.append((state, length))
                state = s
                length = 1
            }
        }
        runs.append((state, length))

        // Merge very short runs that are likely noise
        let minRun = Int(sampleRate * 0.02)
        var filtered: [(Bool, Int)] = []
        for run in runs {
            if run.1 < minRun, let last = filtered.last {
                filtered[filtered.count - 1] = (last.0, last.1 + run.1)
            } else {
                filtered.append(run)
            }
        }
        // merge consecutive runs of same state
        var merged: [(Bool, Int)] = []
        for run in filtered {
            if let last = merged.last, last.0 == run.0 {
                merged[merged.count - 1] = (last.0, last.1 + run.1)
            } else {
                merged.append(run)
            }
        }
        runs = merged

        // Determine dot length
        let onRuns = runs.filter { $0.0 }.map { $0.1 }.filter { $0 > Int(sampleRate * 0.02) }
        guard let minOn = onRuns.min() else { return "" }
        let dot = minOn
        self.estimatedDotDuration = Double(dot) / sampleRate

        var result = ""
        var current = ""
        var index = 0
        while index < runs.count && runs[index].0 == false { index += 1 }
        while index < runs.count {
            let onLen = runs[index].1
            current += onLen < dot * 2 ? "." : "-"
            let offLen = (index + 1 < runs.count) ? runs[index + 1].1 : 0
            if offLen >= dot * 6 {
                if let ch = CWDecoder.morseTable[current] { result.append(ch) }
                result.append(" ")
                current = ""
                index += 2
            } else if offLen >= dot * 2 {
                if let ch = CWDecoder.morseTable[current] { result.append(ch) }
                current = ""
                index += 2
            } else {
                index += 2
            }
        }
        if !current.isEmpty {
            if let ch = CWDecoder.morseTable[current] { result.append(ch) }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private func estimateFrequency(samples: [Float]) -> Double? {
        guard samples.count > 0 else { return nil }
        let startFreq = 300.0
        let endFreq = 1000.0
        let step = 10.0
        var bestFreq = startFreq
        var bestMag: Double = 0.0
        for f in stride(from: startFreq, through: endFreq, by: step) {
            let mag = goertzelMagnitude(samples: samples, sampleRate: sampleRate, targetFrequency: f)
            if mag > bestMag {
                bestMag = mag
                bestFreq = f
            }
        }
        return bestFreq
    }

    private func goertzelMagnitude(samples: [Float], sampleRate: Double, targetFrequency: Double) -> Double {
        let n = samples.count
        let k = Int(0.5 + Double(n) * targetFrequency / sampleRate)
        let omega = 2.0 * Double.pi * Double(k) / Double(n)
        let sine = sin(omega)
        let cosine = cos(omega)
        var q0: Double = 0
        var q1: Double = 0
        var q2: Double = 0
        for sample in samples {
            q0 = 2.0 * cosine * q1 - q2 + Double(sample)
            q2 = q1
            q1 = q0
        }
        let real = q1 - q2 * cosine
        let imag = q2 * sine
        return sqrt(real * real + imag * imag)
    }

    private static let morseTable: [String: String] = [
        ".-": "A", "-...": "B", "-.-.": "C", "-..": "D", ".": "E",
        "..-.": "F", "--.": "G", "....": "H", "..": "I", ".---": "J",
        "-.-": "K", ".-..": "L", "--": "M", "-.": "N", "---": "O",
        ".--.": "P", "--.-": "Q", ".-.": "R", "...": "S", "-": "T",
        "..-": "U", "...-": "V", ".--": "W", "-..-": "X", "-.--": "Y",
        "--..": "Z",
        "-----": "0", ".----": "1", "..---": "2", "...--": "3", "....-": "4",
        ".....": "5", "-....": "6", "--...": "7", "---..": "8", "----.": "9"
    ]
}
