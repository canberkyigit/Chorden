// Turns single-note recordings (any format Core Audio reads) into a Chorden sample set.
// Usage: swift tools/import_samples.swift <out dir> <set id> <midi>=<file> [<midi>=<file> ...]
//
// Each note is mixed to mono, trimmed to its attack, matched in loudness to the others (RMS of the
// first 300 ms), faded out at the end and saved as mono AAC named by its MIDI note. One gain for the
// whole set then puts the loudest peak at −1.4 dBFS, so nothing clips in the encoder. Run
// tools/tune_samples.swift afterwards to measure each note's exact pitch into tuning.json.
import AVFoundation

let args = CommandLine.arguments
let dir = URL(fileURLWithPath: args[1]).appendingPathComponent(args[2])
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

var notes: [(name: String, data: [Float], rate: Double)] = []
for pair in args.dropFirst(3) {
    let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: parts[1]))
    let rate = file.processingFormat.sampleRate
    let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buf)
    let n = Int(buf.frameLength), channels = Int(buf.format.channelCount)
    var mono = [Float](repeating: 0, count: n)
    for c in 0..<channels { let p = buf.floatChannelData![c]; for i in 0..<n { mono[i] += p[i] / Float(channels) } }
    // Remove any DC offset, then start 2 ms before the attack.
    let mean = mono.reduce(0, +) / Float(max(n, 1))
    mono = mono.map { $0 - mean }
    let peak = mono.map(abs).max() ?? 0
    let onset = mono.firstIndex { abs($0) > peak * 0.05 } ?? 0
    var data = Array(mono[max(0, onset - Int(rate * 0.002))...])
    // A short fade-in over those 2 ms, so the cut can't click.
    let fadeIn = min(data.count, Int(rate * 0.002))
    for i in 0..<fadeIn { data[i] *= Float(i) / Float(fadeIn) }
    // Equal loudness: RMS of the first 300 ms.
    let window = data.prefix(Int(rate * 0.3))
    let rms = sqrt(window.reduce(0) { $0 + $1 * $1 } / Float(max(window.count, 1)))
    data = data.map { $0 / max(rms, 1e-6) }
    notes.append((parts[0], data, rate))
}

let loudest = notes.map { $0.data.map(abs).max() ?? 0 }.max() ?? 1
let gain = 0.85 / max(loudest, 1e-6)
for note in notes {
    let n = note.data.count
    let fade = Int(note.rate * 0.15)
    let format = AVAudioFormat(standardFormatWithSampleRate: note.rate, channels: 1)!
    let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
    pcm.frameLength = AVAudioFrameCount(n)
    for i in 0..<n {
        let f: Float = i > n - fade ? Float(n - i) / Float(fade) : 1
        pcm.floatChannelData![0][i] = note.data[i] * gain * f
    }
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: note.rate,
                                   AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96000]
    let file = try AVAudioFile(forWriting: dir.appendingPathComponent("\(note.name).m4a"), settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    try file.write(from: pcm)
}
print("✓ \(args[2]): \(notes.count) recordings, gain \(String(format: "%.1f", 20 * log10(gain))) dB")
