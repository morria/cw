import Foundation

#if canImport(AVFoundation)
import AVFoundation

public protocol AudioStreamSource {
    func startStreaming(_ onSample: ((Float) -> Void)?) throws
    func stopStreaming()
}

public class FileStreamer: AudioStreamSource {
    private var audioFile: AVAudioFile?
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
        let file = try AVAudioFile(forReading: fileURL)
        self.audioFile = file
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        try file.read(into: buffer)

        processAudioBuffer(buffer, onSample)
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, _ onSample: ((Float) -> Void)?) {
        let frameLength = Int(buffer.frameLength)
        guard let floatChannelData = buffer.floatChannelData else { return }

        for i in 0..<frameLength {
            let sample = floatChannelData.pointee[i]
            onSample?(sample)
        }
    }

    public func stopStreaming() {
        audioFile = nil
    }
}

#if os(macOS)
public class MacOSDeviceStreamer: AudioStreamSource {
    private let deviceID: String
    private var audioEngine: AVAudioEngine?

    public init(deviceID: String) {
        self.deviceID = deviceID
    }

    public func startStreaming(_ onSample: ((Float) -> Void)?) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false) else {
            throw NSError(
                domain: "MacOSDeviceStreamer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"]
            )
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            let floatData = buffer.floatChannelData?[0]
            let frameCount = Int(buffer.frameLength)
            for i in 0..<frameCount {
                onSample?(floatData?[i] ?? 0.0)
            }
        }

        try engine.start()
        self.audioEngine = engine
    }

    public func stopStreaming() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }
}
#endif

#else
public protocol AudioStreamSource {
    func startStreaming(_ onSample: ((Float) -> Void)?) throws
    func stopStreaming()
}

public class FileStreamer: AudioStreamSource {
    public init(filePath: String) throws {
        throw NSError(
            domain: "FileStreamer",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "AVFoundation unavailable on this platform"]
        )
    }

    public func startStreaming(_ onSample: ((Float) -> Void)?) throws {}
    public func stopStreaming() {}
}
#endif
