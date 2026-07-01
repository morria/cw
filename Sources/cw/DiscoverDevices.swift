import Foundation

/// An audio input device available for capture.
public struct AudioInputDevice {
    public let id: UInt32
    public let name: String
    public let inputChannelCount: Int
}

#if canImport(CoreAudio) && os(macOS)
import CoreAudio

/// Returns the audio devices that have at least one input channel.
public func audioInputDevices() -> [AudioInputDevice] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
    ) == noErr else { return [] }

    let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs
    ) == noErr else { return [] }

    var devices: [AudioInputDevice] = []
    for deviceID in deviceIDs {
        let channels = inputChannelCount(of: deviceID)
        guard channels > 0 else { continue }
        devices.append(
            AudioInputDevice(
                id: deviceID,
                name: deviceName(of: deviceID) ?? "Unknown device",
                inputChannelCount: channels
            )
        )
    }
    return devices
}

private func deviceName(of deviceID: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceNameCFString,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &name) { pointer in
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
    }
    guard status == noErr else { return nil }
    return name as String
}

private func inputChannelCount(of deviceID: AudioDeviceID) -> Int {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
          size > 0
    else { return 0 }

    let bufferListPointer = UnsafeMutableRawPointer.allocate(
        byteCount: Int(size),
        alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { bufferListPointer.deallocate() }

    guard AudioObjectGetPropertyData(
        deviceID, &address, 0, nil, &size,
        bufferListPointer
    ) == noErr else { return 0 }

    let bufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
    let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
    return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
}

#else

/// Returns the audio devices that have at least one input channel.
/// Live capture is only supported on macOS; other platforms return [].
public func audioInputDevices() -> [AudioInputDevice] {
    []
}

#endif

/// Prints the available audio input devices to standard output.
public func listAudioDevices() {
    let devices = audioInputDevices()
    if devices.isEmpty {
        print("No audio input devices found (live capture is only supported on macOS).")
        return
    }
    for device in devices {
        print("Device \(device.id): \(device.name) (\(device.inputChannelCount) input channel\(device.inputChannelCount == 1 ? "" : "s"))")
    }
}
