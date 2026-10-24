// Renders Chorden's instrument samples from a General MIDI SoundFont.
// Usage: swift tools/render_samples.swift <MuseScore_General.sf2> <out dir>
//
// Each instrument is played note by note through Apple's sampler in offline mode, every third
// semitone across its range, and saved as mono AAC. Chorden pitch-shifts between these roots.
import AVFoundation

struct SampleSet {
    let id: String
    let program: UInt8
    let low: Int, high: Int
    /// Seconds the key is held, then seconds of release that are kept.
    let hold: Double, tail: Double
    /// Semitones between recorded notes (1 = every note, no pitch shifting at all).
    var step = 3
    /// Velocity layers: (MIDI velocity, file suffix). A soft layer is saved as e.g. "60s.m4a".
    var layers: [(UInt8, String)] = [(112, "")]
}

let sets = [
    // The acoustic guitar in full: every note from low E to the 24th fret, played hard and soft.
    SampleSet(id: "steel", program: 25, low: 40, high: 88, hold: 3.6, tail: 0.3, step: 1, layers: [(118, ""), (68, "s")]),
    SampleSet(id: "nylon", program: 24, low: 40, high: 85, hold: 3.2, tail: 0.3),
    SampleSet(id: "electric", program: 27, low: 40, high: 88, hold: 3.6, tail: 0.3),
    SampleSet(id: "bass", program: 33, low: 28, high: 67, hold: 3.4, tail: 0.3),
    SampleSet(id: "violin", program: 40, low: 55, high: 94, hold: 4.6, tail: 0.4),
    SampleSet(id: "viola", program: 41, low: 48, high: 87, hold: 4.6, tail: 0.4),
    SampleSet(id: "cello", program: 42, low: 36, high: 76, hold: 4.6, tail: 0.4),
    SampleSet(id: "contrabass", program: 43, low: 28, high: 64, hold: 4.6, tail: 0.4),
    SampleSet(id: "banjo", program: 105, low: 48, high: 84, hold: 2.2, tail: 0.2),
    SampleSet(id: "piano", program: 0, low: 21, high: 108, hold: 4.0, tail: 0.4),
]

let bank = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
// Optional third argument: render only these sets (comma-separated ids).
let only = CommandLine.arguments.count > 3 ? Set(CommandLine.arguments[3].split(separator: ",").map(String.init)) : nil
let rate = 44100.0
let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!

for set in sets where only?.contains(set.id) ?? true {
    let dir = outDir.appendingPathComponent(set.id)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var roots = Array(stride(from: set.low, through: set.high, by: set.step))
    if roots.last != set.high { roots.append(set.high) }
    var rendered: [(String, [Float])] = []

    for (velocity, suffix) in set.layers {
    for midi in roots {
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try sampler.loadSoundBankInstrument(at: bank, program: set.program,
                                            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: 0)
        try engine.start()
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
        var mono: [Float] = []
        func render(_ seconds: Double) throws {
            var left = Int(seconds * rate)
            while left > 0 {
                let n = AVAudioFrameCount(min(4096, left))
                _ = try engine.renderOffline(n, to: buffer)
                let l = buffer.floatChannelData![0], r = buffer.floatChannelData![1]
                for i in 0..<Int(buffer.frameLength) { mono.append((l[i] + r[i]) * 0.5) }
                left -= Int(n)
            }
        }
        try render(0.05) // let the sampler settle
        mono.removeAll()
        sampler.startNote(UInt8(midi), withVelocity: velocity, onChannel: 0)
        try render(set.hold)
        sampler.stopNote(UInt8(midi), onChannel: 0)
        try render(set.tail)
        engine.stop()
        // Trim the silent lead-in so the attack starts at sample 0.
        let peak = mono.map(abs).max() ?? 0
        let start = mono.firstIndex { abs($0) > peak * 0.01 } ?? 0
        rendered.append(("\(midi)\(suffix)", Array(mono[max(0, start - 16)...])))
    }
    }

    // One gain for the whole instrument keeps its natural balance from low to high, and soft below hard.
    // It's set by the loudest note, with headroom for the AAC encoder, so no recording is ever clipped.
    let loudest = rendered.map { $0.1.map(abs).max() ?? 0 }.max() ?? 1
    let gain = 0.85 / max(loudest, 1e-6)
    let monoFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
    for (name, data) in rendered {
        let n = data.count
        let fade = Int(rate * 0.05)
        let pcm = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(n))!
        pcm.frameLength = AVAudioFrameCount(n)
        for i in 0..<n {
            let f: Float = i > n - fade ? Float(n - i) / Float(fade) : 1
            pcm.floatChannelData![0][i] = data[i] * gain * f
        }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96000]
        let file = try AVAudioFile(forWriting: dir.appendingPathComponent("\(name).m4a"), settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: pcm)
    }
    print("✓ \(set.id): \(rendered.count) recordings")
}
