import Foundation

struct ChordQuality: Identifiable, Hashable {
    /// Suffix as written after the root ("" for major).
    let id: String
    let name: String
    /// Semitones above the root; 13 and up are extensions (9, 11, 13).
    let intervals: [Int]
    /// Tones that may be left out of a voicing.
    let optional: Set<Int>
    var symbol: String { id.isEmpty ? "maj" : id }

    func label(_ interval: Int) -> String {
        if id == "dim7" && interval == 9 { return "𝄫7" }
        if (id == "6" || id == "m6" || id == "6/9") && interval == 9 { return "6" }
        switch interval {
        case 0: return "R"
        case 1, 13: return "♭9"
        case 2: return "2"
        case 3: return "♭3"
        case 4: return "3"
        case 5: return "4"
        case 6: return "♭5"
        case 7: return "5"
        case 8: return "♯5"
        case 9: return "6"
        case 10: return "♭7"
        case 11: return "7"
        case 14: return "9"
        case 15: return "♯9"
        case 17: return "11"
        case 21: return "13"
        default: return "?"
        }
    }
}

enum Chords {
    static let qualities: [ChordQuality] = [
        q("", "major", [0, 4, 7], opt: [7]),
        q("m", "minor", [0, 3, 7], opt: [7]),
        q("5", "power chord", [0, 7]),
        q("7", "dominant 7th", [0, 4, 7, 10], opt: [7]),
        q("maj7", "major 7th", [0, 4, 7, 11], opt: [7]),
        q("m7", "minor 7th", [0, 3, 7, 10], opt: [7]),
        q("sus2", "suspended 2nd", [0, 2, 7]),
        q("sus4", "suspended 4th", [0, 5, 7]),
        q("7sus4", "7th suspended 4th", [0, 5, 7, 10], opt: [7]),
        q("add9", "added 9th", [0, 4, 7, 14], opt: [7]),
        q("madd9", "minor added 9th", [0, 3, 7, 14], opt: [7]),
        q("6", "major 6th", [0, 4, 7, 9], opt: [7]),
        q("m6", "minor 6th", [0, 3, 7, 9], opt: [7]),
        q("6/9", "six-nine", [0, 4, 7, 9, 14], opt: [7]),
        q("9", "dominant 9th", [0, 4, 7, 10, 14], opt: [7]),
        q("maj9", "major 9th", [0, 4, 7, 11, 14], opt: [7]),
        q("m9", "minor 9th", [0, 3, 7, 10, 14], opt: [7]),
        q("11", "dominant 11th", [0, 4, 7, 10, 14, 17], opt: [4, 7, 14]),
        q("m11", "minor 11th", [0, 3, 7, 10, 14, 17], opt: [7, 14]),
        q("13", "dominant 13th", [0, 4, 7, 10, 14, 21], opt: [7, 14]),
        q("dim", "diminished", [0, 3, 6]),
        q("dim7", "diminished 7th", [0, 3, 6, 9]),
        q("m7♭5", "half-diminished", [0, 3, 6, 10]),
        q("aug", "augmented", [0, 4, 8]),
        q("7♯5", "augmented 7th", [0, 4, 8, 10]),
        q("7♭9", "dominant 7th ♭9", [0, 4, 7, 10, 13], opt: [7]),
        q("7♯9", "dominant 7th ♯9", [0, 4, 7, 10, 15], opt: [7]),
        q("mMaj7", "minor major 7th", [0, 3, 7, 11], opt: [7]),
    ]

    private static func q(_ id: String, _ name: String, _ iv: [Int], opt: Set<Int> = []) -> ChordQuality {
        ChordQuality(id: id, name: name, intervals: iv, optional: opt)
    }

    static func quality(_ id: String) -> ChordQuality { qualities.first { $0.id == id } ?? qualities[0] }

    // MARK: - Parsing ("C#m7", "Bbmaj7", "F♯ø", "Gsus")

    private static let aliases: [String: String] = [
        "": "", "maj": "", "major": "", "m": "m", "min": "m", "minor": "m", "-": "m",
        "5": "5", "7": "7", "dom7": "7", "maj7": "maj7", "Δ": "maj7", "Δ7": "maj7", "ma7": "maj7",
        "m7": "m7", "min7": "m7", "-7": "m7", "sus2": "sus2", "sus4": "sus4", "sus": "sus4",
        "7sus4": "7sus4", "7sus": "7sus4", "add9": "add9", "add2": "add9", "madd9": "madd9", "minadd9": "madd9",
        "6": "6", "m6": "m6", "min6": "m6", "6/9": "6/9", "69": "6/9", "9": "9", "maj9": "maj9", "m9": "m9",
        "min9": "m9", "11": "11", "m11": "m11", "min11": "m11", "13": "13", "dim": "dim", "°": "dim",
        "o": "dim", "dim7": "dim7", "°7": "dim7", "o7": "dim7", "m7b5": "m7♭5", "ø": "m7♭5", "ø7": "m7♭5",
        "min7b5": "m7♭5", "aug": "aug", "+": "aug", "7#5": "7♯5", "+7": "7♯5", "aug7": "7♯5",
        "7b9": "7♭9", "7#9": "7♯9", "mmaj7": "mMaj7", "minmaj7": "mMaj7", "m(maj7)": "mMaj7", "-maj7": "mMaj7",
    ]

    static func parse(_ text: String) -> (root: Int, quality: String)? {
        var s = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
        guard let first = s.first?.uppercased().first,
              let base = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11][String(first)] else { return nil }
        s.removeFirst()
        var root = base
        if s.hasPrefix("#") { root += 1; s.removeFirst() } else if s.hasPrefix("b") { root -= 1; s.removeFirst() }
        // "M7" means major 7th; anything else is case-insensitive.
        if s.hasPrefix("M") && !s.hasPrefix("Maj") && !s.hasPrefix("Major") { s = "maj" + s.dropFirst() }
        let key = s.lowercased().replacingOccurrences(of: " ", with: "")
        let match = aliases.first { $0.key.lowercased() == key }
        guard let quality = match?.value else { return nil }
        return ((root + 12) % 12, quality)
    }

    // MARK: - Voicings

    struct Voicing: Hashable {
        /// Fret per string (nil = muted, 0 = open), in tuning order.
        let frets: [Int?]
        let fingers: [Int?]
        /// Index-finger barre: fret and the string range it covers.
        let barre: (fret: Int, from: Int, to: Int)?
        let score: Double

        var lowestFret: Int { frets.compactMap { $0 }.filter { $0 > 0 }.min() ?? 0 }
        var highestFret: Int { frets.compactMap { $0 }.max() ?? 0 }

        static func == (a: Voicing, b: Voicing) -> Bool { a.frets == b.frets }
        func hash(into h: inout Hasher) { h.combine(frets) }
    }

    /// Generates playable shapes for any tuning by search: every combination of chord tones inside a
    /// hand-sized fret window, filtered for completeness and fingering, ranked by how natural it plays.
    static func voicings(root: Int, quality: ChordQuality, instrument: Instrument, tuning: Tuning) -> [Voicing] {
        let strings = tuning.notes
        let n = strings.count
        let toneOf: [Int: Int] = Dictionary(quality.intervals.map { ((root + $0) % 12, $0) }, uniquingKeysWith: { a, _ in a })
        var required = Set(quality.intervals.filter { !quality.optional.contains($0) }.map { (root + $0) % 12 })
        let drones = instrument.drones
        let playable = n - drones.count
        if required.count > playable {
            // Too few strings for every tone: keep the ones that define the sound (3rd/7th/extension) over the root.
            required.remove(root % 12)
        }
        let minSounding: Int = {
            if quality.id == "5" { return 2 }
            if n >= 6 { return 4 }
            return max(2, n - 1)
        }()
        let maxFret = min(instrument.frets, 15)
        let span = instrument.span

        var found: [[Int?]: Voicing] = [:]
        var current = [Int?](repeating: nil, count: n)

        for start in 1...max(1, maxFret - span) {
            let window = start...(start + span)
            let options: [[Int?]] = (0..<n).map { s in
                var o: [Int?] = [nil]
                if toneOf[strings[s] % 12] != nil { o.append(0) }
                if !drones.contains(s) {
                    for f in window where toneOf[(strings[s] + f) % 12] != nil { o.append(f) }
                }
                return o
            }
            func dfs(_ s: Int) {
                if s == n {
                    if let v = evaluate(current) { if found[v.frets].map({ v.score < $0.score }) ?? true { found[v.frets] = v } }
                    return
                }
                for o in options[s] {
                    current[s] = o
                    dfs(s + 1)
                }
            }
            dfs(0)
        }

        func evaluate(_ frets: [Int?]) -> Voicing? {
            let sounding = frets.indices.filter { frets[$0] != nil }
            guard sounding.count >= minSounding else { return nil }
            let pcs = Set(sounding.map { (strings[$0] + frets[$0]!) % 12 })
            guard required.isSubset(of: pcs) else { return nil }
            if instrument.pitchOrdered {
                let bass = sounding.min { strings[$0] + frets[$0]! < strings[$1] + frets[$1]! }!
                guard (strings[bass] + frets[bass]!) % 12 == root % 12 else { return nil }
            }
            let fretted = sounding.filter { frets[$0]! > 0 }
            let minF = fretted.map { frets[$0]! }.min() ?? 0
            let maxF = fretted.map { frets[$0]! }.max() ?? 0
            guard maxF - minF <= span else { return nil }

            // Fingering: one finger per fretted note, or an index barre across the lowest fret.
            var barre: (Int, Int, Int)? = nil
            let atMin = fretted.filter { frets[$0]! == minF }
            var fingersNeeded = fretted.count
            if atMin.count >= 2, let lo = atMin.first, let hi = atMin.last {
                let covered = (lo...hi)
                let blocked = covered.contains { frets[$0] == nil || frets[$0] == 0 }
                if !blocked {
                    barre = (minF, lo, hi)
                    fingersNeeded = 1 + fretted.filter { frets[$0]! > minF }.count
                }
            }
            guard fingersNeeded <= 4 else { return nil }

            // Mutes: bass-side mutes are normal on guitar; inner and treble-side mutes are harder.
            let first = sounding.first!, last = sounding.last!
            let innerMutes = (first...last).filter { frets[$0] == nil }.count
            // Skipping an inner string is a jazz-grip technique for 7th chords and up, never for triads.
            guard innerMutes == 0 || (innerMutes == 1 && quality.intervals.count >= 4 && n >= 6) else { return nil }
            let topMutes = (n - 1) - last
            let bassMutes = (0..<first).filter { !drones.contains($0) }.count
            let opens = sounding.filter { frets[$0] == 0 && !drones.contains($0) }.count

            // `score` judges the grip itself; the position term only orders shapes, it never filters them.
            var score = 0.0
            score += Double(fingersNeeded) * 0.55
            score += [0, 0.3, 0.8, 1.8, 3.0][min(4, maxF - minF)]
            score -= Double(sounding.count) * 1.0
            score += Double(innerMutes) * 3
            if quality.id != "5" { score += Double(topMutes) * 1.4 }
            // Power chords live on the bass strings.
            if quality.id == "5" && instrument.pitchOrdered { score += Double(bassMutes) * 0.8 }
            if !instrument.pitchOrdered { score += Double(bassMutes) * 1.5 }
            if barre != nil { score += 0.6 }
            // Open strings belong with low grips; mixed into a high shape they rarely sound or sit right.
            if maxF > span { score += Double(opens * (maxF - span)) * 1.2 }
            if !pcs.contains((root + 7) % 12) && quality.intervals.contains(7) { score += 0.4 }
            if !pcs.contains(root % 12) { score += 0.8 }

            let fingers = assignFingers(frets, barre: barre, minF: minF)
            return Voicing(frets: frets, fingers: fingers, barre: barre.map { (fret: $0.0, from: $0.1, to: $0.2) },
                           score: score + Double(minF) * 0.4)
        }

        // Best shape per hand position, then drop positions that are much worse than the best overall.
        var byPosition: [Int: Voicing] = [:]
        func position(_ v: Voicing) -> Int {
            v.highestFret <= max(3, span) && v.frets.enumerated().contains { $0.element == 0 && !drones.contains($0.offset) }
                ? 0 : v.lowestFret
        }
        for v in found.values {
            let key = position(v)
            if byPosition[key].map({ v.score < $0.score }) ?? true { byPosition[key] = v }
        }
        guard let best = byPosition.values.map({ $0.score - Double($0.lowestFret) * 0.4 }).min() else { return [] }
        var result = byPosition.values.filter { $0.score - Double($0.lowestFret) * 0.4 <= best + 3.3 }
        // Neighbouring positions often produce the same grip shifted by one fret; keep the better one.
        result.sort { position($0) < position($1) }
        var pruned: [Voicing] = []
        for v in result {
            if let prev = pruned.last, position(v) - position(prev) == 1, isShift(prev, v) {
                if v.score < prev.score { pruned[pruned.count - 1] = v }
                continue
            }
            pruned.append(v)
        }
        // Most common grip first, the rest up the neck.
        pruned = Array(pruned.sorted { $0.score < $1.score }.prefix(8))
        let first = pruned.removeFirst()
        return [first] + pruned.sorted { position($0) < position($1) }
    }

    private static func isShift(_ a: Voicing, _ b: Voicing) -> Bool {
        let sa = a.frets.map { $0 == nil }, sb = b.frets.map { $0 == nil }
        return sa == sb
    }

    private static func assignFingers(_ frets: [Int?], barre: (Int, Int, Int)?, minF: Int) -> [Int?] {
        var fingers = [Int?](repeating: nil, count: frets.count)
        var notes = frets.indices.filter { (frets[$0] ?? 0) > 0 }
        if let b = barre {
            for s in notes where frets[s] == b.0 { fingers[s] = 1 }
            notes.removeAll { frets[$0] == b.0 }
        }
        notes.sort { (frets[$0]!, $0) < (frets[$1]!, $1) }
        var prev = barre == nil ? 0 : 1
        for (i, s) in notes.enumerated() {
            // Leave enough fingers for the notes still to place (e.g. three notes on one fret → 2 3 4).
            let remaining = notes.count - i - 1
            let wanted = min(frets[s]! - minF + 1, 4 - remaining)
            let f = min(4, max(wanted, prev + 1))
            fingers[s] = f
            prev = f
        }
        return fingers
    }
}
