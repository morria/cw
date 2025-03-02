import CoreAudio
import AudioToolbox

class AudioStreamer: NSObject {
    var audioQueue: AudioQueueRef?
    var isStreaming = false

    func startStreaming(deviceIndex: Int) {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMaster
        )
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)
        
        guard deviceIndex < devices.count else {
            print("Invalid device index")
            return
        }
        
        _ = devices[deviceIndex] // Use underscore to ignore unused variable warning
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: 44100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        
        AudioQueueNewInput(&streamDescription, audioQueueCallback, Unmanaged.passUnretained(self).toOpaque(), nil, nil, 0, &audioQueue)
        AudioQueueStart(audioQueue!, nil)
        isStreaming = true
        print("Streaming audio... Press Ctrl+C to stop.")
    }
}

func audioQueueCallback(
    inUserData: UnsafeMutableRawPointer?,
    inAQ: AudioQueueRef,
    inBuffer: AudioQueueBufferRef,
    inStartTime: UnsafePointer<AudioTimeStamp>,
    inNumberPacketDescriptions: UInt32,
    inPacketDescs: UnsafePointer<AudioStreamPacketDescription>?
) {
    // Handle audio buffer
}

