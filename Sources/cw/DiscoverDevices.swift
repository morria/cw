import Foundation

/// Print a list of available input audio devices.  The real implementation is
/// only available on macOS where CoreAudio can be used.  On other platforms this
/// function simply informs the user that the operation is unsupported.
#if os(macOS)
import CoreAudio

public func listAudioDevices() {
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

    for (index, device) in devices.enumerated() {
        var name: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMaster
        )
        AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name)
        let deviceName = name as String
        print("Device \(index): \(deviceName)")
    }
}

#else

public func listAudioDevices() {
    print("Audio device listing is not supported on this platform")
}

#endif

