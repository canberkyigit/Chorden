// Renders the progression player's drum kit into Resources/Samples/drums.
// Usage: swiftc -O tools/render_drums.swift -o /tmp/render_drums
//        /tmp/render_drums <MuseScore_General.sf2> Resources/Samples/drums
//
// Every drum is a real one-shot from the General MIDI percussion kit (bank 128, "Standard"), struck through
// Apple's sampler in offline mode, like the metronome's hits (tools/render_metronome.swift). Kick, snare and
// hi-hat get a second, soft layer: the kit's own low-velocity zones (darker filter, shorter ring), so a ghost
// note sounds played softly rather than turned down. Each hit is trimmed so its attack starts at sample 0 (the
// sequencer schedules it to the sample), faded out where it has died away, set to its place in a balanced kit
// by perceived loudness (kick and snare up front, cymbals and percussion lower), and saved as 16-bit mono WAV
// at 48 kHz. The app pans them and scales them by velocity; `Synth`'s `DrumSamples` reads these names.
import AVFoundation
import Accelerate

let bank = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
let rate = 48000.0

/// The velocity the soft layers stand for: the app plays a soft layer at `velocity / softVelocity` gain, the
/// hard layer at `velocity`, so the two meet in level where it switches between them.
let softVelocity = 0.35

// MARK: - Sources

/// One drum struck at a MIDI velocity, folded to mono.
func strike(_ note: UInt8, velocity: UInt8 = 127, seconds: Double = 2) throws -> [Float] {
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
    let engine = AVAudioEngine()
    let sampler = AVAudioUnitSampler()
    engine.attach(sampler)
    engine.connect(sampler, to: engine.mainMixerNode, format: format)
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    try sampler.loadSoundBankInstrument(at: bank, program: 0,
                                        bankMSB: UInt8(kAUSampler_DefaultPercussionBankMSB), bankLSB: 0)
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
    sampler.startNote(note, withVelocity: velocity, onChannel: 9)
    try render(seconds)
    engine.stop()
    return mono
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

/// A gentle one-pole low-pass: a stick barely touching the hats excites less of the cymbal's top end.
func soften(_ x: [Float], cutoff: Double) -> [Float] {
    let a = Float(exp(-2 * Double.pi * cutoff / rate))
    var y: Float = 0
    return x.map { y = $0 * (1 - a) + y * a; return y }
}

// MARK: - Loudness (as in render_metronome.swift)

/// Perceived loudness of a short hit, in phon: a Zwicker-style model over its first 100 ms.
/// A full-scale sine is taken as 90 dB SPL.
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

/// `x` at `target` phon, its first transient limited if it would peak over `ceiling` (then brought back up to
/// the target, a few times, since limiting takes a little loudness off).
func scaled(_ x: [Float], to target: Double) -> [Float] {
    var y = x
    for _ in 0..<4 {
        let g = gain(y, to: target)
        y = limited(y.map { $0 * g })
    }
    return y
}

/// Spectral centroid of the first 100 ms, in Hz: how bright a hit is (printed to show the soft layers are darker).
func centroid(_ x: [Float]) -> Double {
    let n = 8192
    var re = [Float](repeating: 0, count: n), im = [Float](repeating: 0, count: n)
    for i in 0..<min(Int(rate * 0.1), x.count, n) { re[i] = x[i] }
    let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .FORWARD)!
    var outR = [Float](repeating: 0, count: n), outI = [Float](repeating: 0, count: n)
    vDSP_DFT_Execute(setup, re, im, &outR, &outI)
    vDSP_DFT_DestroySetup(setup)
    var num = 0.0, den = 0.0
    for k in 1..<(n / 2) {
        let m = Double(hypot(outR[k], outI[k]))
        num += m * Double(k) * rate / Double(n); den += m
    }
    return den > 0 ? num / den : 0
}

// MARK: - The kit

/// Loudness of each drum struck hard (velocity 1 in the app), in phon. Kick and snare lead; rim and clap sit
/// just under them; toms a little under; cymbals and shaker well below, as a drummer balances a kit.
let level: [String: Double] = [
    "kick": 87, "snare": 91, "rim": 85, "clap": 86, "tom": 85, "tommid": 85, "tomhigh": 84,
    "hat": 81, "openhat": 82, "ride": 81, "crash": 83, "shaker": 74,
]

/// The loudest a hit may peak, leaving the mixer room for the chord on top of it.
let ceiling: Float = 0.75

/// Holds a hit's first transient under `ceiling` the way a drum limiter does: the gain dips over a 1 ms lead-in
/// and recovers over 40 ms, so the body of the hit is untouched and nothing is clipped.
func limited(_ x: [Float]) -> [Float] {
    var g = x.map { min(1, ceiling / max(abs($0), 1e-9)) }
    let release = Float(1 - exp(-1 / (0.04 * rate))), attack = Float(1 / (0.001 * rate))
    for i in 1..<g.count { g[i] = min(g[i], g[i - 1] + (1 - g[i - 1]) * release) }
    for i in stride(from: g.count - 2, through: 0, by: -1) { g[i] = min(g[i], g[i + 1] + attack) }
    return zip(x, g).map { $0 * $1 }
}

/// A hard hit and its soft layer, at the loudness the hard one would have at `softVelocity`.
func layered(_ name: String, hard: [Float], soft: [Float]) -> [(String, [Float])] {
    let h = scaled(hard, to: level[name]!)
    let target = phon(h.map { $0 * Float(softVelocity) })
    return [(name, h), (name + "-soft", scaled(soft, to: target))]
}

var hits: [(String, [Float])] = []
// Kick (GM 36, Bass Drum 1) and snare (GM 38, Acoustic Snare): the soft layer is the kit's lowest-velocity zone,
// filtered darker with a shorter ring.
hits += layered("kick", hard: trim(try strike(36), fadeAt: 0.5, fade: 0.1),
                soft: trim(try strike(36, velocity: 56), fadeAt: 0.5, fade: 0.1))
hits += layered("snare", hard: trim(try strike(38), fadeAt: 0.6, fade: 0.15),
                soft: trim(try strike(38, velocity: 56), fadeAt: 0.45, fade: 0.12))
// Closed hi-hat (GM 42): the kit has one zone, so a light tap is the same hit with its top end rolled off.
let hat = trim(try strike(42), fadeAt: 0.25, fade: 0.08)
hits += layered("hat", hard: hat, soft: soften(trim(try strike(42, velocity: 56), fadeAt: 0.2, fade: 0.08), cutoff: 5000))
// Open hat (GM 46, half-open): left to ring; the next closed hat chokes it in the app.
hits.append(("openhat", scaled(trim(try strike(46), fadeAt: 0.9, fade: 0.3), to: level["openhat"]!)))
// Side stick (GM 37), hand clap (GM 39), maracas (GM 70) for the bossa shaker, low tom (GM 45), ride (GM 51).
hits.append(("rim", scaled(trim(try strike(37), fadeAt: 0.3, fade: 0.08), to: level["rim"]!)))
hits.append(("clap", scaled(trim(try strike(39), fadeAt: 0.4, fade: 0.1), to: level["clap"]!)))
hits.append(("shaker", scaled(trim(try strike(70), fadeAt: 0.15, fade: 0.04), to: level["shaker"]!)))
hits.append(("tom", scaled(trim(try strike(45), fadeAt: 0.8, fade: 0.25), to: level["tom"]!)))
hits.append(("ride", scaled(trim(try strike(51, seconds: 3), fadeAt: 1.6, fade: 0.6), to: level["ride"]!)))
// For fills and the top of the loop: low-mid tom (GM 47), high tom (GM 50) and crash cymbal (GM 49).
hits.append(("tommid", scaled(trim(try strike(47), fadeAt: 0.7, fade: 0.25), to: level["tommid"]!)))
hits.append(("tomhigh", scaled(trim(try strike(50), fadeAt: 0.6, fade: 0.2), to: level["tomhigh"]!)))
hits.append(("crash", scaled(trim(try strike(49, seconds: 4), fadeAt: 2.6, fade: 1.0), to: level["crash"]!)))

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                               AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
for (name, data) in hits {
    let peak = data.map(abs).max() ?? 0
    precondition(peak <= ceiling + 0.001, "\(name) would clip")
    let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count))!
    pcm.frameLength = AVAudioFrameCount(data.count)
    for i in data.indices { pcm.floatChannelData![0][i] = data[i] }
    let file = try AVAudioFile(forWriting: outDir.appendingPathComponent("\(name).wav"), settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    try file.write(from: pcm)
    print(String(format: "✓ %-12@ %5.0f ms  peak %5.1f dBFS  %4.1f phon  centroid %5.0f Hz", name as NSString,
                 Double(data.count) / rate * 1000, 20 * log10(peak), phon(data), centroid(data)))
}
