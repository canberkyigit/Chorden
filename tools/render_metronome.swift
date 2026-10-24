// Renders Chorden's metronome sounds into Resources/Samples/metronome.
// Usage: swiftc -O tools/render_metronome.swift -o /tmp/render_metronome
//        /tmp/render_metronome <MuseScore_General.sf2> Resources/Samples/metronome
//
// Every sound is a real one-shot from the General MIDI percussion kit (bank 128, "Standard"), struck through
// Apple's sampler in offline mode, except the electronic beep, which is synthesized. Each hit is trimmed so its
// attack starts at sample 0 (the metronome schedules it to the sample), faded out where it has died away, and
// set to the same perceived loudness as all the others, then saved as 16-bit mono WAV at 48 kHz.
import AVFoundation
import Accelerate

let bank = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
let rate = 48000.0

/// Loudness the downbeat sounds at, and the other beats a little below it (as the app's older clicks did).
let accentPhon = 80.0
let beatPhon = 78.3

// MARK: - Sources

/// One drum struck hard (velocity only scales this kit's level), optionally retuned in cents.
func strike(_ note: UInt8, cents: Float = 0) throws -> [Float] {
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
    let engine = AVAudioEngine()
    let sampler = AVAudioUnitSampler()
    engine.attach(sampler)
    engine.connect(sampler, to: engine.mainMixerNode, format: format)
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    try sampler.loadSoundBankInstrument(at: bank, program: 0,
                                        bankMSB: UInt8(kAUSampler_DefaultPercussionBankMSB), bankLSB: 0)
    sampler.globalTuning = cents
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
    sampler.startNote(note, withVelocity: 127, onChannel: 9)
    try render(1.0)
    engine.stop()
    return mono
}

/// The electronic metronome's beep: a tone with a little 2nd and 3rd harmonic, held briefly, then let go.
func beep(_ frequency: Double) -> [Float] {
    (0..<Int(rate * 0.1)).map { i in
        let t = Double(i) / rate
        let attack = t < 0.001 ? 0.5 - 0.5 * cos(Double.pi * t / 0.001) : 1
        let release = t < 0.03 ? 1 : exp(-(t - 0.03) / 0.012)
        let w = 2 * Double.pi * frequency * t
        return Float((sin(w) + 0.2 * sin(2 * w) + 0.1 * sin(3 * w)) * attack * release)
    }
}

/// Starts the hit at its attack and ends it where it has died away (60 dB down) or at `fadeAt`.
func trim(_ x: [Float], fadeAt: Double? = nil, fade: Double = 0.03) -> [Float] {
    let peak = x.map(abs).max() ?? 0
    guard peak > 0, let first = x.firstIndex(where: { abs($0) > peak * 0.02 }),
          let last = x.lastIndex(where: { abs($0) > peak * 0.001 }) else { return x }
    let lead = Int(rate * 0.00025)
    let start = max(0, first - lead)
    var end = last + 1
    if let f = fadeAt { end = min(end, start + Int((f + fade) * rate)) }
    var y = Array(x[start..<end])
    for i in 0..<min(first - start, y.count) { y[i] *= Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(first - start))) }
    let n = min(y.count, Int(fade * rate))
    for i in 0..<n { y[y.count - n + i] *= Float(0.5 + 0.5 * cos(Double.pi * Double(i + 1) / Double(n))) }
    return y
}

// MARK: - Loudness

/// Perceived loudness of a short hit, in phon: a Zwicker-style model (outer/middle-ear weighting, excitation
/// spread along the Bark scale, specific loudness ∝ E^0.23) over its first 100 ms, the ear's integration time
/// for short sounds. Unlike plain K-weighted energy it hears that a pure tone (the beep, a bell) is softer than
/// a wide-band hit (a hi-hat) of the same energy. A full-scale sine is taken as 90 dB SPL.
func phon(_ x: [Float], fullScale: Double = 90) -> Double {
    let w = Int(rate * 0.1), n = 8192
    var re = [Float](repeating: 0, count: n), im = [Float](repeating: 0, count: n)
    for i in 0..<min(w, x.count) { re[i] = x[i] }
    let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .FORWARD)!
    var outR = [Float](repeating: 0, count: n), outI = [Float](repeating: 0, count: n)
    vDSP_DFT_Execute(setup, re, im, &outR, &outI)
    vDSP_DFT_DestroySetup(setup)
    let bark = { (f: Double) in 13 * atan(0.00076 * f) + 3.5 * atan(pow(f / 7500, 2)) }
    let step = 0.25, bands = 100
    var e = [Double](repeating: 0, count: bands)
    for k in 1..<(n / 2) {
        let f = Double(k) * rate / Double(n)
        guard f >= 20, f <= 20000 else { continue }
        let p = 2 * Double(outR[k] * outR[k] + outI[k] * outI[k]) / Double(n) / Double(w) / 0.5
        let khz = f / 1000
        let ear = -2.184 * pow(khz, -0.8) + 6.5 * exp(-0.6 * pow(khz - 3.3, 2)) - 0.001 * pow(khz, 3.6)
        e[min(bands - 1, Int(bark(f) / step))] += p * pow(10, (ear + fullScale) / 10)
    }
    var spread = [Double](repeating: 0, count: bands)
    for b in 0..<bands where e[b] > 0 {
        let z = (Double(b) + 0.5) * step
        let upper = max(4, 24 + 230 / (1960 * (z + 0.53) / (26.28 - z)) - 0.2 * 10 * log10(e[b]))
        for j in 0..<bands {
            let dz = Double(j - b) * step
            spread[j] += e[b] * pow(10, -(dz < 0 ? -27 * dz : upper * dz) / 10)
        }
    }
    var sone = 0.0
    for j in 0..<bands {
        let z = (Double(j) + 0.5) * step
        let threshold = pow(10, 0.4 * 3.64 * pow(1.96 * (z + 0.53) / (26.28 - z), -0.8) / 10)
        sone += max(0, 0.08 * pow(threshold, 0.23) * (pow(0.5 + 0.5 * spread[j] / threshold, 0.23) - 1)) * step
    }
    return sone >= 1 ? 40 + 33.22 * log10(sone) : 40 * pow(sone + 0.0005, 0.35)
}

/// The gain that brings `x` to `target` phon.
func gain(_ x: [Float], to target: Double) -> Float {
    var lo = -40.0, hi = 40.0
    for _ in 0..<40 {
        let mid = (lo + hi) / 2
        if phon(x.map { $0 * Float(pow(10, mid / 20)) }) < target { lo = mid } else { hi = mid }
    }
    return Float(pow(10, (lo + hi) / 40))
}

func scaled(_ x: [Float], to target: Double) -> [Float] {
    let g = gain(x, to: target)
    return x.map { $0 * g }
}

// MARK: - The kit

var hits: [(String, [Float])] = []
// Classic: the tick of a clockwork metronome (GM 33, Metronome Click) on every beat; on one, its bell
// (GM 34, Metronome Bell) rings with the same tick, as on the real thing, a little louder than other downbeats.
let tick = scaled(trim(try strike(33)), to: beatPhon)
let bell = trim(try strike(34), fadeAt: 0.25, fade: 0.18)
var lo: Float = 0, hi: Float = 4
for _ in 0..<40 {
    let mid = (lo + hi) / 2
    let mix = (0..<bell.count).map { ($0 < tick.count ? tick[$0] : 0) + bell[$0] * mid }
    if phon(mix) < beatPhon + 5 { lo = mid } else { hi = mid }
}
hits.append(("classic-accent", (0..<bell.count).map { ($0 < tick.count ? tick[$0] : 0) + bell[$0] * lo }))
hits.append(("classic-beat", tick))
// Woodblock: the high block (GM 76) on one, the low block (GM 77) a fourth below on the other beats.
hits.append(("wood-accent", scaled(trim(try strike(76)), to: accentPhon)))
hits.append(("wood-beat", scaled(trim(try strike(77)), to: beatPhon)))
// Cowbell (GM 56); on one a smaller bell, a fourth higher, the way the kit's own high wood block is made.
hits.append(("cowbell-accent", scaled(trim(try strike(56, cents: 500)), to: accentPhon)))
hits.append(("cowbell-beat", scaled(trim(try strike(56)), to: beatPhon)))
// Hi-hat: on one the hats are opened (GM 46, half-open) and closed again by the foot; then closed hits (GM 42).
hits.append(("hihat-accent", scaled(trim(try strike(46), fadeAt: 0.14, fade: 0.04), to: accentPhon)))
hits.append(("hihat-beat", scaled(trim(try strike(42)), to: beatPhon)))
// Beep: an electronic metronome, A6 on one and E6 (a fourth below) on the other beats.
hits.append(("beep-accent", scaled(trim(beep(1760)), to: accentPhon)))
hits.append(("beep-beat", scaled(trim(beep(1318.5)), to: beatPhon)))

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                               AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
for (name, data) in hits {
    let peak = data.map(abs).max() ?? 0
    precondition(peak < 0.95, "\(name) would clip")
    let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count))!
    pcm.frameLength = AVAudioFrameCount(data.count)
    for i in data.indices { pcm.floatChannelData![0][i] = data[i] }
    let file = try AVAudioFile(forWriting: outDir.appendingPathComponent("\(name).wav"), settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    try file.write(from: pcm)
    print(String(format: "✓ %-15@ %4.0f ms  peak %5.1f dBFS  %4.1f phon", name as NSString,
                 Double(data.count) / rate * 1000, 20 * log10(peak), phon(data)))
}
