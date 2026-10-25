import Foundation

/// How a plucked instrument sounds: string losses, pick, doubled courses, body and room.
struct Timbre: Equatable {
    var id: String
    /// Decay time (−60 dB) of a 220 Hz note; other pitches scale with √(220/f).
    var t60: Double
    /// Excitation brightness 0…1 (pick vs. finger, steel vs. nylon).
    var brightness: Double
    /// Loop low-pass weight: 0.5 = dark (classic Karplus–Strong), lower = brighter, longer highs.
    var damping: Double
    /// Pluck point as a fraction of the string from the bridge; it notches out harmonics.
    var pick: Double
    /// Doubled courses (mandolin, 12-string, bağlama): the second string's detune in cents.
    var course: Double?
    /// Body modes: frequency, Q, gain.
    var body: [Mode]
    var dry: Double
    var reverb: Double
    /// Magnetic pickup + amp instead of a wooden body.
    var electric = false
    var gain: Double
    /// Wooden body heard through the string (commuted synthesis); replaces `body` filters when set.
    var resonator: Resonator? = nil
    /// Played with a bow (sustained) rather than plucked.
    var bowed = false
    /// Recorded set in Resources/Samples to play instead of the model, once it has loaded.
    var samples: String? = nil
    /// Bowed only: brightness of the bowed string (one-pole low-pass cutoff, Hz).
    var bowCutoff = 6000.0
    /// Extra high-frequency loss in the string (0 = none, toward 1 = gut/nylon that loses its overtones fast):
    /// a one-pole low-pass in the loop, beyond what `damping` can do. Set for a 220 Hz note and eased for
    /// higher ones (they pass the filter more often per second), so every note keeps a similar ring.
    var stringLoss = 0.0

    struct Mode: Equatable { let f: Double, q: Double, g: Double }

    /// A synthetic body impulse response: air cavity, top-plate modes and a dense cloud of higher modes.
    struct Resonator: Equatable {
        /// Mode frequencies relative to a dreadnought (smaller bodies are higher).
        var scale: Double
        /// Strength of the Helmholtz "boom" around 100 Hz.
        var air: Double
        /// Amount of upper modes (steel sparkle vs. nylon warmth).
        var highs: Double
        /// Highest body mode in Hz.
        var top: Double
        var length: Double
    }

    // Acoustic body: air (Helmholtz) resonance near 100 Hz, top-plate modes, then a few higher ones.
    private static let acousticBody = [Mode(f: 98, q: 14, g: 0.9), Mode(f: 196, q: 16, g: 0.6), Mode(f: 240, q: 10, g: 0.35),
                                       Mode(f: 390, q: 8, g: 0.35), Mode(f: 560, q: 7, g: 0.22), Mode(f: 1050, q: 4, g: 0.18),
                                       Mode(f: 2400, q: 3, g: 0.12)]
    private static let smallBody = acousticBody.map { Mode(f: $0.f * 1.7, q: $0.q, g: $0.g) }

    static let steel = Timbre(id: "steel", t60: 5, brightness: 0.75, damping: 0.2, pick: 0.12, course: nil,
                              body: [], dry: 1, reverb: 0.24, gain: 0.38,
                              resonator: Resonator(scale: 1, air: 1.35, highs: 1, top: 7500, length: 0.16), samples: "steel")
    static let nylon = Timbre(id: "nylon", t60: 3.6, brightness: 0.45, damping: 0.36, pick: 0.17, course: nil,
                              body: [], dry: 1, reverb: 0.26, gain: 0.36,
                              resonator: Resonator(scale: 1.03, air: 1.25, highs: 0.5, top: 4500, length: 0.16), samples: "nylon")
    static let electricClean = Timbre(id: "electric", t60: 5, brightness: 0.7, damping: 0.25, pick: 0.1, course: nil,
                                      body: [], dry: 1, reverb: 0.16, electric: true, gain: 0.45, samples: "electric")
    static let bass = Timbre(id: "bass", t60: 6, brightness: 0.4, damping: 0.32, pick: 0.15, course: nil,
                             body: [], dry: 1, reverb: 0.08, electric: true, gain: 0.55, samples: "bass")
    static let ukulele = Timbre(id: "uke", t60: 2, brightness: 0.5, damping: 0.36, pick: 0.2, course: nil,
                                body: [], dry: 1, reverb: 0.2, gain: 0.32,
                                resonator: Resonator(scale: 1.75, air: 0.8, highs: 0.75, top: 6000, length: 0.09), samples: "ukulele")
    /// The baritone sits below the recorded ukulele's range (C4 up), so it keeps the model.
    static let baritoneUke = Timbre(id: "baritoneuke", t60: 2.2, brightness: 0.5, damping: 0.36, pick: 0.2, course: nil,
                                    body: [], dry: 1, reverb: 0.2, gain: 0.32,
                                    resonator: Resonator(scale: 1.55, air: 0.9, highs: 0.7, top: 6000, length: 0.1))
    static let mandolin = Timbre(id: "mandolin", t60: 1.8, brightness: 0.9, damping: 0.2, pick: 0.1, course: 2.5,
                                 body: [], dry: 1, reverb: 0.2, gain: 0.3,
                                 resonator: Resonator(scale: 1.8, air: 0.6, highs: 1.1, top: 8000, length: 0.09))
    static let banjo = Timbre(id: "banjo", t60: 1.4, brightness: 0.95, damping: 0.16, pick: 0.09, course: nil,
                              body: [Mode(f: 330, q: 5, g: 0.6), Mode(f: 900, q: 4, g: 0.4), Mode(f: 2600, q: 3, g: 0.3)],
                              dry: 0.6, reverb: 0.15, gain: 0.65, samples: "banjo")
    static let baglama = Timbre(id: "baglama", t60: 3.0, brightness: 0.85, damping: 0.2, pick: 0.11, course: 3,
                                body: [], dry: 1, reverb: 0.24, gain: 0.27,
                                resonator: Resonator(scale: 1.3, air: 1, highs: 1, top: 7000, length: 0.13), samples: "baglama")
    // Fitted to real oud notes (decay and harmonic balance over the first 1.2 s): gut/nylon courses that
    // lose their overtones fast after the bright risha attack, a deep bowl that rings a little longer.
    static let oud = Timbre(id: "oud", t60: 3.8, brightness: 0.6, damping: 0.2, pick: 0.16, course: 1.5,
                            body: [], dry: 1, reverb: 0.28, gain: 0.3,
                            resonator: Resonator(scale: 0.88, air: 1, highs: 0.7, top: 5000, length: 0.24), stringLoss: 0.4)

    // Bowed family: violin-type body modes (air A0, the B1 pair, then the "bridge hill" formant),
    // scaled down for bigger instruments.
    private static func bowedBody(_ k: Double, hill: Double) -> [Mode] {
        [Mode(f: 280 * k, q: 12, g: 0.8), Mode(f: 460 * k, q: 10, g: 0.7), Mode(f: 550 * k, q: 10, g: 0.8),
         Mode(f: 1000 * k, q: 4, g: 0.3), Mode(f: hill, q: 2.5, g: 0.9), Mode(f: hill * 1.4, q: 3, g: 0.45)]
    }
    static let violin = Timbre(id: "violin", t60: 1, brightness: 0.6, damping: 0, pick: 0, course: nil,
                               body: bowedBody(1, hill: 2500), dry: 0.35, reverb: 0.3, gain: 0.16, bowed: true, samples: "violin", bowCutoff: 7000)
    static let viola = Timbre(id: "viola", t60: 1, brightness: 0.55, damping: 0, pick: 0, course: nil,
                              body: bowedBody(0.82, hill: 2100), dry: 0.35, reverb: 0.3, gain: 0.17, bowed: true, samples: "viola", bowCutoff: 5500)
    static let cello = Timbre(id: "cello", t60: 1, brightness: 0.5, damping: 0, pick: 0, course: nil,
                              body: bowedBody(0.42, hill: 1500), dry: 0.38, reverb: 0.3, gain: 0.2, bowed: true, samples: "cello", bowCutoff: 4000)
    static let doubleBass = Timbre(id: "doublebass", t60: 1, brightness: 0.45, damping: 0, pick: 0, course: nil,
                                   body: bowedBody(0.28, hill: 900), dry: 0.4, reverb: 0.28, gain: 0.26, bowed: true, samples: "contrabass", bowCutoff: 2500)
    // Steel-strung folk instruments with their own character.
    static let bouzouki = Timbre(id: "bouzouki", t60: 3.2, brightness: 0.9, damping: 0.18, pick: 0.1, course: 2,
                                 body: [], dry: 1, reverb: 0.24, gain: 0.3,
                                 resonator: Resonator(scale: 1.35, air: 0.9, highs: 1.15, top: 8000, length: 0.12))
    static let balalaika = Timbre(id: "balalaika", t60: 1.6, brightness: 0.85, damping: 0.22, pick: 0.13, course: nil,
                                  body: [], dry: 1, reverb: 0.2, gain: 0.32,
                                  resonator: Resonator(scale: 1.9, air: 0.5, highs: 1, top: 7500, length: 0.07))
    static let cavaquinho = Timbre(id: "cavaquinho", t60: 1.8, brightness: 0.9, damping: 0.2, pick: 0.12, course: nil,
                                   body: [], dry: 1, reverb: 0.2, gain: 0.32,
                                   resonator: Resonator(scale: 1.8, air: 0.7, highs: 1.1, top: 8000, length: 0.08))

    static let piano = Timbre(id: "piano", t60: 6, brightness: 0.6, damping: 0.2, pick: 0.12, course: nil,
                              body: [], dry: 1, reverb: 0.26, gain: 0.3, samples: "piano")

    /// The instrument's own sound. The Settings choice (acoustic / classical / electric) applies to guitars only.
    static func current() -> Timbre { of(Prefs.shared.instrument.id) }

    static func of(_ id: String) -> Timbre {
        let prefs = Prefs.shared
        if id.hasPrefix("guitar") {
            switch prefs.pluckSound {
            case .steel: return .steel
            case .nylon: return .nylon
            case .electric: return .electricClean
            case .auto: return id == "guitar6" ? .steel : .electricClean
            }
        }
        switch id {
        case "bass4", "bass5", "bass6": return .bass
        case "violin": return .violin
        case "viola": return .viola
        case "cello": return .cello
        case "doublebass": return .doubleBass
        case "ukulele": return .ukulele
        case "baritoneuke": return .baritoneUke
        case "cavaquinho": return .cavaquinho
        case "balalaika": return .balalaika
        case "mandolin": return .mandolin
        case "bouzouki", "bouzoukigreek": return .bouzouki
        case "banjo5", "tenorbanjo": return .banjo
        case "baglama": return .baglama
        case "oud": return .oud
        case "piano": return .piano
        default: return .steel
        }
    }
}

enum PluckSound: String, CaseIterable {
    case auto, steel, nylon, electric

    var name: String {
        switch self {
        case .auto: "Auto"
        case .steel: "Acoustic"
        case .nylon: "Classical"
        case .electric: "Electric"
        }
    }

    var detail: String {
        switch self {
        case .auto: "follows the instrument"
        case .steel: "steel strings"
        case .nylon: "nylon strings"
        case .electric: "clean amp"
        }
    }
}

/// A bowed note: the Helmholtz motion of a bowed string is close to a sawtooth (band-limited here
/// with PolyBLEP), with bow noise, a slow attack and vibrato that blooms after the note starts.
/// The bus body filter adds the violin-family formants.
struct BowedVoice {
    private let f: Double
    private let sr: Double
    private var phase = 0.0
    /// Samples to wait before sounding (the sequencer adds its scheduling offset here).
    var delay: Int
    private var age = 0
    private let hold: Int
    private let attack: Double
    private var env = 0.0
    private var releasing = false
    private var lp = 0.0
    private let lpCoef: Double
    private var nlp = 0.0
    private var seed: UInt32
    private let gain: Double
    private let vibRate: Double
    let string: Int?
    let panL: Float, panR: Float
    var finished: Bool { (releasing || age >= delay + hold) && env < 0.0005 && age > delay }

    init(frequency: Double, sampleRate: Double, delay: Int, duration: Double, velocity: Double, timbre: Timbre,
         string: Int?, pan: Double, seed: UInt32) {
        f = frequency
        sr = sampleRate
        self.delay = delay
        hold = Int(duration * sampleRate)
        attack = frequency < 150 ? 0.09 : 0.06
        lpCoef = 1 - exp(-2 * Double.pi * timbre.bowCutoff * (0.7 + 0.3 * velocity) / sampleRate)
        self.seed = seed | 1
        gain = timbre.gain * (0.5 + 0.5 * velocity)
        vibRate = 5.2 + Double(seed % 100) / 100 * 0.8
        self.string = string
        let p = max(-1, min(1, pan))
        panL = Float(sqrt(0.5 - p / 2))
        panR = Float(sqrt(0.5 + p / 2))
    }

    mutating func release() { releasing = true }
    var started: Bool { age > delay }

    private mutating func noise() -> Double {
        seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
        return Double(seed) / Double(UInt32.max) * 2 - 1
    }

    mutating func next() -> Float {
        age += 1
        if age <= delay { return 0 }
        let t = Double(age - delay) / sr
        let sustaining = !releasing && age < delay + hold
        // Bow pressure: a quick swell, then a slow fade after the note's length.
        env += sustaining ? (1 - env) * (1 - exp(-1 / (attack * sr))) : -env * (1 - exp(-1 / (0.12 * sr)))
        // Vibrato fades in after ~0.25 s, as players do.
        let depth = 0.0045 * min(1, max(0, (t - 0.25) / 0.4))
        let freq = f * (1 + depth * sin(2 * .pi * vibRate * t))
        let dt = freq / sr
        phase += dt
        if phase >= 1 { phase -= 1 }
        var saw = 2 * phase - 1
        if phase < dt { let x = phase / dt; saw -= x + x - x * x - 1 }
        else if phase > 1 - dt { let x = (phase - 1) / dt; saw -= x * x + x + x + 1 }
        lp += lpCoef * (saw - lp)
        // Rosin noise, strongest at the attack.
        nlp += 0.25 * (noise() - nlp)
        let bow = nlp * (0.05 + 0.25 * exp(-t / 0.05))
        return Float((lp + bow) * env * gain)
    }
}

/// One string polarization: a tuned Karplus–Strong loop (delay line + loss filter + all-pass for the fraction).
struct StringLoop {
    private var line: [Float]
    private var index = 0
    private var prev: Float = 0
    private var apX: Float = 0
    private var apY: Float = 0
    private let c: Float
    private let loss: Float
    private let s: Float
    /// Extra one-pole low-pass in the loop (`Timbre.stringLoss`).
    private let lpA: Float
    private var lpY: Float = 0
    /// Commuted synthesis: the body's response to the pluck, fed into the string as it plays.
    private let input: [Float]
    private var inputIndex = 0

    init(frequency: Double, sampleRate: Double, t60: Double, damping: Double, stringLoss: Double = 0, input: [Float] = [],
         excitation: (Int) -> [Float]) {
        // The extra low-pass delays and attenuates the fundamental too: measure both there and compensate,
        // so pitch and the fundamental's decay stay exact.
        let w = 2 * Double.pi * frequency / sampleRate
        let k = stringLoss / (1 - min(stringLoss, 0.95)) * (220 / frequency)
        let a = min(0.95, k / (1 + k))
        let lpDelay = a > 0 ? atan2(a * sin(w), 1 - a * cos(w)) / w : 0
        let lpGain = (1 - a) / sqrt(1 - 2 * a * cos(w) + a * a)
        // Loop delay P = N (line) + S (loss filter) + L (low-pass) + d (all-pass), with d kept in [0.1, 1.1).
        let p = sampleRate / frequency
        let n = max(2, Int(floor(p - damping - lpDelay - 0.1)))
        let d = p - damping - lpDelay - Double(n)
        c = Float((1 - d) / (1 + d))
        s = Float(damping)
        lpA = Float(a)
        loss = Float(pow(0.001, 1 / (max(0.3, t60) * frequency)) / lpGain)
        self.input = input
        line = input.isEmpty ? excitation(n) : [Float](repeating: 0, count: n)
    }

    mutating func next() -> Float {
        let out = line[index]
        var filtered = loss * ((1 - s) * out + s * prev)
        prev = out
        if lpA > 0 {
            lpY = (1 - lpA) * filtered + lpA * lpY
            filtered = lpY
        }
        var ap = c * filtered + apX - c * apY
        apX = filtered
        apY = ap
        if inputIndex < input.count {
            ap += input[inputIndex]
            inputIndex += 1
        }
        line[index] = ap
        index += 1
        if index == line.count { index = 0 }
        return out
    }
}

/// A plucked note: two polarizations (fast and slow decay, slightly detuned, which gives the
/// natural two-stage decay and gentle beating), optionally a doubled course.
struct PluckVoice {
    private var loops: [StringLoop]
    private let mix: [Float]
    private let knock: [Float]
    private var knockIndex = 0
    /// Samples to wait before sounding (the sequencer adds its scheduling offset here).
    var delay: Int
    private var age = 0
    private let life: Int
    private let gain: Float
    let string: Int?
    let panL: Float, panR: Float
    private var releasing = false
    private var releaseCountdown = 0
    private var releaseEnv: Float = 1
    private let releaseStep: Float
    var finished: Bool { age >= life || releaseEnv < 0.0005 }
    var started: Bool { delay == 0 }

    init(frequency: Double, sampleRate: Double, delay: Int, velocity: Double, timbre: Timbre,
         string: Int?, pan: Double, seed: UInt32) {
        var rng = seed | 1
        func noise() -> Float {
            rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5
            return Float(rng) / Float(UInt32.max) * 2 - 1
        }
        // Excitation: a noise burst, softened for gentle or dark plucks, then notched by the pick position.
        let bright = timbre.brightness * (0.55 + 0.45 * velocity)
        let a = Float(0.92 - 0.85 * bright)
        func excitation(_ n: Int) -> [Float] {
            var y: Float = 0
            var e = (0..<n).map { _ -> Float in y += (1 - a) * (noise() - y); return y }
            let m = max(1, Int((timbre.pick * Double(n)).rounded()))
            if m < n { for i in stride(from: n - 1, through: m, by: -1) { e[i] -= e[i - m] } }
            let mean = e.reduce(0, +) / Float(n)
            let peak = e.map { abs($0 - mean) }.max() ?? 1
            return e.map { ($0 - mean) / max(peak, 1e-6) }
        }
        // Commuted synthesis: the pluck as heard through the wooden body, shaped by pick and force,
        // drives the string loops. A little of it is also heard directly (the knock of the body).
        var input: [Float] = []
        if let r = timbre.resonator {
            var e = BodyIR.get(r, id: timbre.id, sampleRate: sampleRate)
            var y: Float = 0
            for i in e.indices { y += (1 - a) * (e[i] - y); e[i] = y }
            let m = max(1, Int((timbre.pick * sampleRate / frequency).rounded()))
            if m < e.count { for i in stride(from: e.count - 1, through: m, by: -1) { e[i] -= e[i - m] } }
            let peak = e.map(abs).max() ?? 1
            input = e.map { $0 / max(peak, 1e-6) * 0.5 }
        }
        knock = input
        let t60 = min(12, timbre.t60 * sqrt(220 / frequency))
        // A doubled course is tuned symmetrically around the note, so the pair still averages to pitch.
        let spread = (timbre.course ?? 0) / 2
        let cents = { (c: Double) in frequency * pow(2, c / 1200) }
        var loops = [
            StringLoop(frequency: cents(-spread - 0.15), sampleRate: sampleRate, t60: t60, damping: timbre.damping, stringLoss: timbre.stringLoss, input: input, excitation: excitation),
            StringLoop(frequency: cents(-spread + 0.2), sampleRate: sampleRate, t60: t60 * 0.45, damping: timbre.damping, stringLoss: timbre.stringLoss, input: input, excitation: excitation),
        ]
        var mix: [Float] = [0.58, 0.42]
        if timbre.course != nil {
            loops.append(StringLoop(frequency: cents(spread), sampleRate: sampleRate, t60: t60 * 0.9,
                                    damping: timbre.damping, stringLoss: timbre.stringLoss, input: input, excitation: excitation))
            mix = [0.4, 0.2, 0.6]
        }
        self.loops = loops
        self.mix = mix
        self.delay = delay
        self.string = string
        gain = Float(timbre.gain * (0.35 + 0.65 * velocity))
        let p = max(-1, min(1, pan))
        panL = Float(sqrt(0.5 - p / 2))
        panR = Float(sqrt(0.5 + p / 2))
        life = delay + Int(sampleRate * min(10, t60 * 1.2))
        releaseStep = Float(exp(-1 / (0.035 * sampleRate)))
    }

    /// A new note on the same string stops this one, as a real string can only sound once.
    mutating func release() { releasing = true }

    /// Releases `samples` from now (a scheduled strum that hasn't started yet).
    mutating func releaseAt(_ samples: Int) {
        if samples <= 0 { releasing = true } else { releaseCountdown = samples }
    }

    mutating func next() -> Float {
        age += 1
        if delay > 0 { delay -= 1; return 0 }
        var s: Float = 0
        for i in loops.indices { s += loops[i].next() * mix[i] }
        if knockIndex < knock.count {
            s += knock[knockIndex] * 0.25
            knockIndex += 1
        }
        if releaseCountdown > 0 {
            releaseCountdown -= 1
            if releaseCountdown == 0 { releasing = true }
        }
        if releasing { releaseEnv *= releaseStep }
        let remaining = life - age
        let fade: Float = remaining < 9600 ? Float(remaining) / 9600 : 1
        return s * gain * fade * releaseEnv
    }
}

/// Synthetic guitar-body impulse responses, built once per body and cached.
enum BodyIR {
    private static var cache: [String: [Float]] = [:]
    private static let lock = NSLock()

    static func get(_ r: Timbre.Resonator, id: String, sampleRate: Double) -> [Float] {
        let key = "\(id)|\(Int(sampleRate))"
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let ir = make(r, sampleRate: sampleRate)
        cache[key] = ir
        return ir
    }

    private static func make(_ r: Timbre.Resonator, sampleRate sr: Double) -> [Float] {
        let n = Int(r.length * sr)
        var out = [Double](repeating: 0, count: n)
        var seed: UInt32 = 0x2545_F491
        func rand() -> Double {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            return Double(seed) / Double(UInt32.max)
        }
        // (frequency, decay seconds, amplitude): air cavity, its coupled top mode, then the top plate.
        var modes: [(Double, Double, Double)] = [
            (98, 0.12, r.air), (118, 0.05, 0.25 * r.air), (196, 0.08, 0.8), (232, 0.06, 0.55), (290, 0.05, 0.45),
            (385, 0.04, 0.42), (440, 0.035, 0.3), (520, 0.03, 0.32), (610, 0.028, 0.25), (700, 0.025, 0.22),
        ].map { ($0.0 * r.scale, $0.1, $0.2) }
        // A dense cloud of higher modes, log-spaced at random, weaker and shorter as they rise.
        let lo = 750 * r.scale
        for _ in 0..<110 {
            let f = exp(log(lo) + rand() * (log(r.top) - log(lo)))
            let amp = 0.24 * r.highs * pow(lo / f, 0.5) * (0.4 + 0.6 * rand())
            let decay = 0.02 * pow(lo / f, 0.6) * (0.6 + 0.8 * rand())
            modes.append((f, decay, amp))
        }
        for (f, decay, amp) in modes where f < sr * 0.45 {
            // Damped oscillator by recursion: y[k] = 2r cos(w) y[k-1] − r² y[k-2].
            let w = 2 * Double.pi * f / sr
            let rr = exp(-1 / (decay * sr))
            let phase = rand() * 2 * Double.pi
            var y1 = amp * sin(phase - w) * (1 / rr), y0 = amp * sin(phase)
            let k = 2 * rr * cos(w)
            for i in 0..<n {
                out[i] += y0
                let y = k * y0 - rr * rr * y1
                y1 = y0
                y0 = y
            }
        }
        // The first instant: a short, bright knock of pick on string and top.
        for i in 0..<min(n, Int(sr * 0.003)) {
            out[i] += (rand() * 2 - 1) * 0.35 * exp(-Double(i) / (sr * 0.0007))
        }
        let peak = out.map(abs).max() ?? 1
        return out.map { Float($0 / peak) }
    }
}

struct Biquad {
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    static func bandpass(_ f: Double, q: Double, sampleRate: Double) -> Biquad {
        let w = 2 * Double.pi * min(f, sampleRate * 0.45) / sampleRate, alpha = sin(w) / (2 * q), a0 = 1 + alpha
        var b = Biquad()
        b.b0 = alpha / a0; b.b1 = 0; b.b2 = -alpha / a0; b.a1 = -2 * cos(w) / a0; b.a2 = (1 - alpha) / a0
        return b
    }

    static func lowpass(_ f: Double, q: Double, sampleRate: Double) -> Biquad {
        let w = 2 * Double.pi * f / sampleRate, alpha = sin(w) / (2 * q), cw = cos(w), a0 = 1 + alpha
        var b = Biquad()
        b.b0 = (1 - cw) / 2 / a0; b.b1 = (1 - cw) / a0; b.b2 = (1 - cw) / 2 / a0; b.a1 = -2 * cw / a0; b.a2 = (1 - alpha) / a0
        return b
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

/// Body resonances (or a pickup/amp for electrics) for one channel.
struct BodyFilter {
    private var modes: [Biquad] = []
    private var gains: [Double] = []
    private var dry = 1.0
    private var electric = false
    private var pickup = Biquad()

    init() {}

    init(_ t: Timbre, sampleRate: Double) {
        modes = t.body.map { Biquad.bandpass($0.f, q: $0.q, sampleRate: sampleRate) }
        gains = t.body.map(\.g)
        dry = t.dry
        electric = t.electric
        // A pickup's resonant peak before its treble roll-off.
        pickup = .lowpass(t.id == "bass" ? 2200 : 3800, q: 1.4, sampleRate: sampleRate)
    }

    mutating func process(_ x: Double) -> Double {
        if electric { return tanh(1.3 * pickup.process(x)) / 1.3 }
        var y = dry * x
        for i in modes.indices { y += gains[i] * modes[i].process(x) * 2.2 }
        return y
    }
}

/// A small stereo room (Freeverb topology: parallel combs into series all-passes).
struct Room {
    private struct Comb {
        var buf: [Float]
        var i = 0
        var store: Float = 0
        mutating func process(_ x: Float) -> Float {
            let y = buf[i]
            store = y * 0.7 + store * 0.3
            buf[i] = x + store * 0.8
            i += 1
            if i == buf.count { i = 0 }
            return y
        }
    }

    private struct AllPass {
        var buf: [Float]
        var i = 0
        mutating func process(_ x: Float) -> Float {
            let b = buf[i]
            buf[i] = x + b * 0.5
            i += 1
            if i == buf.count { i = 0 }
            return b - x
        }
    }

    private var combsL: [Comb], combsR: [Comb], apsL: [AllPass], apsR: [AllPass]

    init(sampleRate: Double) {
        let k = sampleRate / 44100
        let comb = { (n: Int) in Comb(buf: [Float](repeating: 0, count: Int(Double(n) * k))) }
        let ap = { (n: Int) in AllPass(buf: [Float](repeating: 0, count: Int(Double(n) * k))) }
        combsL = [1116, 1188, 1277, 1356].map(comb)
        combsR = [1139, 1211, 1300, 1379].map(comb)
        apsL = [556, 441].map(ap)
        apsR = [579, 464].map(ap)
    }

    mutating func process(_ x: Float) -> (Float, Float) {
        let input = x * 0.05
        var l: Float = 0, r: Float = 0
        for i in combsL.indices { l += combsL[i].process(input); r += combsR[i].process(input) }
        for i in apsL.indices { l = apsL[i].process(l); r = apsR[i].process(r) }
        return (l, r)
    }
}
