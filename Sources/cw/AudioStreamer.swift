import Foundation

/// A source of mono audio samples.
///
/// The callback may be invoked on a background thread (live capture delivers
/// samples from the audio thread), hence `@Sendable`.
public protocol AudioStreamSource {
    /// Sample rate of the samples delivered to the callback, in Hz.
    var sampleRate: Double { get }
    /// Begins delivering samples to `onSample`.
    func startStreaming(_ onSample: (@Sendable (Float) -> Void)?) throws
    /// Stops delivering samples.
    func stopStreaming()
}

#if canImport(AVFoundation)
import AVFoundation

/// Streams samples from an audio file using AVFoundation (any format
/// AVAudioFile can read).
public final class FileStreamer: AudioStreamSource {
    private let fileURL: URL
    private var audioFile: AVAudioFile?
    public let sampleRate: Double

    public init(filePath: String) throws {
        let url = URL(fileURLWithPath: filePath)
        let file = try AVAudioFile(forReading: url)
        self.fileURL = url
        self.audioFile = file
        self.sampleRate = file.processingFormat.sampleRate
    }

    public func startStreaming(_ onSample: (@Sendable (Float) -> Void)?) throws {
        guard let file = audioFile else {
            throw NSError(
                domain: "FileStreamer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Streamer already stopped"]
            )
        }
        file.framePosition = 0
        let format = file.processingFormat
        let chunkFrames: AVAudioFrameCount = 32768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw NSError(
                domain: "FileStreamer",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate audio buffer"]
            )
        }
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            deliver(buffer, onSample)
        }
    }

    private func deliver(_ buffer: AVAudioPCMBuffer, _ onSample: (@Sendable (Float) -> Void)?) {
        guard let channelData = buffer.floatChannelData else { return }
        let channels = Int(buffer.format.channelCount)
        for frame in 0..<Int(buffer.frameLength) {
            var sum: Float = 0
            for channel in 0..<channels {
                sum += channelData[channel][frame]
            }
            onSample?(sum / Float(channels))
        }
    }

    public func stopStreaming() {
        audioFile = nil
    }
}

#else

/// Streams samples from a WAV file (WAV only on platforms without
/// AVFoundation).
public final class FileStreamer: AudioStreamSource {
    private let wav: WavFile
    public var sampleRate: Double { wav.sampleRate }

    public init(filePath: String) throws {
        self.wav = try WavFile(contentsOf: URL(fileURLWithPath: filePath))
    }

    public func startStreaming(_ onSample: (@Sendable (Float) -> Void)?) throws {
        for sample in wav.samples {
            onSample?(sample)
        }
    }

    public func stopStreaming() {}
}

#endif

#if os(macOS)
import AVFoundation
import AudioToolbox
import CoreAudio

/// Streams live samples from an audio input device. Multi-channel input is
/// averaged down to mono.
public final class MacOSDeviceStreamer: AudioStreamSource {
    private let deviceID: AudioDeviceID?
    private var audioEngine: AVAudioEngine?
    public private(set) var sampleRate: Double = 0

    /// - Parameter deviceID: CoreAudio device to capture from, or nil for
    ///   the system default input device.
    public init(deviceID: AudioDeviceID? = nil) {
        self.deviceID = deviceID
    }

    public func startStreaming(_ onSample: (@Sendable (Float) -> Void)?) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        if let deviceID {
            guard let audioUnit = inputNode.audioUnit else {
                throw NSError(
                    domain: "MacOSDeviceStreamer",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Input node has no audio unit"]
                )
            }
            var device = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &device,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else {
                throw NSError(
                    domain: "MacOSDeviceStreamer",
                    code: Int(status),
                    userInfo: [NSLocalizedDescriptionKey: "Failed to select device \(deviceID)"]
                )
            }
        }

        let format = inputNode.inputFormat(forBus: 0)
        sampleRate = format.sampleRate

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let channels = Int(buffer.format.channelCount)
            guard channels > 0 else { return }
            for frame in 0..<Int(buffer.frameLength) {
                var sum: Float = 0
                for channel in 0..<channels {
                    sum += channelData[channel][frame]
                }
                onSample?(sum / Float(channels))
            }
        }

        try engine.start()
        self.audioEngine = engine
    }

    public func stopStreaming() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }
}
#endif
