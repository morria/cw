# cw — a Morse code (CW) decoder in Swift

A Swift package that decodes on/off-keyed Morse (CW) audio into text. It
automatically finds the carrier tone, adapts to the sender's speed, and holds
up well in noise. Ships as a library (`cw`) plus a command-line decoder
(`listen`).

## Features

- **Automatic tone detection** — two-pass Goertzel scan (250–1200 Hz by
  default) with a subharmonic guard so distorted tones don't lock onto a
  harmonic.
- **Noise-robust envelope** — the signal is demodulated with a sliding
  Goertzel filter *at the detected frequency*, so broadband noise is largely
  rejected before keying is measured. Decodes cleanly at 5 dB broadband SNR
  and below.
- **Automatic speed tracking** — dot length is estimated by clustering mark
  durations; tested from 5 to 40 WPM with no configuration.
- **Adaptive thresholding** — two-means clustering of the envelope with
  hysteresis, plus dot-relative run cleanup that repairs noise-chopped dashes
  and noise-bridged gaps.
- **Letters, digits, and punctuation** (`.,?'!/()&:;=+-_"$@`).
- **Cross-platform** — the decoder and WAV reader are pure Swift and run on
  macOS and Linux; live audio capture is available on macOS.

## Usage

### Library

```swift
import cw

// Decode a WAV recording
let wav = try WavFile(contentsOf: URL(fileURLWithPath: "qso.wav"))
let decoder = CWDecoder(sampleRate: wav.sampleRate,
                        bufferSeconds: Double(wav.samples.count) / wav.sampleRate)
decoder.feed(samples: wav.samples)
let text = decoder.decodeBuffer()          // "CQ CQ CQ DE W2ASM K"
let tone = decoder.estimatedFrequency      // 600.0 (Hz)
let speed = decoder.estimatedWPM           // 12.0
```

For live use, keep feeding samples as they arrive and call
`decodeBuffer()` (or `decodeBuffer(lastSeconds:)`) whenever you want the
current text. The decoder keeps a rolling window of recent audio
(`bufferSeconds`, default 120 s).

### Command line

```console
$ swift run listen path/to/recording.wav
tone: 600 Hz, speed: 12 WPM
CQ CQ CQ DE W2ASM K

$ swift run listen --devices          # list audio input devices (macOS)
$ swift run listen --live             # decode live from the default input (macOS)
$ swift run listen --live 42          # decode live from device 42 (macOS)
```

## How it works

1. **Tone search.** Non-overlapping 1024-sample windows are ranked by energy;
   the strongest (key-down) windows are scanned with the generalized Goertzel
   algorithm — coarse at the window's natural resolution, then fine at 1 Hz.
   If a subharmonic of the winner carries comparable power, it wins instead
   (harmonics of a distorted tone can out-power the fundamental).
2. **Envelope.** A 10 ms Goertzel window slides in 2.5 ms hops at the detected
   frequency, producing a tone-selective envelope that ignores most noise.
3. **Segmentation.** The envelope is split into mark/space runs using
   thresholds derived from two-means clustering, with hysteresis so a mark
   must rise well above the floor to start and fall well below to end.
4. **Timing.** Mark runs are clustered into dot/dash groups to estimate the
   dot length; runs shorter than a third of a dot are folded into their
   neighbours and the estimate is refined. Elements and gaps are then
   classified against standard Morse timing (dash > 2 dots; letter gap >
   2 dots; word gap > 5 dots).

## Development

```console
$ swift build          # or: make build
$ swift test           # or: make test
```

The test suite decodes 18 reference recordings (6/12/24 WPM × 300/600/1000 Hz
× 10/30 dB SNR), re-noises the clean ones down to 5 dB, and cross-validates
against synthesized CW from 5 to 40 WPM, including punctuation and degenerate
inputs (silence, pure noise).
