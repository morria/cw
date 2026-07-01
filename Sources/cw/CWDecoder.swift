import Foundation

/// Decodes on/off-keyed Morse (CW) audio into text.
///
/// Feed raw audio samples with `feed(sample:)` or `feed(samples:)`, then call
/// `decodeBuffer()` to run the decoding pipeline:
///
/// 1. The carrier tone is located with a two-pass Goertzel scan (with a
///    subharmonic check so distorted tones don't lock onto a harmonic).
/// 2. A tone-selective envelope is computed with a sliding Goertzel window at
///    the detected frequency, giving strong immunity to broadband noise.
/// 3. The envelope is segmented into mark/space runs using an adaptive
///    two-means threshold with hysteresis.
/// 4. The dot duration is estimated by clustering mark lengths, short noise
///    runs are re-merged relative to the dot, and elements/gaps are classified
///    against standard 1/3/7-unit Morse timing.
public final class CWDecoder {
    private let sampleRate: Double
    private let bufferSize: Int
    private var buffer: [Float]
    private var writeIndex: Int = 0
    private var filled: Bool = false

    /// Detected carrier frequency in Hz, set by the last decode.
    public private(set) var estimatedFrequency: Double?
    /// Estimated dot (dit) duration in seconds, set by the last decode.
    public private(set) var estimatedDotDuration: Double?
    /// Estimated words per minute (PARIS standard), set by the last decode.
    public var estimatedWPM: Double? {
        estimatedDotDuration.map { 1.2 / $0 }
    }

    /// Lowest carrier frequency considered, in Hz.
    public let minimumFrequency: Double
    /// Highest carrier frequency considered, in Hz.
    public let maximumFrequency: Double

    /// - Parameters:
    ///   - sampleRate: Sample rate of the audio that will be fed, in Hz.
    ///   - bufferSeconds: How much trailing audio to retain for decoding.
    ///   - minimumFrequency: Lowest carrier frequency to search for, in Hz.
    ///   - maximumFrequency: Highest carrier frequency to search for, in Hz.
    public init(
        sampleRate: Double = 8000.0,
        bufferSeconds: Double = 120.0,
        minimumFrequency: Double = 250.0,
        maximumFrequency: Double = 1200.0
    ) {
        self.sampleRate = sampleRate
        self.bufferSize = max(1, Int(sampleRate * bufferSeconds))
        self.buffer = Array(repeating: 0.0, count: bufferSize)
        self.minimumFrequency = minimumFrequency
        self.maximumFrequency = maximumFrequency
    }

    /// Appends one audio sample to the ring buffer.
    public func feed(sample: Float) {
        buffer[writeIndex] = sample
        writeIndex += 1
        if writeIndex >= bufferSize {
            writeIndex = 0
            filled = true
        }
    }

    /// Appends a block of audio samples to the ring buffer.
    public func feed(samples: [Float]) {
        for sample in samples {
            feed(sample: sample)
        }
    }

    /// Discards all buffered audio and estimates.
    public func reset() {
        writeIndex = 0
        filled = false
        buffer = Array(repeating: 0.0, count: bufferSize)
        estimatedFrequency = nil
        estimatedDotDuration = nil
    }

    /// Decodes the buffered audio and returns the recovered text.
    ///
    /// - Parameter lastSeconds: If given, only the most recent span of audio
    ///   is decoded; otherwise everything buffered is used.
    public func decodeBuffer(lastSeconds: Double? = nil) -> String {
        decodeSamples(collectSamples(lastSeconds: lastSeconds))
    }

    private func collectSamples(lastSeconds: Double?) -> [Float] {
        let available = filled ? bufferSize : writeIndex
        let count: Int
        if let seconds = lastSeconds {
            count = min(max(0, Int(sampleRate * seconds)), available)
        } else {
            count = available
        }
        guard count > 0 else { return [] }
        var result = [Float](repeating: 0.0, count: count)
        // Read the most recent `count` samples ending at writeIndex.
        var idx = (writeIndex - count + bufferSize * 2) % bufferSize
        for i in 0..<count {
            result[i] = buffer[idx]
            idx += 1
            if idx == bufferSize { idx = 0 }
        }
        return result
    }

    // MARK: - Decoding pipeline

    private func decodeSamples(_ samples: [Float]) -> String {
        estimatedFrequency = nil
        estimatedDotDuration = nil
        guard samples.count >= 256 else { return "" }

        guard let frequency = estimateFrequency(samples: samples) else { return "" }
        estimatedFrequency = frequency

        let (envelope, hop) = toneEnvelope(samples: samples, frequency: frequency)
        guard !envelope.isEmpty else { return "" }

        let (floorLevel, signalLevel) = twoMeans(envelope)
        // A keyed tone must stand well clear of the noise floor.
        guard signalLevel > 0, signalLevel >= 4.0 * floorLevel else { return "" }

        var runs = segment(
            envelope: envelope,
            onThreshold: floorLevel + 0.50 * (signalLevel - floorLevel),
            offThreshold: floorLevel + 0.25 * (signalLevel - floorLevel)
        )

        // First pass: drop sub-10ms blips, then get a rough dot estimate.
        runs = mergeShortRuns(runs, minimumLength: max(1, Int(0.010 * sampleRate / Double(hop))))
        guard var unit = estimateUnit(runs: runs) else { return "" }
        // Second pass: with the dot known, absorb dips and spikes shorter
        // than a third of a dot (noise chopping a dash or bridging a gap).
        let refined = mergeShortRuns(runs, minimumLength: max(1, Int(unit / 3.0)))
        if let refinedUnit = estimateUnit(runs: refined) {
            runs = refined
            unit = refinedUnit
        }
        estimatedDotDuration = unit * Double(hop) / sampleRate

        return decodeRuns(runs, unit: unit)
    }

    // MARK: - Frequency estimation

    /// Two-pass tone search over the highest-energy analysis windows.
    private func estimateFrequency(samples: [Float]) -> Double? {
        let window = min(1024, samples.count)
        guard window >= 64 else { return nil }

        // Rank non-overlapping windows by energy; key-down segments dominate.
        var windows: [(energy: Double, start: Int)] = []
        var start = 0
        while start + window <= samples.count {
            var energy = 0.0
            for i in start..<(start + window) {
                energy += Double(samples[i]) * Double(samples[i])
            }
            windows.append((energy, start))
            start += window
        }
        guard !windows.isEmpty else { return nil }
        windows.sort { $0.energy > $1.energy }
        let top = windows.prefix(8).map { $0.start }

        func power(at frequency: Double) -> Double {
            var total = 0.0
            for s in top {
                total += goertzelPower(samples: samples, start: s, count: window, frequency: frequency)
            }
            return total
        }

        // Coarse scan at the window's natural resolution.
        let coarseStep = sampleRate / Double(window)
        var bestFrequency = minimumFrequency
        var bestPower = -1.0
        var f = minimumFrequency
        while f <= maximumFrequency {
            let p = power(at: f)
            if p > bestPower {
                bestPower = p
                bestFrequency = f
            }
            f += coarseStep
        }

        // Harmonic guard: a clipped or distorted tone can put more energy in
        // a harmonic bin; prefer a subharmonic carrying comparable power.
        for divisor in [3.0, 2.0] {
            let sub = bestFrequency / divisor
            if sub >= minimumFrequency {
                let p = power(at: sub)
                if p > 0.4 * bestPower {
                    bestFrequency = sub
                    bestPower = p
                    break
                }
            }
        }

        // Fine scan +/- one coarse step at 1 Hz resolution.
        var fineBest = bestFrequency
        var finePower = bestPower
        f = bestFrequency - coarseStep
        while f <= bestFrequency + coarseStep {
            if f >= minimumFrequency {
                let p = power(at: f)
                if p > finePower {
                    finePower = p
                    fineBest = f
                }
            }
            f += 1.0
        }
        return fineBest
    }

    /// Normalized power near `frequency` over `samples[start..<start+count]`
    /// using the generalized (non-integer-bin) Goertzel algorithm.
    private func goertzelPower(samples: [Float], start: Int, count: Int, frequency: Double) -> Double {
        let omega = 2.0 * Double.pi * frequency / sampleRate
        let cosine = cos(omega)
        let sine = sin(omega)
        let coefficient = 2.0 * cosine
        var q1 = 0.0
        var q2 = 0.0
        for i in start..<(start + count) {
            let q0 = coefficient * q1 - q2 + Double(samples[i])
            q2 = q1
            q1 = q0
        }
        let real = q1 - q2 * cosine
        let imaginary = q2 * sine
        return (real * real + imaginary * imaginary) / Double(count * count)
    }

    // MARK: - Envelope

    /// Envelope of the tone at `frequency` via a sliding Goertzel window
    /// (10 ms window, 2.5 ms hop), lightly smoothed. Returns the envelope
    /// and the hop size in samples.
    private func toneEnvelope(samples: [Float], frequency: Double) -> ([Double], Int) {
        let hop = max(1, Int(sampleRate * 0.0025))
        let window = max(hop, Int(sampleRate * 0.010))
        guard samples.count >= window else { return ([], hop) }
        var envelope: [Double] = []
        envelope.reserveCapacity(samples.count / hop + 1)
        var start = 0
        while start + window <= samples.count {
            envelope.append(goertzelPower(samples: samples, start: start, count: window, frequency: frequency).squareRoot())
            start += hop
        }
        // 3-tap moving average to suppress single-hop spikes.
        if envelope.count >= 3 {
            var smoothed = envelope
            for i in 1..<(envelope.count - 1) {
                smoothed[i] = (envelope[i - 1] + envelope[i] + envelope[i + 1]) / 3.0
            }
            envelope = smoothed
        }
        return (envelope, hop)
    }

    /// 1-D two-means clustering. Returns (low center, high center).
    private func twoMeans(_ values: [Double]) -> (Double, Double) {
        guard let lo = values.min(), let hi = values.max(), lo < hi else {
            return (values.first ?? 0, values.first ?? 0)
        }
        var c0 = lo
        var c1 = hi
        for _ in 0..<20 {
            let mid = (c0 + c1) / 2.0
            var s0 = 0.0, s1 = 0.0
            var n0 = 0, n1 = 0
            for v in values {
                if v < mid {
                    s0 += v
                    n0 += 1
                } else {
                    s1 += v
                    n1 += 1
                }
            }
            let nc0 = n0 > 0 ? s0 / Double(n0) : c0
            let nc1 = n1 > 0 ? s1 / Double(n1) : c1
            if abs(nc0 - c0) < 1e-12 && abs(nc1 - c1) < 1e-12 { break }
            c0 = nc0
            c1 = nc1
        }
        return (c0, c1)
    }

    // MARK: - Segmentation

    private struct Run {
        var isOn: Bool
        var length: Int
    }

    /// Splits the envelope into mark/space runs with hysteresis: a mark must
    /// rise above `onThreshold` to start and fall below `offThreshold` to end.
    private func segment(envelope: [Double], onThreshold: Double, offThreshold: Double) -> [Run] {
        var runs: [Run] = []
        var state = envelope[0] >= onThreshold
        var length = 1
        for v in envelope.dropFirst() {
            let s = state ? (v >= offThreshold) : (v >= onThreshold)
            if s == state {
                length += 1
            } else {
                runs.append(Run(isOn: state, length: length))
                state = s
                length = 1
            }
        }
        runs.append(Run(isOn: state, length: length))
        return runs
    }

    /// Absorbs runs shorter than `minimumLength` into their predecessor and
    /// coalesces neighbours left with the same state.
    private func mergeShortRuns(_ runs: [Run], minimumLength: Int) -> [Run] {
        var merged: [Run] = []
        for run in runs {
            if run.length < minimumLength, !merged.isEmpty {
                merged[merged.count - 1].length += run.length
            } else if let last = merged.last, last.isOn == run.isOn {
                merged[merged.count - 1].length += run.length
            } else {
                merged.append(run)
            }
        }
        return merged
    }

    /// Estimates the dot length (in envelope hops) by clustering mark runs
    /// into dot/dash groups.
    private func estimateUnit(runs: [Run]) -> Double? {
        let ons = runs.filter { $0.isOn }.map { Double($0.length) }
        guard !ons.isEmpty else { return nil }
        let (d0, d1) = twoMeans(ons)
        if d1 >= 2.0 * d0 {
            return (d0 + d1 / 3.0) / 2.0
        }
        // Single duration class (e.g. "EEE" or "TTT"): interior gaps
        // disambiguate — an intra-character gap is one unit long.
        var gaps: [Double] = []
        for (index, run) in runs.enumerated() where !run.isOn && index > 0 && index < runs.count - 1 {
            gaps.append(Double(run.length))
        }
        let average = (d0 + d1) / 2.0
        if let shortestGap = gaps.min(), shortestGap * 2.0 <= average {
            return average / 3.0
        }
        return average
    }

    // MARK: - Symbol decoding

    private func decodeRuns(_ runs: [Run], unit: Double) -> String {
        var output = ""
        var pattern = ""

        func flush() {
            if let character = CWDecoder.morseTable[pattern] {
                output.append(character)
            }
            pattern = ""
        }

        var index = 0
        while index < runs.count && !runs[index].isOn { index += 1 }
        while index < runs.count {
            pattern.append(Double(runs[index].length) > 2.0 * unit ? "-" : ".")
            let gap = index + 1 < runs.count ? Double(runs[index + 1].length) : 0.0
            let isLast = runs[(index + 1)...].allSatisfy { !$0.isOn }
            if isLast {
                flush()
            } else if gap > 5.0 * unit {
                flush()
                output.append(" ")
            } else if gap > 2.0 * unit {
                flush()
            }
            index += 2
        }
        return output.trimmingCharacters(in: .whitespaces)
    }

    static let morseTable: [String: String] = [
        ".-": "A", "-...": "B", "-.-.": "C", "-..": "D", ".": "E",
        "..-.": "F", "--.": "G", "....": "H", "..": "I", ".---": "J",
        "-.-": "K", ".-..": "L", "--": "M", "-.": "N", "---": "O",
        ".--.": "P", "--.-": "Q", ".-.": "R", "...": "S", "-": "T",
        "..-": "U", "...-": "V", ".--": "W", "-..-": "X", "-.--": "Y",
        "--..": "Z",
        "-----": "0", ".----": "1", "..---": "2", "...--": "3", "....-": "4",
        ".....": "5", "-....": "6", "--...": "7", "---..": "8", "----.": "9",
        ".-.-.-": ".", "--..--": ",", "..--..": "?", ".----.": "'",
        "-.-.--": "!", "-..-.": "/", "-.--.": "(", "-.--.-": ")",
        ".-...": "&", "---...": ":", "-.-.-.": ";", "-...-": "=",
        ".-.-.": "+", "-....-": "-", "..--.-": "_", ".-..-.": "\"",
        "...-..-": "$", ".--.-.": "@",
    ]
}
