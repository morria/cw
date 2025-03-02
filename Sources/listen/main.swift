import Foundation
import cw

listAudioDevices()

let fileName = "Tests/samples/sample_12_600_10_CQ_CQ_CQ_DE_W2ASM_K.wav"

do {
    // let stream = try MacOSDeviceStreamer(deviceID: "1")
    let stream = try FileStreamer(filePath: fileName)
    try stream.startStreaming { sample in
        print("Sample: \(sample)")
    }
    // RunLoop.current.run()
    stream.stopStreaming()
} catch {
    print("Error: \(error)")
}
