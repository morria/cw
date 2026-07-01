import Foundation
import cw

let usage = """
USAGE: listen <file.wav>         Decode a CW recording and print the text
       listen --devices          List audio input devices (macOS only)
       listen --live [deviceID]  Decode live audio from an input device
                                 (macOS only; omit deviceID for the default)
"""

func decodeFile(_ path: String) -> Int32 {
    let wav: WavFile
    do {
        wav = try WavFile(contentsOf: URL(fileURLWithPath: path))
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        return 1
    }
    let duration = Double(wav.samples.count) / wav.sampleRate
    let decoder = CWDecoder(sampleRate: wav.sampleRate, bufferSeconds: max(duration, 1.0))
    decoder.feed(samples: wav.samples)
    let text = decoder.decodeBuffer()

    if let frequency = decoder.estimatedFrequency {
        let wpm = decoder.estimatedWPM.map { String(format: "%.0f", $0) } ?? "?"
        FileHandle.standardError.write(
            Data(String(format: "tone: %.0f Hz, speed: %@ WPM\n", frequency, wpm).utf8)
        )
    }
    print(text)
    return text.isEmpty ? 2 : 0
}

#if os(macOS)
/// Collects samples from the audio thread for the main thread to drain.
final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(_ sample: Float) {
        lock.lock()
        samples.append(sample)
        lock.unlock()
    }

    func drain() -> [Float] {
        lock.lock()
        defer {
            samples.removeAll(keepingCapacity: true)
            lock.unlock()
        }
        return samples
    }
}

func decodeLive(deviceID: UInt32?) -> Int32 {
    let streamer = MacOSDeviceStreamer(deviceID: deviceID)
    let sampleBuffer = SampleBuffer()
    do {
        try streamer.startStreaming { sampleBuffer.append($0) }
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        return 1
    }
    FileHandle.standardError.write(
        Data("listening at \(Int(streamer.sampleRate)) Hz — press Ctrl-C to stop\n".utf8)
    )
    let decoder = CWDecoder(sampleRate: streamer.sampleRate, bufferSeconds: 120.0)
    var lastText = ""
    while true {
        Thread.sleep(forTimeInterval: 2.0)
        decoder.feed(samples: sampleBuffer.drain())
        let text = decoder.decodeBuffer()
        if text != lastText {
            lastText = text
            let frequency = decoder.estimatedFrequency.map { String(format: "%.0f Hz", $0) } ?? "?"
            let wpm = decoder.estimatedWPM.map { String(format: "%.0f WPM", $0) } ?? "?"
            print("[\(frequency), \(wpm)] \(text)")
        }
    }
}
#endif

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case nil, "--help", "-h":
    print(usage)
    exit(arguments.first == nil ? 1 : 0)
case "--devices":
    listAudioDevices()
    exit(0)
case "--live":
    #if os(macOS)
    let deviceID = arguments.count > 1 ? UInt32(arguments[1]) : nil
    if arguments.count > 1 && deviceID == nil {
        FileHandle.standardError.write(Data("error: invalid device ID '\(arguments[1])'\n".utf8))
        exit(1)
    }
    exit(decodeLive(deviceID: deviceID))
    #else
    FileHandle.standardError.write(Data("error: live capture is only supported on macOS\n".utf8))
    exit(1)
    #endif
default:
    exit(decodeFile(arguments[0]))
}
