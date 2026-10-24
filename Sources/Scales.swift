import CoreAudio
import Foundation

struct Scale: Identifiable {
    let id: String
    let name: String
    let group: String
    /// Degrees above the root in semitones; fractional for makams.
    let degrees: [Double]
    /// Makams: step sizes in Holdrian commas (53 per octave) and the usual karar (tonic) pitch class.
    var commas: [Int]? = nil
    var karar: Int? = nil

    var isMakam: Bool { commas != nil }

    /// Step pattern as shown under the name: "W W H …" or, for makams, "9 8 5 …" commas.
    var steps: String {
        if let commas { return commas.map(String.init).joined(separator: " ") }
        let all = degrees + [12]
        return zip(all, all.dropFirst()).map { a, b in
            let x = b - a
            if abs(x - x.rounded()) > 0.01 {
                // Quarter tones as fractions of a whole tone; anything else (slendro) in cents.
                switch (x * 2).rounded() {
                case 1 where abs(x * 2 - 1) < 0.01: return "¼"
                case 3 where abs(x * 2 - 3) < 0.01: return "¾"
                case 5 where abs(x * 2 - 5) < 0.01: return "1¼"
                default: return "\(Int((x * 100).rounded()))¢"
                }
            }
            switch Int(x.rounded()) {
            case 1: return "H"
            case 2: return "W"
            case 3: return "W½"
            default: return "\(Int(x.rounded()))"
            }
        }.joined(separator: " ")
    }
}

enum Scales {
    /// One Holdrian comma (koma) in cents: the octave divided into 53.
    static let koma = 1200.0 / 53

    static let groups = ["Modes", "Jazz", "Pentatonic & Blues", "Asian", "Indian", "Minor & Exotic", "Symmetric", "Arabic Maqam", "Makam"]

    private static func s(_ id: String, _ name: String, _ group: String, _ d: [Int]) -> Scale {
        Scale(id: id, name: name, group: group, degrees: d.map(Double.init))
    }

    /// Scales with microtones that aren't komas: Arabic quarter tones, Javanese slendro.
    private static func q(_ id: String, _ name: String, _ group: String, _ d: [Double]) -> Scale {
        Scale(id: id, name: name, group: group, degrees: d)
    }

    /// Makams in the Arel–Ezgi–Uzdilek system: K=1, E=4, S=5, M=8, T=9, A=12/13 commas.
    private static func m(_ id: String, _ name: String, karar: Int, _ commas: [Int]) -> Scale {
        var acc = 0
        let degrees = [0.0] + commas.dropLast().map { c -> Double in
            acc += c
            return Double(acc) * koma / 100
        }
        return Scale(id: id, name: name, group: "Makam", degrees: degrees, commas: commas, karar: karar)
    }

    static let all: [Scale] = [
        s("major", "Major (Ionian)", "Modes", [0, 2, 4, 5, 7, 9, 11]),
        s("dorian", "Dorian", "Modes", [0, 2, 3, 5, 7, 9, 10]),
        s("phrygian", "Phrygian", "Modes", [0, 1, 3, 5, 7, 8, 10]),
        s("lydian", "Lydian", "Modes", [0, 2, 4, 6, 7, 9, 11]),
        s("mixolydian", "Mixolydian", "Modes", [0, 2, 4, 5, 7, 9, 10]),
        s("minor", "Minor (Aeolian)", "Modes", [0, 2, 3, 5, 7, 8, 10]),
        s("locrian", "Locrian", "Modes", [0, 1, 3, 5, 6, 8, 10]),

        s("lyddom", "Lydian Dominant", "Jazz", [0, 2, 4, 6, 7, 9, 10]),
        s("altered", "Altered", "Jazz", [0, 1, 3, 4, 6, 8, 10]),
        s("lydaug", "Lydian Augmented", "Jazz", [0, 2, 4, 6, 8, 9, 11]),
        s("locrian2", "Locrian ♮2", "Jazz", [0, 2, 3, 5, 6, 8, 10]),
        s("mixob6", "Mixolydian ♭6", "Jazz", [0, 2, 4, 5, 7, 8, 10]),
        s("dorianb2", "Dorian ♭2", "Jazz", [0, 1, 3, 5, 7, 9, 10]),
        s("bebopdom", "Bebop Dominant", "Jazz", [0, 2, 4, 5, 7, 9, 10, 11]),
        s("bebopmaj", "Bebop Major", "Jazz", [0, 2, 4, 5, 7, 8, 9, 11]),
        s("bebopmin", "Bebop Minor", "Jazz", [0, 2, 3, 4, 5, 7, 9, 10]),
        s("bebopmelmin", "Bebop Melodic Minor", "Jazz", [0, 2, 3, 5, 7, 8, 9, 11]),
        s("lydiansharp2", "Lydian ♯2", "Jazz", [0, 3, 4, 6, 7, 9, 11]),
        s("ionianaug", "Ionian ♯5", "Jazz", [0, 2, 4, 5, 8, 9, 11]),
        s("locrian6", "Locrian ♮6", "Jazz", [0, 1, 3, 5, 6, 9, 10]),
        s("ultralocrian", "Ultralocrian", "Jazz", [0, 1, 3, 4, 6, 8, 9]),

        s("majpent", "Major Pentatonic", "Pentatonic & Blues", [0, 2, 4, 7, 9]),
        s("minpent", "Minor Pentatonic", "Pentatonic & Blues", [0, 3, 5, 7, 10]),
        s("blues", "Blues", "Pentatonic & Blues", [0, 3, 5, 6, 7, 10]),
        s("majblues", "Major Blues", "Pentatonic & Blues", [0, 2, 3, 4, 7, 9]),
        s("egyptian", "Egyptian (Suspended)", "Pentatonic & Blues", [0, 2, 5, 7, 10]),
        s("dompent", "Dominant Pentatonic", "Pentatonic & Blues", [0, 2, 4, 7, 10]),
        s("mangong", "Man Gong (Chinese)", "Pentatonic & Blues", [0, 3, 5, 8, 10]),

        s("hirajoshi", "Hirajōshi", "Asian", [0, 2, 3, 7, 8]),
        s("insen", "In-sen", "Asian", [0, 1, 5, 7, 10]),
        s("iwato", "Iwato", "Asian", [0, 1, 5, 6, 10]),
        s("yo", "Yo", "Asian", [0, 2, 5, 7, 9]),
        s("kumoi", "Kumoi", "Asian", [0, 2, 3, 7, 9]),
        s("pelog", "Pelog (approx.)", "Asian", [0, 1, 3, 7, 8]),
        // Five equal steps to the octave: 240 cents each, between our semitones.
        q("slendro", "Slendro (5-equal)", "Asian", [0, 2.4, 4.8, 7.2, 9.6]),

        s("bhairav", "Bhairav", "Indian", [0, 1, 4, 5, 7, 8, 11]),
        s("todi", "Todi", "Indian", [0, 1, 3, 6, 7, 8, 11]),
        s("purvi", "Purvi", "Indian", [0, 1, 4, 6, 7, 8, 11]),
        s("marwa", "Marwa", "Indian", [0, 1, 4, 6, 7, 9, 11]),
        s("malkauns", "Malkauns", "Indian", [0, 3, 5, 8, 10]),
        s("hindol", "Hindol", "Indian", [0, 4, 6, 9, 11]),
        s("durga", "Durga", "Indian", [0, 2, 5, 7, 9]),

        s("harmonic", "Harmonic Minor", "Minor & Exotic", [0, 2, 3, 5, 7, 8, 11]),
        s("melodic", "Melodic Minor", "Minor & Exotic", [0, 2, 3, 5, 7, 9, 11]),
        s("phrygdom", "Phrygian Dominant", "Minor & Exotic", [0, 1, 4, 5, 7, 8, 10]),
        s("hungarian", "Hungarian Minor", "Minor & Exotic", [0, 2, 3, 6, 7, 8, 11]),
        s("doubleharm", "Double Harmonic", "Minor & Exotic", [0, 1, 4, 5, 7, 8, 11]),
        s("neapmin", "Neapolitan Minor", "Minor & Exotic", [0, 1, 3, 5, 7, 8, 11]),
        s("neapmaj", "Neapolitan Major", "Minor & Exotic", [0, 1, 3, 5, 7, 9, 11]),
        s("ukrdorian", "Ukrainian Dorian", "Minor & Exotic", [0, 2, 3, 6, 7, 9, 10]),
        s("hungmaj", "Hungarian Major", "Minor & Exotic", [0, 3, 4, 6, 7, 9, 10]),
        s("persian", "Persian", "Minor & Exotic", [0, 1, 4, 5, 6, 8, 11]),
        s("enigmatic", "Enigmatic", "Minor & Exotic", [0, 1, 4, 6, 8, 10, 11]),
        s("prometheus", "Prometheus", "Minor & Exotic", [0, 2, 4, 6, 9, 10]),
        s("harmmaj", "Harmonic Major", "Minor & Exotic", [0, 2, 4, 5, 7, 8, 11]),
        s("spanish8", "Spanish 8-tone", "Minor & Exotic", [0, 1, 3, 4, 5, 6, 8, 10]),
        s("tritone", "Tritone", "Minor & Exotic", [0, 1, 4, 6, 7, 10]),

        s("whole", "Whole Tone", "Symmetric", [0, 2, 4, 6, 8, 10]),
        s("dimhw", "Diminished (H–W)", "Symmetric", [0, 1, 3, 4, 6, 7, 9, 10]),
        s("dimwh", "Diminished (W–H)", "Symmetric", [0, 2, 3, 5, 6, 8, 9, 11]),
        s("augmented", "Augmented", "Symmetric", [0, 3, 4, 7, 8, 11]),
        s("chromatic", "Chromatic", "Symmetric", Array(0..<12)),

        // Arabic maqamat in quarter tones (24 per octave); x.5 = half-flat.
        q("arast", "Rast (Arabic)", "Arabic Maqam", [0, 2, 3.5, 5, 7, 9, 10.5]),
        q("bayati", "Bayati", "Arabic Maqam", [0, 1.5, 3, 5, 7, 8, 10]),
        q("asaba", "Saba (Arabic)", "Arabic Maqam", [0, 1.5, 3, 4, 7, 8, 10]),
        q("jiharkah", "Jiharkah", "Arabic Maqam", [0, 2, 4, 5, 7, 9, 10.5]),

        m("rast", "Rast", karar: 7, [9, 8, 5, 9, 9, 8, 5]),
        m("ussak", "Uşşak", karar: 9, [8, 5, 9, 9, 4, 9, 9]),
        m("huseyni", "Hüseyni", karar: 9, [8, 5, 9, 9, 8, 5, 9]),
        m("hicaz", "Hicaz", karar: 9, [5, 12, 5, 9, 8, 5, 9]),
        m("humayun", "Hümayun", karar: 9, [5, 12, 5, 9, 4, 9, 9]),
        m("hicazkar", "Hicazkâr", karar: 7, [5, 12, 5, 9, 5, 12, 5]),
        m("kurdi", "Kürdî", karar: 9, [4, 9, 9, 9, 4, 9, 9]),
        m("nihavend", "Nihavend", karar: 7, [9, 4, 9, 9, 5, 12, 5]),
        m("buselik", "Bûselik", karar: 9, [9, 4, 9, 9, 4, 9, 9]),
        m("mahur", "Mahur", karar: 7, [9, 9, 4, 9, 9, 9, 4]),
        m("karcigar", "Karcığar", karar: 9, [8, 5, 9, 5, 12, 5, 9]),
        m("suzinak", "Suzinak", karar: 7, [9, 8, 5, 9, 5, 12, 5]),
        // Saba does not repeat at the octave; this is its usual first octave.
        m("saba", "Saba", karar: 9, [8, 5, 5, 12, 5, 9, 9]),
        m("zirguleli", "Zirgüleli Hicaz", karar: 9, [5, 12, 5, 9, 5, 12, 5]),
        m("sedaraban", "Şedaraban", karar: 9, [5, 12, 5, 5, 12, 5, 9]),
        m("nikriz", "Nikriz", karar: 7, [9, 4, 13, 5, 9, 8, 5]),
        m("neveser", "Neveser", karar: 7, [9, 4, 13, 5, 5, 12, 5]),
    ]

    static var makams: [Scale] { all.filter(\.isMakam) }

    static func scale(_ id: String) -> Scale { all.first { $0.id == id } ?? all[0] }

    /// Nearest semitone and the koma offset from it, e.g. Rast's 3rd from G → (B, −1).
    static func spell(_ pitch: Double) -> (note: Int, koma: Int) {
        let note = Int(pitch.rounded())
        return (note, Int(((pitch - Double(note)) * 100 / koma).rounded()))
    }

    /// Note name for display. Makam degrees use Turkish (AEU) spelling: a natural note plus an accidental
    /// numbered in komas: B♭¹ (segâh, koma flat), B♭⁴ (bakiye flat), F♯⁴ (eviç).
    static func label(_ pitch: Double, _ notation: Notation, makam: Bool = false) -> String {
        guard makam else { return notation.name(pc: Int(pitch.rounded())) }
        let sp = makamSpelling(pitch)
        return notation.name(pc: sp.natural) + sp.accidental
    }

    /// Natural notes' places in the 53-koma octave, with their pitch class.
    private static let naturals: [(koma: Int, pc: Int)] = [(0, 0), (9, 2), (18, 4), (22, 5), (31, 7), (40, 9), (49, 11), (53, 12)]

    /// Spells a pitch as the nearest natural (as a MIDI note, for the octave) plus a koma accidental.
    static func makamSpelling(_ pitch: Double) -> (natural: Int, accidental: String, komas: Int) {
        let c = Int((pitch * 100 / koma).rounded())
        let octave = Int(floor(Double(c) / 53))
        let r = c - octave * 53
        let n = naturals.min { abs(r - $0.koma) < abs(r - $1.koma) }!
        let k = r - n.koma
        return (octave * 12 + n.pc, komaAccidental(k), k)
    }

    /// Spells degree `i` of a makam the traditional way: seven degrees, seven letters, each with its
    /// own koma accidental (Kürdî's 2nd is B♭⁵, not A♯⁴).
    static func degreeSpelling(_ scale: Scale, _ i: Int, pitch: Double, karar: Int) -> (natural: Int, accidental: String) {
        guard scale.degrees.count == 7 else {
            let sp = makamSpelling(pitch)
            return (sp.natural, sp.accidental)
        }
        let kararPC = ((makamSpelling(Double(karar)).natural % 12) + 12) % 12
        let first = naturals.firstIndex { $0.pc == kararPC } ?? 0
        let letter = naturals[(first + i) % 7]
        let c = Int((pitch * 100 / koma).rounded())
        let base = Int(floor(pitch / 12))
        let best = [base - 1, base, base + 1]
            .map { o in (midi: o * 12 + letter.pc, pos: o * 53 + letter.koma) }
            .min { abs(c - $0.pos) < abs(c - $1.pos) }!
        return (best.midi, komaAccidental(c - best.pos))
    }

    static func degreeLabel(_ scale: Scale, _ i: Int, root: Int, _ notation: Notation) -> String {
        guard scale.isMakam else {
            let d = scale.degrees[i]
            let frac = d - d.rounded(.down)
            // Quarter tone: the note above, half-flat (E½♭ = E a quarter tone flat).
            if abs(frac - 0.5) < 0.01 { return notation.name(pc: root + Int(d.rounded(.up))) + "½♭" }
            // Other microtones (slendro): nearest note and its offset in cents.
            if abs(frac) > 0.01 {
                let n = Int(d.rounded()), c = Int(((d - Double(n)) * 100).rounded())
                return notation.name(pc: root + n) + (c > 0 ? "+\(c)" : "\(c)")
            }
            return notation.name(pc: root + Int(d.rounded()))
        }
        let sp = degreeSpelling(scale, i, pitch: Double(root + 60) + scale.degrees[i], karar: root)
        return notation.name(pc: sp.natural) + sp.accidental
    }

    static func komaAccidental(_ k: Int) -> String {
        guard k != 0 else { return "" }
        let sup: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
                                           "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"]
        return (k < 0 ? "♭" : "♯") + String(String(abs(k)).compactMap { sup[$0] })
    }
}

// MARK: - Playback

/// One note of a scale run: its pitch, the degree it plays and, on a neck, the dot it lights.
struct ScaleNote: Equatable {
    let midi: Double
    let degree: Int
    var mark: NeckMark? = nil
}

/// Plays a scale run and says which note is being heard, so the highlight lands with the sound.
/// Notes are queued a moment ahead at exact times on the synth's sample clock, and the playhead is
/// read back from that same clock, less the output latency. (Wall-clock timers drift: each one may
/// fire up to a tenth of its delay late, so the lights fell further behind the sound as a run went on.)
final class ScalePlayer: ObservableObject {
    static let shared = ScalePlayer()

    /// From Play until the last note's light goes out.
    @Published private(set) var playing = false
    /// The note being heard.
    @Published private(set) var index: Int?

    var current: ScaleNote? { index.map { notes[$0] } }

    private let synth = Synth.shared
    private var notes: [ScaleNote] = []
    /// Sample time each note starts at.
    private var times: [UInt64] = []
    private var end: UInt64 = 0
    private var queued = 0
    private var lookahead: UInt64 = 0
    /// Samples from a note starting in the render to it being heard, less the time a light takes to show.
    private var lead = 0.0
    private var string: Int?
    private var hold = 0.0
    private var timer: Timer?
    /// The clock moves once per render buffer: its last value and when that was seen, to read between.
    private var lastClock: UInt64 = 0
    private var lastChange = 0.0
    private var buffer = 0.0

    func play(_ run: [ScaleNote], step: Double = 0.28) {
        stop()
        guard !run.isEmpty else { return }
        synth.prepare()
        let sr = synth.outputSampleRate
        let output = OutputLatency.current()
        let bowed = Timbre.current().bowed
        // Heard once through the output (buffer, device); seen about a frame after the view changes.
        // A bowed note speaks ~30 ms after it starts: the violin family's samples swell in.
        lead = (output.seconds + (bowed ? 0.03 : 0) - 1.0 / 60) * sr
        buffer = output.buffer
        // Plucked notes share one string, so each is let go as the next one starts: a clean legato
        // line (the piano's on the right hand's side). Bowed notes are held into the next instead.
        let strings = max(2, Prefs.shared.tuning.notes.count)
        string = bowed ? nil : (Prefs.shared.instrument.isKeyboard ? 1 : (strings - 1) / 2)
        hold = step + 0.03
        notes = run
        // A short lead-in, so the first note is queued with room to spare.
        let start = synth.now + UInt64(0.1 * sr)
        times = run.indices.map { start + UInt64((Double($0) * step * sr).rounded()) }
        end = times[times.count - 1] + UInt64((step + 0.2) * sr)
        // Queued shortly before it's due, when the note it lets go of has already started.
        lookahead = UInt64(min(0.2, step * 0.7) * sr)
        queued = 0
        lastClock = synth.now
        lastChange = ProcessInfo.processInfo.systemUptime
        playing = true
        let t = Timer(timeInterval: 1.0 / 240, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if playing {
            synth.cancelScheduled()
            synth.silence()
        }
        playing = false
        index = nil
    }

    private func tick() {
        guard playing else { return }
        let now = synth.now
        let t = ProcessInfo.processInfo.systemUptime
        if now != lastClock {
            lastClock = now
            lastChange = t
        } else if t - lastChange > 2 {
            return stop()  // No audio output.
        }
        while queued < times.count && times[queued] < now + lookahead {
            let f = Music.frequency(midi: notes[queued].midi, a4: Prefs.shared.a4)
            synth.schedule(strum: [Synth.Note(frequency: f, string: string)], at: times[queued], up: false,
                           velocity: 0.75, hold: hold)
            queued += 1
        }
        // The sample being rendered now (read between buffers), as it will be heard and seen.
        let heard = Double(now) + min(t - lastChange, buffer) * synth.outputSampleRate - lead
        if heard >= Double(end) {
            // Done: the last note rings on.
            timer?.invalidate()
            timer = nil
            playing = false
            index = nil
            return
        }
        let i = times.lastIndex { Double($0) <= heard }
        if i != index { index = i }
    }
}

/// What the default output adds between a sample being rendered and it reaching the speaker: the IO
/// buffer, the safety offset and the device's and stream's own latency. About 30 ms on built-in
/// speakers; far more over Bluetooth or AirPlay.
enum OutputLatency {
    static func current() -> (seconds: Double, buffer: Double) {
        guard let device: AudioObjectID = get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice),
              device != kAudioObjectUnknown else { return (0.03, 512.0 / 48000) }
        let out = kAudioDevicePropertyScopeOutput
        let rate: Float64 = get(device, kAudioDevicePropertyNominalSampleRate) ?? 0
        let sr = rate > 0 ? rate : 48000
        let buffer: UInt32 = get(device, kAudioDevicePropertyBufferFrameSize) ?? 512
        let safety: UInt32 = get(device, kAudioDevicePropertySafetyOffset, out) ?? 0
        let latency: UInt32 = get(device, kAudioDevicePropertyLatency, out) ?? 0
        var stream: UInt32 = 0
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: out,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        if AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size >= 4 {
            var ids = [AudioStreamID](repeating: 0, count: Int(size) / 4)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &ids) == noErr, let first = ids.first {
                stream = get(first, kAudioStreamPropertyLatency) ?? 0
            }
        }
        let frames = Double(buffer) + Double(safety) + Double(latency) + Double(stream)
        return (min(3, frames / sr), Double(buffer) / sr)
    }

    private static func get<T: Numeric>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
}
