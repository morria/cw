import Foundation

/// A minimal abstraction representing a source of audio samples.
public protocol AudioStreamSource {
    /// Begin streaming floating point samples to the provided callback.
    ///
    /// - Parameter onSample: callback receiving a single normalized sample in the
    ///   range `[-1, 1]`.
    func startStreaming(_ onSample: ((Float) -> Void)?) throws

    /// Stop streaming samples.
    func stopStreaming()
}

/// Stream samples from an on–disk WAV file. The entire file is loaded into
/// memory and every sample is forwarded to the callback.
public final class FileStreamer: AudioStreamSource {
    private let fileURL: URL

    public init(filePath: String) throws {
        let url = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(
                domain: "FileStreamer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "File not found"]
            )
        }
        self.fileURL = url
    }

    public func startStreaming(_ onSample: ((Float) -> Void)?) throws {
        let wav = try WAVFile(url: fileURL)
        for sample in wav.samples {
            onSample?(sample)
        }
    }

    public func stopStreaming() {
        // Nothing to clean up for file based streaming
    }
}

#if canImport(AVFoundation) && os(macOS)
import AVFoundation

/// Stream audio from a macOS audio input device.
public final class MacOSDeviceStreamer: AudioStreamSource {
    private let deviceID: String
    private var audioEngine: AVAudioEngine?

    public init(deviceID: String) {
        self.deviceID = deviceID
    }

    public func startStreaming(_ onSample: ((Float) -> Void)?) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(
                domain: "MacOSDeviceStreamer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"]
            )
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            let frameCount = Int(buffer.frameLength)
            guard let data = buffer.floatChannelData?[0] else { return }
            for i in 0..<frameCount {
                onSample?(data[i])
            }
        }

        try engine.start()
        audioEngine = engine
    }

    public func stopStreaming() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }
}
#endif
