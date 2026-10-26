import Foundation

// MARK: - What can be asked

/// The kinds of question the EarQuiz tab asks; Mixed draws from the listening ones.
/// Sing answers with the voice (the microphone judges it); Find answers on the neck or keyboard.
enum EarMode: String, CaseIterable {
    case mixed, intervals, chords, scales, notes, sing, find

    /// The kinds Mixed draws from, with how often each comes up.
    static let mixable: [(mode: EarMode, weight: Double)] = [(.intervals, 1), (.chords, 1), (.scales, 0.8), (.notes, 0.35)]

    var title: String {
        switch self {
        case .mixed: return "Mixed"
        case .intervals: return "Intervals"
        case .chords: return "Chords"
        case .scales: return "Scales & Makams"
        case .notes: return "Notes"
        case .sing: return "Sing"
        case .find: return "Find notes"
        }
    }

    var prompt: String {
        switch self {
        case .mixed: return "What do you hear?"
        case .intervals: return "Which interval?"
        case .chords: return "Which chord?"
        case .scales: return "Which scale?"
        case .notes: return "Which note?"
        case .sing: return "Sing it back"
        case .find: return "Find the note"
        }
    }

    /// Answered by clicking one of the answer buttons (or its number key).
    var answersByButton: Bool { self != .sing && self != .find }
}

/// One possible answer.
struct EarItem: Identifiable, Hashable {
    let id: String
    /// English name, translated for display.
    let name: String
}

/// A ready-made set of answers ("Beginner", "Makams" …).
struct EarPreset: Identifiable {
    let id: String
    let items: [String]
}

/// How a question is played: an interval up, down or together; a chord together or broken.
struct EarWay: Identifiable, Hashable {
    let id: String
    let name: String
}

/// A question: the item asked, the lowest note it is played from and the way it is played.
struct EarQuestion: Equatable {
    let mode: EarMode
    let item: String
    let root: Int
    let way: String
    /// Find: the string the note must be found on (nil = anywhere).
    var string: Int? = nil

    /// Sing: the note to sing, `item` semitones up or down from the root.
    var target: Int { root + (way == "down" ? -1 : 1) * (Int(item) ?? 0) }
}

/// A sound to make, `at` seconds after the question starts.
struct EarEvent: Equatable {
    let at: Double
    let midis: [Double]
    /// How long bowed notes are held.
    let hold: Double
    /// One string per note: notes on the same string let go of each other.
    let strings: [Int?]
}

enum EarQuiz {
    /// Letter-steps above the root for each interval in semitones (the tritone as an augmented 4th).
    static let intervalSteps = [0, 1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 6, 7, 8, 8, 9, 9, 10, 10, 11]
    static let intervalNames = ["Unison", "Minor 2nd", "Major 2nd", "Minor 3rd", "Major 3rd", "Perfect 4th", "Tritone",
                                "Perfect 5th", "Minor 6th", "Major 6th", "Minor 7th", "Major 7th", "Octave",
                                "Minor 9th", "Major 9th", "Minor 10th", "Major 10th", "Perfect 11th", "Augmented 11th", "Perfect 12th"]
    /// Intervals asked: within the octave, then the compound ones.
    static let intervalIDs = (1...12).map(String.init) + ["13", "14", "15", "16", "17", "19"]
    static let chordIDs = ["", "m", "5", "dim", "aug", "sus2", "sus4", "7", "maj7", "m7", "m7♭5", "dim7", "mMaj7", "7sus4",
                           "6", "m6", "6/9", "add9", "madd9", "9", "maj9", "m9", "7♭9", "7♯9", "7♯5", "13"]
    static let scaleIDs = ["major", "minor", "harmonic", "melodic", "dorian", "phrygian", "lydian", "mixolydian", "locrian",
                           "majpent", "minpent", "blues", "whole", "phrygdom", "hungarian", "hirajoshi",
                           "rast", "ussak", "huseyni", "hicaz", "kurdi", "nihavend", "saba", "karcigar", "hicazkar", "suzinak",
                           "humayun", "buselik", "mahur", "zirguleli", "sedaraban", "nikriz", "neveser"]
    /// Shorter names than the Scales tab's ("Major" for "Major (Ionian)").
    private static let scaleNames = ["major": "Major", "minor": "Minor", "harmonic": "Harmonic Minor", "melodic": "Melodic Minor",
                                     "majpent": "Major Pentatonic", "minpent": "Minor Pentatonic"]

    static func items(_ mode: EarMode) -> [EarItem] {
        switch mode {
        case .mixed:
            return []
        case .intervals:
            return intervalIDs.map { EarItem(id: $0, name: intervalNames[Int($0)!]) }
        case .chords:
            return chordIDs.map { id in EarItem(id: id, name: Chords.quality(id).name) }
        case .scales:
            return scaleIDs.map { id in EarItem(id: id, name: scaleNames[id] ?? Scales.scale(id).name) }
        case .notes, .find:
            return (0..<12).map { EarItem(id: "\($0)", name: "") }
        case .sing:
            return (1...12).map { EarItem(id: "\($0)", name: intervalNames[$0]) }
        }
    }

    static func presets(_ mode: EarMode) -> [EarPreset] {
        switch mode {
        case .mixed:
            return [EarPreset(id: "All", items: [])]
        case .intervals:
            return [EarPreset(id: "Beginner", items: ["3", "4", "7", "12"]),
                    EarPreset(id: "Intermediate", items: ["1", "2", "3", "4", "5", "7", "9", "12"]),
                    EarPreset(id: "Octave", items: (1...12).map(String.init)),
                    EarPreset(id: "Compound", items: ["12", "13", "14", "15", "16", "17", "19"]),
                    EarPreset(id: "All", items: intervalIDs)]
        case .chords:
            return [EarPreset(id: "Beginner", items: ["", "m"]),
                    EarPreset(id: "Triads", items: ["", "m", "dim", "aug", "sus2", "sus4"]),
                    EarPreset(id: "Common", items: ["", "m", "dim", "aug", "sus2", "sus4", "7", "maj7", "m7", "6", "add9"]),
                    EarPreset(id: "Sevenths", items: ["7", "maj7", "m7", "m7♭5", "dim7", "mMaj7", "7sus4"]),
                    EarPreset(id: "Extended", items: ["6", "6/9", "add9", "9", "maj9", "m9", "7♭9", "7♯9", "13"]),
                    EarPreset(id: "All", items: chordIDs)]
        case .scales:
            return [EarPreset(id: "Beginner", items: ["major", "minor", "harmonic", "majpent"]),
                    EarPreset(id: "Modes", items: ["major", "dorian", "phrygian", "lydian", "mixolydian", "minor", "locrian"]),
                    EarPreset(id: "Popular", items: ["major", "minor", "harmonic", "dorian", "mixolydian", "majpent", "minpent", "blues",
                                                     "rast", "ussak", "hicaz", "kurdi", "nihavend", "huseyni"]),
                    EarPreset(id: "Makams", items: ["rast", "ussak", "huseyni", "hicaz", "kurdi", "nihavend", "saba", "karcigar",
                                                    "hicazkar", "suzinak", "humayun", "buselik", "mahur", "zirguleli",
                                                    "sedaraban", "nikriz", "neveser"]),
                    EarPreset(id: "All", items: scaleIDs)]
        case .notes, .find:
            return [EarPreset(id: "White keys", items: ["0", "2", "4", "5", "7", "9", "11"]),
                    EarPreset(id: "All", items: (0..<12).map(String.init))]
        case .sing:
            return [EarPreset(id: "Beginner", items: ["3", "4", "7", "12"]),
                    EarPreset(id: "Intermediate", items: ["2", "3", "4", "5", "7", "9", "12"]),
                    EarPreset(id: "Octave", items: (1...12).map(String.init))]
        }
    }

    /// The set a kind starts with until one is picked: wide enough that the questions keep varying.
    static func defaultSet(_ mode: EarMode) -> [String] {
        let id = [EarMode.intervals: "Octave", .chords: "Common", .scales: "Popular", .notes: "All",
                  .sing: "Beginner", .find: "White keys"][mode] ?? ""
        return (presets(mode).first { $0.id == id } ?? presets(mode)[0]).items
    }

    static func ways(_ mode: EarMode) -> [EarWay] {
        switch mode {
        case .mixed: return []
        case .intervals: return [EarWay(id: "up", name: "Up"), EarWay(id: "down", name: "Down"), EarWay(id: "together", name: "Together")]
        case .chords: return [EarWay(id: "together", name: "Together"), EarWay(id: "broken", name: "Broken")]
        case .scales: return []
        // One switch: hear C before the note (relative pitch) or the note alone (perfect pitch).
        case .notes: return [EarWay(id: "ref", name: "Hear %@ first")]
        case .sing: return [EarWay(id: "up", name: "Up"), EarWay(id: "down", name: "Down")]
        // One switch: anywhere on the neck, or on a string named by the question.
        case .find: return [EarWay(id: "string", name: "On one string")]
        }
    }

    /// Ways that must keep at least one selected (Notes' reference is a plain on/off switch).
    static func needsWay(_ mode: EarMode) -> Bool { mode == .intervals || mode == .chords || mode == .sing }

    static func defaultWays(_ mode: EarMode) -> [String] {
        switch mode {
        case .intervals, .sing: return ["up"]
        case .chords: return ["together"]
        case .scales, .notes, .mixed, .find: return []
        }
    }

    /// Semitones the question spans above its root.
    static func span(_ mode: EarMode, _ item: String) -> Int {
        switch mode {
        case .intervals, .sing: return Int(item) ?? 12
        case .chords: return Chords.quality(item).intervals.max() ?? 7
        case .scales: return 12
        case .notes, .mixed, .find: return 0
        }
    }

    /// A comfortable stretch of the instrument to play questions in.
    static func register(_ instrument: Instrument, _ tuning: Tuning) -> ClosedRange<Int> {
        if instrument.isKeyboard { return 48...79 }
        let lo = max(36, tuning.notes.min() ?? 40)
        let hi = min(84, (tuning.notes.max() ?? 64) + max(12, min(instrument.frets, 15)))
        return lo...max(lo + 14, hi)
    }

    // MARK: Choosing a question

    /// Picks the next question, more often the items that were missed. `stats` maps item → (right, asked).
    static func makeQuestion(mode: EarMode, set: [String], ways: [String], register: ClosedRange<Int>,
                             stats: [String: (Int, Int)], misses: [String: Int], recent: [String],
                             random: inout some RandomNumberGenerator) -> EarQuestion {
        let pool = set.isEmpty ? presets(mode)[0].items : set
        // Never the same item three times running, nor twice if there is enough choice.
        var candidates = pool
        if pool.count > 2, let last = recent.last { candidates.removeAll { $0 == last } }
        if recent.count >= 2, recent.suffix(2).allSatisfy({ $0 == recent.last }), candidates.count > 1 {
            candidates.removeAll { $0 == recent.last }
        }
        if candidates.isEmpty { candidates = pool }
        let weights = candidates.map { id -> Double in
            let (right, asked) = stats[id] ?? (0, 0)
            let accuracy = Double(right + 1) / Double(asked + 2)
            return 0.4 + (1 - accuracy) * 2.6 + Double(misses[id] ?? 0) * 0.9
        }
        var pick = Double.random(in: 0..<weights.reduce(0, +), using: &random)
        var item = candidates[candidates.count - 1]
        for (i, w) in weights.enumerated() {
            if pick < w { item = candidates[i]; break }
            pick -= w
        }
        let span = self.span(mode, item)
        let way: String
        if mode == .notes {
            way = ways.contains("ref") ? "ref" : ""
        } else if mode == .find {
            way = ways.contains("string") ? "string" : ""
        } else {
            let allowed = ways.filter { w in self.ways(mode).contains { $0.id == w } }
            way = allowed.randomElement(using: &random) ?? defaultWays(mode).first ?? ""
        }
        let root: Int
        if mode == .find {
            root = Int(item) ?? 0
        } else if mode == .sing {
            // Around the middle of most voices; any octave of the answer counts, so low and high voices both fit.
            root = Int.random(in: 52...64, using: &random)
        } else if mode == .notes {
            // Any octave of the pitch class inside the register.
            let pc = Int(item) ?? 0
            let options = register.filter { (($0 % 12) + 12) % 12 == pc }
            root = options.randomElement(using: &random) ?? 60 + pc
        } else {
            // Roots around the middle of the register, so nothing lands at its extremes.
            let top = max(register.lowerBound, register.upperBound - span)
            let mid = (register.lowerBound + top) / 2
            let lo = max(register.lowerBound, mid - 6), hi = min(top, mid + 6)
            var roots = Array(lo...max(lo, hi))
            // Makams sit on a natural note, as their karar does (G Rast, A Hicaz), so their koma
            // accidentals read the traditional way.
            if mode == .scales, Scales.scale(item).isMakam {
                let natural = roots.filter { naturalPC.contains((($0 % 12) + 12) % 12) }
                if !natural.isEmpty { roots = natural }
            }
            root = roots.randomElement(using: &random) ?? lo
        }
        return EarQuestion(mode: mode, item: item, root: root, way: way)
    }

    // MARK: Sound

    /// What to play for `item` from the question's root, the way the question was played.
    static func events(_ q: EarQuestion, item: String) -> [EarEvent] {
        let r = Double(q.root)
        switch q.mode {
        case .intervals:
            let top = r + Double(Int(item) ?? 0)
            switch q.way {
            case "down": return [EarEvent(at: 0, midis: [top], hold: 0.8, strings: [1]),
                                 EarEvent(at: 0.75, midis: [r], hold: 1.2, strings: [1])]
            case "together": return [EarEvent(at: 0, midis: [r, top], hold: 1.8, strings: [0, 1])]
            default: return [EarEvent(at: 0, midis: [r], hold: 0.8, strings: [1]),
                             EarEvent(at: 0.75, midis: [top], hold: 1.2, strings: [1])]
            }
        case .chords:
            let notes = Chords.quality(item).intervals.map { r + Double($0) }
            let strings = notes.indices.map { Optional($0) }
            if q.way == "broken" {
                // Up the chord one note at a time, then all together.
                let steps = notes.enumerated().map { i, m in EarEvent(at: Double(i) * 0.36, midis: [m], hold: 0.5, strings: [i]) }
                return steps + [EarEvent(at: Double(notes.count) * 0.36 + 0.2, midis: notes, hold: 1.8, strings: strings)]
            }
            return [EarEvent(at: 0, midis: notes, hold: 1.8, strings: strings)]
        case .notes:
            let pitch = EarEvent(at: q.way == "ref" ? 1.0 : 0, midis: [r], hold: 1.2, strings: [1])
            guard q.way == "ref" else { return [pitch] }
            // C in the same octave as the note, or the one just below.
            let c = Double(q.root - ((q.root % 12) + 12) % 12)
            return [EarEvent(at: 0, midis: [c], hold: 0.8, strings: [0]), pitch]
        case .scales:
            return scaleRun(item, root: q.root).enumerated().map { i, m in
                EarEvent(at: Double(i) * scaleStep, midis: [m], hold: scaleStep + 0.03, strings: [1])
            }
        case .sing:
            return [EarEvent(at: 0, midis: [r], hold: 1.1, strings: [1])]
        case .find:
            // The note to find, so its sound goes with its place.
            return [EarEvent(at: 0, midis: [Double(60 + ((q.root % 12) + 12) % 12)], hold: 0.9, strings: [1])]
        case .mixed:
            return []
        }
    }

    /// Sing: the root, then the note that was asked for.
    static func answerEvents(_ q: EarQuestion) -> [EarEvent] {
        [EarEvent(at: 0, midis: [Double(q.root)], hold: 0.8, strings: [1]),
         EarEvent(at: 0.75, midis: [Double(q.target)], hold: 1.2, strings: [1])]
    }

    static let scaleStep = 0.24

    /// One octave up and back down; makam degrees at their true koma pitches.
    static func scaleRun(_ id: String, root: Int) -> [Double] {
        let s = Scales.scale(id)
        let up = (s.degrees + [12]).map { Double(root) + $0 }
        return up + up.dropLast().reversed()
    }

    /// Two items that sound alike within a koma (Kürdî and Phrygian, Rast and Major): either answer counts.
    static func sameSound(_ mode: EarMode, _ a: String, _ b: String) -> Bool {
        guard mode == .scales, a != b else { return a == b }
        let x = Scales.scale(a).degrees, y = Scales.scale(b).degrees
        return x.count == y.count && zip(x, y).allSatisfy { abs($0 - $1) < 0.2 }
    }

    // MARK: Spelling

    static let naturalPC = [0, 2, 4, 5, 7, 9, 11]

    /// A note as a letter (0 = C … 6 = B) and an accidental in semitones.
    struct Spelled: Equatable {
        let letter: Int
        let accidental: Int
    }

    private static func wrap(_ x: Int) -> Int { ((x % 12) + 12 + 6) % 12 - 6 }

    static func spell(above root: Spelled, steps: Int, semitones: Int) -> Spelled {
        let letter = (root.letter + steps) % 7
        let pc = naturalPC[root.letter] + root.accidental + semitones
        return Spelled(letter: letter, accidental: wrap(pc - naturalPC[letter]))
    }

    static func name(_ s: Spelled, _ notation: Notation) -> String {
        let acc = ["𝄫", "♭", "", "♯", "𝄪"][max(0, min(4, s.accidental + 2))]
        return notation.name(pc: naturalPC[s.letter]) + acc
    }

    /// Letter-steps and semitones of each note the item is made of, from the root.
    static func shape(_ mode: EarMode, _ item: String) -> [(steps: Int, semitones: Int)] {
        switch mode {
        case .intervals, .sing:
            let n = Int(item) ?? 0
            return [(0, 0), (intervalSteps[n], n)]
        case .chords:
            let q = Chords.quality(item)
            return q.intervals.map { iv in
                let digits = q.label(iv).filter(\.isNumber)
                return (Int(digits).map { $0 - 1 } ?? 0, iv)
            }
        case .scales, .notes, .mixed, .find:
            return [(0, 0)]
        }
    }

    /// Spells an interval or chord from its root with the right letters (C–E♭, not C–D♯), choosing the
    /// root's spelling that needs the fewest accidentals.
    static func spelling(_ mode: EarMode, _ item: String, root: Int, _ notation: Notation) -> [String] {
        let pc = ((root % 12) + 12) % 12
        let tones = shape(mode, item)
        let roots = (0..<7).compactMap { l -> Spelled? in
            let a = wrap(pc - naturalPC[l])
            return abs(a) <= 1 ? Spelled(letter: l, accidental: a) : nil
        }
        // A white-key root keeps its plain name (C, not B♯); a black key may go either way.
        .sorted { abs($0.accidental) < abs($1.accidental) }
        .filter { naturalPC.contains(pc) ? $0.accidental == 0 : true }
        let options = roots.map { r in tones.map { spell(above: r, steps: $0.steps, semitones: $0.semitones) } }
        let preferSharp = notation.accidental == .sharp
        let best = options.min { a, b in
            let ca = a.map { abs($0.accidental) }.reduce(0, +), cb = b.map { abs($0.accidental) }.reduce(0, +)
            if ca != cb { return ca < cb }
            return preferSharp ? a[0].accidental > b[0].accidental : a[0].accidental < b[0].accidental
        } ?? []
        return best.map { name($0, notation) }
    }
}
