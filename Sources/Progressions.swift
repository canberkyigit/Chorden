import Foundation

/// A chord in a progression, relative to the key: semitones above the tonic plus a quality.
struct ProgressionStep: Hashable, Codable {
    let offset: Int
    let quality: String
    let numeral: String
}

struct Progression: Hashable, Codable {
    let key: Int
    let minor: Bool
    let mood: String
    let steps: [ProgressionStep]

    func root(_ i: Int) -> Int { (key + steps[i].offset) % 12 }
}

/// Generates progressions that are known to sound good: proven templates (pop, jazz, flamenco…)
/// in a random key, sometimes coloured with 7ths or sus chords where the style allows.
enum Progressions {
    static let moods = ["Happy", "Uplifting", "Romantic", "Melancholic", "Gloomy", "Epic", "Cinematic", "Dreamy", "Lo-fi",
                        "Jazz", "Bossa", "Blues", "Soul", "Gospel", "Rock", "Country", "Reggae", "Anime", "Oriental", "Arabesk"]

    private struct Template {
        let mood: String
        let minor: Bool
        let steps: [(Int, String, String)]
    }

    private static let templates: [Template] = [
        // Happy / pop (major)
        Template(mood: "Happy", minor: false, steps: [(0, "", "I"), (7, "", "V"), (9, "m", "vi"), (5, "", "IV")]),
        Template(mood: "Happy", minor: false, steps: [(0, "", "I"), (9, "m", "vi"), (5, "", "IV"), (7, "", "V")]),
        Template(mood: "Happy", minor: false, steps: [(0, "", "I"), (5, "", "IV"), (9, "m", "vi"), (7, "", "V")]),
        Template(mood: "Happy", minor: false, steps: [(5, "", "IV"), (0, "", "I"), (7, "", "V"), (9, "m", "vi")]),
        Template(mood: "Happy", minor: false, steps: [(0, "", "I"), (5, "", "IV"), (7, "", "V")]),
        Template(mood: "Happy", minor: false, steps: [(0, "", "I"), (7, "", "V"), (5, "", "IV")]),
        Template(mood: "Happy", minor: false, steps: [(0, "", "I"), (2, "m", "ii"), (5, "", "IV")]),
        // Melancholic
        Template(mood: "Melancholic", minor: false, steps: [(9, "m", "vi"), (5, "", "IV"), (0, "", "I"), (7, "", "V")]),
        Template(mood: "Melancholic", minor: true, steps: [(0, "m", "i"), (5, "m", "iv"), (7, "m", "v")]),
        Template(mood: "Melancholic", minor: true, steps: [(0, "m", "i"), (5, "m", "iv"), (8, "", "VI"), (7, "", "V")]),
        Template(mood: "Melancholic", minor: true, steps: [(0, "m", "i"), (10, "", "VII"), (5, "m", "iv")]),
        Template(mood: "Melancholic", minor: false, steps: [(0, "", "I"), (4, "", "III"), (5, "", "IV"), (5, "m", "iv")]),
        Template(mood: "Melancholic", minor: true, steps: [(0, "m", "i"), (3, "", "III"), (10, "", "VII"), (8, "", "VI")]),
        // Epic
        Template(mood: "Epic", minor: true, steps: [(0, "m", "i"), (8, "", "VI"), (3, "", "III"), (10, "", "VII")]),
        Template(mood: "Epic", minor: true, steps: [(0, "m", "i"), (8, "", "VI"), (10, "", "VII")]),
        Template(mood: "Epic", minor: true, steps: [(8, "", "VI"), (10, "", "VII"), (0, "m", "i")]),
        Template(mood: "Epic", minor: true, steps: [(0, "m", "i"), (10, "", "VII"), (8, "", "VI"), (10, "", "VII")]),
        // Dreamy
        Template(mood: "Dreamy", minor: false, steps: [(0, "maj7", "Imaj7"), (4, "m7", "iii7"), (5, "maj7", "IVmaj7")]),
        Template(mood: "Dreamy", minor: false, steps: [(5, "maj7", "IVmaj7"), (7, "7", "V7"), (4, "m7", "iii7"), (9, "m", "vi")]),
        Template(mood: "Dreamy", minor: false, steps: [(0, "add9", "Iadd9"), (4, "m", "iii"), (5, "", "IV")]),
        Template(mood: "Dreamy", minor: false, steps: [(0, "maj7", "Imaj7"), (9, "m7", "vi7"), (5, "maj7", "IVmaj7"), (7, "sus4", "Vsus4")]),
        // Jazz
        Template(mood: "Jazz", minor: false, steps: [(2, "m7", "ii7"), (7, "7", "V7"), (0, "maj7", "Imaj7")]),
        Template(mood: "Jazz", minor: false, steps: [(0, "maj7", "Imaj7"), (9, "m7", "vi7"), (2, "m7", "ii7"), (7, "7", "V7")]),
        Template(mood: "Jazz", minor: true, steps: [(2, "m7♭5", "iiø7"), (7, "7", "V7"), (0, "m7", "i7")]),
        Template(mood: "Jazz", minor: false, steps: [(4, "m7", "iii7"), (9, "7", "VI7"), (2, "m7", "ii7"), (7, "7", "V7")]),
        // Rock
        Template(mood: "Rock", minor: false, steps: [(0, "5", "I5"), (10, "5", "♭VII5"), (5, "5", "IV5")]),
        Template(mood: "Rock", minor: false, steps: [(0, "", "I"), (10, "", "♭VII"), (5, "", "IV"), (0, "", "I")]),
        Template(mood: "Rock", minor: true, steps: [(0, "5", "i5"), (3, "5", "♭III5"), (5, "5", "iv5"), (10, "5", "♭VII5")]),
        Template(mood: "Rock", minor: false, steps: [(0, "", "I"), (3, "", "♭III"), (5, "", "IV")]),
        // Oriental / flamenco (Phrygian dominant, Hicaz flavour)
        Template(mood: "Oriental", minor: true, steps: [(0, "m", "i"), (10, "", "VII"), (8, "", "VI"), (7, "", "V")]),
        Template(mood: "Oriental", minor: false, steps: [(0, "", "I"), (1, "", "♭II"), (10, "m", "♭vii")]),
        Template(mood: "Oriental", minor: false, steps: [(0, "", "I"), (1, "", "♭II"), (5, "m", "iv"), (1, "", "♭II")]),
        Template(mood: "Oriental", minor: true, steps: [(5, "m", "iv"), (3, "", "III"), (1, "", "♭II"), (0, "", "I")]),
        // Uplifting
        Template(mood: "Uplifting", minor: false, steps: [(5, "", "IV"), (7, "", "V"), (9, "m", "vi")]),
        Template(mood: "Uplifting", minor: false, steps: [(0, "", "I"), (2, "m", "ii"), (5, "", "IV"), (7, "", "V")]),
        Template(mood: "Uplifting", minor: false, steps: [(5, "", "IV"), (0, "", "I"), (7, "", "V")]),
        Template(mood: "Uplifting", minor: false, steps: [(0, "add9", "Iadd9"), (7, "", "V"), (9, "m7", "vi7"), (5, "maj7", "IVmaj7")]),
        // Romantic
        Template(mood: "Romantic", minor: false, steps: [(0, "", "I"), (9, "m", "vi"), (2, "m", "ii"), (7, "", "V")]),
        Template(mood: "Romantic", minor: false, steps: [(0, "maj7", "Imaj7"), (4, "m7", "iii7"), (9, "m7", "vi7"), (5, "maj7", "IVmaj7")]),
        Template(mood: "Romantic", minor: false, steps: [(0, "", "I"), (4, "m", "iii"), (5, "", "IV"), (7, "", "V")]),
        Template(mood: "Romantic", minor: false, steps: [(0, "", "I"), (5, "maj7", "IVmaj7"), (7, "sus4", "Vsus4")]),
        // Dark
        Template(mood: "Gloomy", minor: true, steps: [(0, "m", "i"), (1, "", "♭II"), (10, "m", "♭vii")]),
        Template(mood: "Gloomy", minor: true, steps: [(0, "m", "i"), (8, "", "♭VI"), (5, "m", "iv"), (1, "", "♭II")]),
        Template(mood: "Gloomy", minor: true, steps: [(0, "m", "i"), (6, "", "♭V"), (5, "m", "iv"), (0, "m", "i")]),
        Template(mood: "Gloomy", minor: true, steps: [(0, "m", "i"), (11, "dim", "vii°"), (8, "", "♭VI")]),
        // Cinematic
        Template(mood: "Cinematic", minor: true, steps: [(0, "m", "i"), (3, "", "♭III"), (10, "", "♭VII"), (5, "", "IV")]),
        Template(mood: "Cinematic", minor: false, steps: [(0, "", "I"), (4, "", "III"), (9, "m", "vi"), (5, "m", "iv")]),
        Template(mood: "Cinematic", minor: false, steps: [(0, "", "I"), (8, "", "♭VI"), (10, "", "♭VII"), (0, "", "I")]),
        Template(mood: "Cinematic", minor: true, steps: [(0, "sus2", "isus2"), (8, "", "♭VI"), (3, "", "♭III")]),
        // Lo-fi / neo-soul
        Template(mood: "Lo-fi", minor: false, steps: [(2, "m9", "ii9"), (7, "9", "V9"), (0, "maj9", "Imaj9"), (9, "m9", "vi9")]),
        Template(mood: "Lo-fi", minor: false, steps: [(5, "maj7", "IVmaj7"), (4, "m7", "iii7"), (2, "m9", "ii9"), (0, "maj7", "Imaj7")]),
        Template(mood: "Lo-fi", minor: false, steps: [(0, "maj9", "Imaj9"), (4, "7", "III7"), (9, "m9", "vi9")]),
        // Bossa nova
        Template(mood: "Bossa", minor: false, steps: [(2, "m7", "ii7"), (7, "7♭9", "V7♭9"), (0, "maj7", "Imaj7"), (9, "7", "VI7")]),
        Template(mood: "Bossa", minor: false, steps: [(0, "maj7", "Imaj7"), (1, "dim7", "♯i°7"), (2, "m7", "ii7"), (7, "7", "V7")]),
        Template(mood: "Bossa", minor: true, steps: [(0, "m7", "i7"), (5, "m7", "iv7"), (10, "7", "♭VII7"), (3, "maj7", "♭IIImaj7")]),
        // Blues
        Template(mood: "Blues", minor: false, steps: [(0, "7", "I7"), (5, "7", "IV7"), (0, "7", "I7"), (7, "7", "V7")]),
        Template(mood: "Blues", minor: false, steps: [(0, "7", "I7"), (5, "7", "IV7"), (7, "7", "V7")]),
        Template(mood: "Blues", minor: false, steps: [(0, "9", "I9"), (5, "9", "IV9"), (7, "9", "V9"), (5, "9", "IV9")]),
        Template(mood: "Blues", minor: true, steps: [(0, "m7", "i7"), (5, "m7", "iv7"), (7, "7", "V7")]),
        // Soul / funk
        Template(mood: "Soul", minor: false, steps: [(5, "maj7", "IVmaj7"), (4, "m7", "iii7"), (2, "m7", "ii7"), (0, "maj7", "Imaj7")]),
        Template(mood: "Soul", minor: false, steps: [(2, "m7", "ii7"), (4, "m7", "iii7"), (5, "maj7", "IVmaj7")]),
        Template(mood: "Soul", minor: true, steps: [(0, "m7", "i7"), (5, "7", "IV7"), (0, "m7", "i7"), (5, "7", "IV7")]),
        // Gospel
        Template(mood: "Gospel", minor: false, steps: [(0, "", "I"), (4, "7", "III7"), (9, "m", "vi"), (5, "", "IV")]),
        Template(mood: "Gospel", minor: false, steps: [(5, "", "IV"), (6, "dim7", "♯iv°7"), (0, "", "I"), (9, "7", "VI7")]),
        Template(mood: "Gospel", minor: false, steps: [(0, "", "I"), (0, "7", "I7"), (5, "", "IV"), (5, "m", "iv")]),
        // Country
        Template(mood: "Country", minor: false, steps: [(0, "", "I"), (5, "", "IV"), (0, "", "I"), (7, "", "V")]),
        Template(mood: "Country", minor: false, steps: [(0, "", "I"), (2, "7", "II7"), (7, "", "V")]),
        Template(mood: "Country", minor: false, steps: [(0, "", "I"), (9, "m", "vi"), (5, "", "IV"), (7, "7", "V7")]),
        // Reggae
        Template(mood: "Reggae", minor: false, steps: [(0, "", "I"), (5, "", "IV"), (7, "", "V"), (5, "", "IV")]),
        Template(mood: "Reggae", minor: true, steps: [(0, "m", "i"), (10, "", "♭VII"), (8, "", "♭VI"), (10, "", "♭VII")]),
        Template(mood: "Reggae", minor: false, steps: [(0, "", "I"), (9, "m", "vi"), (5, "", "IV")]),
        // Anime / J-pop: the "royal road" and "just the two of us" moves
        Template(mood: "Anime", minor: false, steps: [(5, "maj7", "IVmaj7"), (7, "7", "V7"), (4, "m7", "iii7"), (9, "m", "vi")]),
        Template(mood: "Anime", minor: false, steps: [(5, "maj7", "IVmaj7"), (4, "7", "III7"), (9, "m7", "vi7"), (0, "7", "I7")]),
        Template(mood: "Anime", minor: false, steps: [(9, "m", "vi"), (5, "", "IV"), (7, "", "V"), (0, "", "I")]),
        // Arabesk / Turkish pop: harmonic-minor colour and the Andalusian fall
        Template(mood: "Arabesk", minor: true, steps: [(0, "m", "i"), (5, "m", "iv"), (7, "", "V"), (0, "m", "i")]),
        Template(mood: "Arabesk", minor: true, steps: [(0, "m", "i"), (5, "m", "iv"), (10, "", "VII"), (3, "", "III")]),
        Template(mood: "Arabesk", minor: true, steps: [(0, "m", "i"), (8, "", "VI"), (5, "m", "iv"), (7, "", "V")]),
        Template(mood: "Arabesk", minor: true, steps: [(0, "m", "i"), (7, "", "V"), (5, "m", "iv")]),
    ]

    static let lengths = 2...12

    /// `mood` "" = any. 3 or 4 chords use one template as is; other lengths chain templates of the same
    /// mood and mode in one key, so long progressions are built from phrases that work.
    static func generate(length: Int, mood: String, avoiding last: Progression? = nil) -> Progression {
        let length = min(max(length, lengths.lowerBound), lengths.upperBound)
        let exact = length == 3 || length == 4
        var pool = templates.filter { (!exact || $0.steps.count == length) && (mood.isEmpty || $0.mood == mood) }
        if pool.isEmpty { pool = templates.filter { !exact || $0.steps.count == length } }
        var result: Progression
        repeat {
            let t = pool.randomElement()!
            // Guitar-friendly keys come up more often.
            let keys = t.minor ? [9, 4, 2, 7, 0, 11, 5] : [0, 7, 2, 9, 4, 5, 10]
            let key = Bool.random() ? keys.randomElement()! : Int.random(in: 0..<12)
            var steps = t.steps.map { ProgressionStep(offset: $0.0, quality: $0.1, numeral: $0.2) }
            if !exact {
                let phrases = pool.filter { $0.minor == t.minor }
                while steps.count < length {
                    steps += phrases.randomElement()!.steps.map { ProgressionStep(offset: $0.0, quality: $0.1, numeral: $0.2) }
                }
                steps = Array(steps.prefix(length))
                // A long loop turns home best from the dominant.
                if length >= 5, let end = steps.last, end.offset != 7 && end.offset != 0 {
                    steps[length - 1] = ProgressionStep(offset: 7, quality: t.minor ? "" : "", numeral: "V")
                }
            }
            // Occasional colour on plain triads in the styles that welcome it.
            if ["Happy", "Melancholic", "Epic"].contains(t.mood), Int.random(in: 0..<3) == 0 {
                let i = Int.random(in: 0..<steps.count)
                let s = steps[i]
                if s.quality == "" {
                    let q = ["sus2", "add9", "maj7"].randomElement()!
                    steps[i] = ProgressionStep(offset: s.offset, quality: q, numeral: s.numeral + q)
                }
                if s.quality == "m" { steps[i] = ProgressionStep(offset: s.offset, quality: "m7", numeral: s.numeral + "7") }
            }
            result = Progression(key: key, minor: t.minor, mood: t.mood, steps: steps)
        } while result == last && pool.count > 1
        return result
    }

    /// A single random chord, weighted towards the ones people actually play.
    static func randomChord() -> (root: Int, quality: String) {
        let weighted: [(String, Int)] = [("", 6), ("m", 6), ("7", 4), ("maj7", 3), ("m7", 4), ("sus2", 2), ("sus4", 2),
                                         ("add9", 2), ("6", 1), ("m6", 1), ("9", 1), ("dim", 1), ("aug", 1),
                                         ("m7♭5", 1), ("7sus4", 1), ("5", 1)]
        let total = weighted.reduce(0) { $0 + $1.1 }
        var r = Int.random(in: 0..<total)
        for (q, w) in weighted {
            if r < w { return (Int.random(in: 0..<12), q) }
            r -= w
        }
        return (0, "")
    }
}

// MARK: - Hand editing

extension Progressions {
    private static let majorDegrees = ["I", "♭II", "II", "♭III", "III", "IV", "♭V", "V", "♭VI", "VI", "♭VII", "VII"]
    private static let minorDegrees = ["I", "♭II", "II", "III", "♯III", "IV", "♭V", "V", "VI", "♯VI", "VII", "♯VII"]
    private static let suffixes: [String: String] = [
        "m": "", "m7": "7", "m6": "6", "m9": "9", "m11": "11", "madd9": "add9", "mMaj7": "maj7",
        "dim": "°", "dim7": "°7", "m7♭5": "ø7", "aug": "+", "7♯5": "+7",
    ]

    /// The key's seven chords: (semitones above the tonic, quality).
    static func diatonic(minor: Bool) -> [(offset: Int, quality: String)] {
        minor ? [(0, "m"), (2, "dim"), (3, ""), (5, "m"), (7, "m"), (8, ""), (10, "")]
              : [(0, ""), (2, "m"), (4, "m"), (5, ""), (7, ""), (9, "m"), (11, "dim")]
    }

    /// Roman numeral relative to the key: case from the chord's third, accidentals from the key's own scale.
    static func numeral(offset: Int, quality: String, minor: Bool) -> String {
        let o = ((offset % 12) + 12) % 12
        let intervals = Set(Chords.quality(quality).intervals.map { $0 % 12 })
        let dim = ["dim", "dim7", "m7♭5"].contains(quality)
        var degree = minor ? minorDegrees[o] : majorDegrees[o]
        // The leading-tone chord in minor is plain vii°; diminished passing chords read as raised steps.
        if dim {
            let raised = minor ? [1: "♯I", 6: "♯IV", 11: "VII"] : [1: "♯I", 3: "♯II", 6: "♯IV", 8: "♯V", 10: "♯VI"]
            degree = raised[o] ?? degree
        }
        let lower: Bool
        if intervals.contains(4) { lower = false }
        else if intervals.contains(3) { lower = true }
        else {
            // No third (power, sus): follow the key's own chord on that step.
            lower = diatonic(minor: minor).first { $0.offset == o }.map { $0.quality == "m" || $0.quality == "dim" } ?? false
                && o != 7
        }
        return (lower ? degree.lowercased() : degree) + (suffixes[quality] ?? quality)
    }

    static func step(offset: Int, quality: String, minor: Bool) -> ProgressionStep {
        let o = ((offset % 12) + 12) % 12
        return ProgressionStep(offset: o, quality: quality, numeral: numeral(offset: o, quality: quality, minor: minor))
    }

    /// A key chord that follows the last one well and leads back to the first, in the progression's colour
    /// (7ths when most chords have them, power chords for riffs).
    static func fittingChord(after steps: [ProgressionStep], minor: Bool) -> ProgressionStep {
        func motion(_ a: Int, _ b: Int) -> Double {
            switch (a, b) {
            case (7, 0): return 0.16
            case (2, 7): return 0.1
            case (5, 7): return 0.07
            case (7, 9): return minor ? 0 : 0.06
            case (5, 0), (10, 0): return 0.05
            case (9, 5), (9, 2), (4, 9): return minor ? 0 : 0.05
            case (0, 5), (0, 7), (0, 9): return 0.04
            case (8, 10), (0, 8), (8, 3), (3, 10), (10, 3), (3, 8), (3, 5), (10, 8): return minor ? 0.05 : 0
            default: return 0
            }
        }
        let prior: [Int: Double] = minor ? [0: 0.2, 2: 0, 3: 0.1, 5: 0.14, 7: 0.12, 8: 0.13, 10: 0.12]
                                         : [0: 0.2, 2: 0.1, 4: 0.05, 5: 0.16, 7: 0.17, 9: 0.13, 11: 0]
        let last = steps.last?.offset, first = steps.first?.offset
        let pick = diatonic(minor: minor).max { a, b in
            func score(_ c: (offset: Int, quality: String)) -> Double {
                var s = prior[c.offset] ?? 0
                if let last { s += c.offset == last ? -1 : motion(last, c.offset) }
                if let first { s += 0.6 * motion(c.offset, first) }
                return s - 0.03 * Double(steps.filter { $0.offset == c.offset }.count) + Double.random(in: 0...0.04)
            }
            return score(a) < score(b)
        }!
        // Minor keys cadence on the major V.
        var quality = minor && pick.offset == 7 ? "" : pick.quality
        let n = steps.count
        if n > 0, steps.filter({ $0.quality == "5" }).count * 2 >= n {
            quality = "5"
        } else if n > 0, steps.filter({ ["7", "maj7", "m7", "m7♭5", "9", "maj9", "m9", "13", "6", "m6"].contains($0.quality) }).count * 2 >= n {
            quality = ["": pick.offset == 7 ? "7" : "maj7", "m": "m7", "dim": "m7♭5"][quality] ?? quality
        }
        return step(offset: pick.offset, quality: quality, minor: minor)
    }
}
