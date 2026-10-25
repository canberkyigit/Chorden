import Foundation

/// What the bass plays under the progression.
enum BassStyle: String, CaseIterable {
    case off, auto, roots, rootFifth, eighths, octaves, walking, oneDrop, bossa

    var name: String {
        switch self {
        case .off: "Off"
        case .auto: "Auto"
        case .roots: "Roots"
        case .rootFifth: "Root–fifth"
        case .eighths: "Pop eighths"
        case .octaves: "Octaves"
        case .walking: "Walking"
        case .oneDrop: "One drop"
        case .bossa: "Bossa nova"
        }
    }
}

/// What the piano comps over the progression.
enum KeysStyle: String, CaseIterable {
    case off, auto, pads, ballad, arpeggio, stabs, jazz, skank

    var name: String {
        switch self {
        case .off: "Off"
        case .auto: "Auto"
        case .pads: "Pads"
        case .ballad: "Broken chords"
        case .arpeggio: "Arpeggio"
        case .stabs: "Stabs"
        case .jazz: "Jazz comping"
        case .skank: "Reggae skank"
        }
    }
}

/// The bass player and pianist behind the strumming: beat by beat, which notes they play. Pure music;
/// `ProgressionPlayer` puts the notes on the clock. Lines are voice-led, so it keeps a little memory.
final class BackingBand {
    /// One note or chord: absolute beat, MIDI notes, length in beats.
    struct Event: Equatable {
        let beat: Double
        let notes: [Int]
        let length: Double
        let velocity: Double
    }

    /// Everything the players need to know about the beat being played.
    struct Beat {
        /// Absolute beat (whole number) and its place in the drummer's 4/4 bar.
        let beat: Double
        let barPos: Double
        /// Beats since this chord started, and how long chords last.
        let inChord: Double
        let chordBeats: Double
        let root: Int
        let quality: ChordQuality
        let nextRoot: Int
        let nextQuality: ChordQuality
        let key: Int
        let minor: Bool
        let drums: DrumPattern
    }

    /// The styles Auto picks, so the band fits the groove: drums first, then the strumming.
    static func auto(drums: DrumPattern, rhythm: StrumPattern) -> (bass: BassStyle, keys: KeysStyle) {
        switch drums {
        case .jazz, .shuffle: return (.walking, .jazz)
        case .bossa: return (.bossa, .pads)
        case .reggae: return (.oneDrop, .skank)
        case .rock: return (.eighths, .pads)
        case .disco, .funk: return (.octaves, .stabs)
        case .ballad: return (.roots, [.arpeggio, .travis].contains(rhythm) ? .pads : .ballad)
        case .hiphop, .halftime: return (.roots, .pads)
        case .off, .click, .groove: break
        }
        switch rhythm {
        case .whole, .arpeggio, .travis: return (.roots, .pads)
        case .quarters, .downUp, .folk: return (.rootFifth, .pads)
        case .pop16, .rock: return (.eighths, .pads)
        case .chug, .gallop: return (.eighths, .off)
        case .shuffle: return (.walking, .jazz)
        case .reggae: return (.oneDrop, .skank)
        case .funk: return (.octaves, .stabs)
        case .bossa: return (.bossa, .pads)
        }
    }

    private var lastRoot: Int?
    private var bassRoot: (key: String, midi: Int)?
    private var walk: (key: String, notes: [Int])?
    /// Where the walking line is headed: the next chord's root, in the octave the approach leads to.
    private var walkGoal: Int?
    private var lastVoicing: [Int]?
    private var voicing: (key: String, notes: [Int])?

    func reset() {
        lastRoot = nil
        bassRoot = nil
        walk = nil
        walkGoal = nil
        lastVoicing = nil
        voicing = nil
    }

    // MARK: - Bass

    /// Electric bass range used: E1 (open low E) up to G3.
    static let bassLow = 28, bassHigh = 55

    func bass(_ style: BassStyle, _ b: Beat) -> [Event] {
        let chordStart = b.beat - b.inChord
        let chordEnd = chordStart + b.chordBeats
        if style == .walking {
            let note = walking(b)
            // Quarter notes, legato, a touch more weight on 2 and 4.
            let accent = Int(b.inChord) % 2 == 1
            return [Event(beat: b.beat, notes: [note], length: 0.9, velocity: accent ? 0.8 : 0.72)]
        }
        let bar = Self.bassBar(style, drums: b.drums)
        guard !bar.isEmpty else { return [] }
        // Octave lines start low, so the octave above stays in the bass's register.
        let root = rootNote(b, high: style == .octaves ? Self.bassHigh - 12 : 45)
        var hits = bar.filter { $0.at >= b.barPos - 0.001 && $0.at < b.barPos + 0.999 }
        // A new chord always gets its root on its first beat, even where the bar's pattern rests.
        if b.inChord == 0 {
            if let i = hits.firstIndex(where: { abs($0.at - b.barPos) < 0.001 }) {
                hits[i] = Hit(at: b.barPos, role: .root, length: hits[i].length, velocity: max(hits[i].velocity, 0.82))
            } else {
                let next = bar.map { $0.at <= b.barPos ? $0.at + 4 : $0.at }.min() ?? b.barPos + 4
                hits.insert(Hit(at: b.barPos, role: .root, length: min(1.9, (next - b.barPos) * 0.9), velocity: 0.84), at: 0)
            }
        }
        return hits.map { h in
            let at = b.beat + h.at - b.barPos
            // A note never rings into the next chord.
            let length = max(0.2, min(h.length, chordEnd - at - 0.06))
            let note: Int
            switch h.role {
            case .root: note = root
            case .fifth: note = Self.fifthNote(root, b.quality)
            case .octave: note = root + 12 <= Self.bassHigh ? root + 12 : root
            }
            return Event(beat: at, notes: [note], length: length, velocity: h.velocity)
        }
    }

    private struct Hit {
        enum Role { case root, fifth, octave }
        let at: Double
        let role: Role
        let length: Double
        let velocity: Double
    }

    /// One 4/4 bar of each style, on the drummer's grid.
    private static func bassBar(_ style: BassStyle, drums: DrumPattern) -> [Hit] {
        switch style {
        case .off, .auto, .walking:
            return []
        case .roots:
            // Locked to the kick drum: a root wherever the kick lands (ghost and feathered kicks aside).
            var kicks = Array(Set(drums.bar.filter { $0.1 == .kick && $0.2 >= 0.5 }.map(\.0))).sorted()
            if kicks.count < 2 { kicks = Array(Set(kicks + [0, 2])).sorted() }
            if kicks.first != 0 { kicks.insert(0, at: 0) }
            return kicks.enumerated().map { i, at in
                let next = i + 1 < kicks.count ? kicks[i + 1] : 4
                return Hit(at: at, role: .root, length: min(1.9, (next - at) * 0.9), velocity: at == 0 ? 0.88 : 0.76)
            }
        case .rootFifth:
            // Two-beat: root on one, fifth on three, a little detached.
            return [Hit(at: 0, role: .root, length: 1.3, velocity: 0.86), Hit(at: 2, role: .fifth, length: 1.3, velocity: 0.78)]
        case .eighths:
            return (0..<8).map { Hit(at: Double($0) * 0.5, role: .root, length: 0.42, velocity: $0 % 2 == 0 ? 0.84 : 0.68) }
        case .octaves:
            // Disco: low root on the beat, the octave on the off-beat.
            return (0..<8).map { Hit(at: Double($0) * 0.5, role: $0 % 2 == 0 ? .root : .octave, length: 0.36,
                                     velocity: $0 % 2 == 0 ? 0.86 : 0.72) }
        case .oneDrop:
            // Deep root on one, then space; it answers the drop on three.
            return [Hit(at: 0, role: .root, length: 1.35, velocity: 0.88), Hit(at: 2, role: .root, length: 0.42, velocity: 0.8),
                    Hit(at: 2.5, role: .fifth, length: 0.4, velocity: 0.7)]
        case .bossa:
            // Surdo-like: root, fifth anticipating three, fifth, root anticipating the next bar.
            return [Hit(at: 0, role: .root, length: 1.35, velocity: 0.84), Hit(at: 1.5, role: .fifth, length: 0.42, velocity: 0.7),
                    Hit(at: 2, role: .fifth, length: 1.35, velocity: 0.78), Hit(at: 3.5, role: .root, length: 0.42, velocity: 0.68)]
        }
    }

    /// The chord's root in a comfortable octave, close to the last root (roots move by small steps).
    private func rootNote(_ b: Beat, high: Int) -> Int {
        let key = "\(b.beat - b.inChord) \(b.root) \(b.quality.id) \(high)"
        if let r = bassRoot, r.key == key { return r.midi }
        let midi = Self.nearest(b.root, to: Double(lastRoot ?? 35), high: high)
        bassRoot = (key, midi)
        lastRoot = midi
        return midi
    }

    /// Pitch class `pc` between E1 and `high`, nearest `near` but drawn towards B1, the bass's home.
    private static func nearest(_ pc: Int, to near: Double, high: Int = 45) -> Int {
        let first = bassLow + (pc - bassLow % 12 + 12) % 12
        return stride(from: first, through: max(first, high), by: 12).min { a, c in
            abs(Double(a) - near) + 0.35 * abs(Double(a) - 35) < abs(Double(c) - near) + 0.35 * abs(Double(c) - 35)
        }!
    }

    static func fifthInterval(_ q: ChordQuality) -> Int {
        let iv = Set(q.intervals)
        return iv.contains(7) ? 7 : iv.contains(6) ? 6 : iv.contains(8) ? 8 : 7
    }

    /// The fifth above a low root, below a high one.
    static func fifthNote(_ root: Int, _ q: ChordQuality) -> Int {
        let f = fifthInterval(q)
        return root + f <= 45 ? root + f : root + f - 12
    }

    /// Walking bass: four to the bar, from the chord's root to a note that leads into the next chord.
    private func walking(_ b: Beat) -> Int {
        let segStart = (b.inChord / 4).rounded(.down) * 4
        let length = Int(min(4, b.chordBeats - segStart))
        let k = Int(b.inChord - segStart)
        let last = segStart + 4 >= b.chordBeats
        let key = "\(b.beat - b.inChord + segStart) \(b.root)\(b.quality.id) \(last ? b.nextRoot : -1)\(b.nextQuality.id) \(length)"
        if walk?.key != key {
            // Land where the last run was headed; the very first note sits low.
            let start = walkGoal.flatMap { $0 % 12 == b.root ? $0 : nil } ?? Self.nearest(b.root, to: 35)
            let line = walkLine(b, start: start, beats: length, into: last ? b.nextRoot : b.root,
                                seed: UInt64(max(0, b.beat - b.inChord + segStart)) &+ UInt64(b.root * 31))
            walk = (key, line.notes)
            walkGoal = line.goal
        }
        let notes = walk!.notes
        return notes[min(k, notes.count - 1)]
    }

    private func walkLine(_ b: Beat, start: Int, beats: Int, into target: Int, seed: UInt64) -> (notes: [Int], goal: Int) {
        var rng = SplitMix(seed: seed)
        let lo = Self.bassLow, hi = 52
        // Where the line is headed: the next root in the octave nearest the start (the other one when that's
        // the note it starts on, so a chord held two bars still moves).
        var options = Array(stride(from: lo + (target - lo % 12 + 12) % 12, through: 45, by: 12))
        options.sort { abs($0 - start) < abs($1 - start) }
        var goal = options.first ?? target + 36
        if goal == start, options.count > 1 { goal = options[1] }
        // The approach on the last beat: chromatic from below or above, a scale step, or the dominant.
        let scale = Set((b.minor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]).map { (b.key + $0) % 12 })
        let r = rng.next()
        var approach: Int
        if r < 0.32 { approach = goal - 1 }
        else if r < 0.55 { approach = goal + 1 }
        else if r < 0.85 {
            let up = rng.next() < 0.5
            approach = up ? (goal + 1...goal + 2).first { scale.contains(($0 % 12 + 12) % 12) } ?? goal + 2
                          : (goal - 2...goal - 1).reversed().first { scale.contains(($0 % 12 + 12) % 12) } ?? goal - 2
        } else {
            // From the dominant: the fifth above or the fourth below, whichever is nearer.
            approach = [goal + 7, goal - 5].filter { (lo...hi).contains($0) && $0 % 12 != start % 12 }
                .min { abs($0 - start) < abs($1 - start) } ?? goal - 1
        }
        if approach < lo || approach > hi { approach = goal + (approach < lo ? 1 : -1) }
        if approach == start { approach = goal + (goal > start ? -1 : 1) }
        if beats <= 2 { return (beats == 1 ? [start] : [start, approach], goal) }

        // Two notes in between: chord tones and scale steps, moving smoothly and mostly one way.
        let chordPCs = Set(b.quality.intervals.map { (b.root + $0) % 12 })
        let pool = (lo...hi).filter { chordPCs.contains($0 % 12) || scale.contains($0 % 12) }
        var best: (cost: Double, x: Int, y: Int) = (.infinity, start, approach)
        for x in pool where x != start && abs(x - start) <= 7 {
            for y in pool where y != x && y != approach && abs(y - x) <= 7 && abs(approach - y) <= 5 {
                let moves = [x - start, y - x, approach - y]
                var cost = Double(moves.map(abs).reduce(0, +)) * 0.45
                cost += Double(zip(moves, moves.dropFirst()).filter { $0.0 * $0.1 < 0 }.count) * 1.2
                if !chordPCs.contains(x % 12) { cost += 2.2 }
                if !chordPCs.contains(y % 12) { cost += 0.8 }
                if moves.contains(where: { abs($0) > 5 }) { cost += 1.0 }
                if y == start { cost += 1.5 }
                // Arriving early at the next root takes the surprise out of landing on it.
                if y % 12 == goal % 12 { cost += 2.5 }
                if x % 12 == goal % 12 { cost += 1.2 }
                cost += rng.next() * 1.6
                if cost < best.cost { best = (cost, x, y) }
            }
        }
        return ([start, best.x, best.y, approach], goal)
    }

    // MARK: - Keys

    /// Keys stay between E3 and C5, clear of the bass and under the guitar's top strings.
    func keys(_ style: KeysStyle, _ b: Beat, bassPlaying: Bool, high register: Bool = false) -> [Event] {
        // Chops sit higher and brighter; pads, broken chords and comping in the middle.
        let lift = (style == .skank || style == .stabs ? 4 : 0) + (register ? 12 : 0)
        let v = chordVoicing(b, rootless: style == .jazz || bassPlaying, ninth: style == .jazz, shift: lift)
        guard !v.isEmpty else { return [] }
        let chordStart = b.beat - b.inChord
        let p = b.inChord.truncatingRemainder(dividingBy: 4)
        // Hits of the current chord-bar: (offset in the bar, notes, length, velocity).
        var hits: [(Double, [Int], Double, Double)] = []
        switch style {
        case .off, .auto:
            return []
        case .pads:
            // Struck softly and held, again each bar.
            hits = [(0, v, 4, 0.4)]
        case .ballad:
            // Broken chord with the pedal down: low, middle, top, middle.
            let mid = v.count > 2 ? Array(v.dropFirst().dropLast()) : [v.last!]
            hits = [(0, [v.first!], 4, 0.44), (1, mid, 3, 0.34), (2, [v.last!], 2, 0.38), (3, mid, 1, 0.32)]
        case .arpeggio:
            // Eighths up and back down, the top an octave above the bottom; each note left to ring.
            let line = v + [v.first! + 12]
            let order = [0, 1, 2, 3, 2, 1, 2, 1].map { min($0, line.count - 1) }
            hits = (0..<8).map { (Double($0) * 0.5, [line[order[$0]]], 1.1, $0 % 2 == 0 ? 0.4 : 0.33) }
        case .stabs:
            hits = (0..<4).map { (Double($0) + 0.5, v, 0.24, 0.46) }
        case .skank:
            // Short chops on two and four, the right hand only.
            let upper = v.count > 3 ? Array(v.dropFirst()) : v
            hits = [(1, upper, 0.2, 0.4), (3, upper, 0.2, 0.4)]
        case .jazz:
            // Charleston on the chord's first bar ("one, and-of-two"); after that "and-of-two, four".
            let bar = Int(b.inChord / 4)
            hits = bar == 0 ? [(0, v, 1.1, 0.46), (1.5, v, 0.4, 0.4)] : [(1.5, v, 0.5, 0.4), (3, v, 0.8, 0.37)]
        }
        return hits.compactMap { off, notes, len, vel in
            guard off >= p - 0.001, off < p + 0.999 else { return nil }
            let at = chordStart + b.inChord - p + off
            guard at < chordStart + b.chordBeats - 0.01 else { return nil }
            let left = chordStart + b.chordBeats - at
            return Event(beat: at, notes: notes, length: max(0.15, min(len, left - 0.05)), velocity: vel)
        }
    }

    /// Chord tones voiced close, as near as possible to the last chord (common tones held, the rest moving by step).
    private func chordVoicing(_ b: Beat, rootless: Bool, ninth: Bool, shift: Int) -> [Int] {
        let key = "\(b.beat - b.inChord) \(b.root) \(b.quality.id) \(rootless) \(ninth) \(shift)"
        if let v = voicing, v.key == key { return v.notes }
        var q = b.quality
        // Jazz pianists colour plain sevenths with the ninth (3-5-7-9, rootless).
        let iv = Set(q.intervals)
        if ninth, iv.contains(10) || iv.contains(11), !iv.contains(where: { $0 > 12 }), !iv.contains(6) {
            q = ChordQuality(id: q.id + "9", name: q.name, intervals: q.intervals + [14], optional: q.optional)
        }
        let notes = Self.voice(root: b.root, quality: q, rootless: rootless, previous: lastVoicing,
                               low: 52 + shift, high: 74 + shift, center: 62 + Double(shift))
        voicing = (key, notes)
        lastVoicing = notes
        return notes
    }

    static func voice(root: Int, quality: ChordQuality, rootless: Bool, previous: [Int]?,
                      low: Int, high: Int, center: Double) -> [Int] {
        // Pitch classes above the root, most important first: third, seventh, colour tones, fifth, root.
        var seen = Set<Int>()
        let tones = quality.intervals.map { $0 % 12 }.filter { seen.insert($0).inserted }
        func rank(_ i: Int) -> Int {
            switch i {
            case 3, 4: 0
            case 10, 11: 1
            case 9 where tones.contains(3) && tones.contains(6): 1  // dim7's double-flat seventh
            case 0: 5
            case 7: 4
            case 5 where !tones.contains(3) && !tones.contains(4): 0  // sus4
            case 2 where !tones.contains(3) && !tones.contains(4): 0  // sus2
            default: 2
            }
        }
        var keep = tones.sorted { rank($0) < rank($1) }
        if rootless && keep.count >= 4 { keep.removeAll { $0 == 0 } }
        if keep.count > 4, tones.contains(7), !quality.id.contains("5") { keep.removeAll { $0 == 7 } }
        keep = Array(keep.prefix(4))
        var pcs = keep.map { (root + $0) % 12 }.sorted()
        // A power chord gets its root doubled on top: root, fifth, octave.
        let doubled = pcs.count < 3
        if doubled { pcs = Array(Set(pcs)).sorted() }

        var candidates: [[Int]] = []
        for (i, first) in pcs.enumerated() {
            let order = Array(pcs[i...] + pcs[..<i]) + (doubled ? [first] : [])
            for octave in stride(from: low - 12, through: high, by: 12) {
                var n = octave + (first - octave % 12 + 12) % 12
                guard n >= low else { continue }
                var v = [n]
                for pc in order.dropFirst() {
                    n += (pc - n % 12 + 12) % 12
                    if n == v.last! { n += 12 }
                    v.append(n)
                }
                if v.last! <= high { candidates.append(v) }
            }
        }
        guard !candidates.isEmpty else { return pcs.map { 60 + ($0 - 60 % 12 + 12) % 12 } }
        func cost(_ v: [Int]) -> Double {
            let mean = Double(v.reduce(0, +)) / Double(v.count)
            var c = abs(mean - center) * (previous == nil ? 1 : 0.18)
            if let prev = previous, !prev.isEmpty {
                // Each new note against the nearest old one: smooth hands, held common tones.
                c += v.map { n in Double(prev.map { abs($0 - n) }.min()!) }.reduce(0, +)
                c += prev.map { n in Double(v.map { abs($0 - n) }.min()!) }.reduce(0, +) * 0.5
            }
            // A semitone at the bottom of a chord is muddy.
            if v.count > 1 && v[1] - v[0] <= 1 { c += 6 }
            return c
        }
        return candidates.min { cost($0) < cost($1) }!
    }
}

/// Small deterministic random numbers, so a walking line doesn't change when it's planned again.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
