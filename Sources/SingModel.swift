import AppKit
import Combine
import Foundation

/// A sung note after segmentation.
struct SungNote: Equatable {
    let midi: Int
    let start: Double
    let end: Double
    /// The pitch as sung (fractional MIDI), before it was rounded to `midi`.
    let pitch: Double
    var duration: Double { end - start }

    init(midi: Int, start: Double, end: Double, pitch: Double? = nil) {
        self.midi = midi
        self.start = start
        self.end = end
        self.pitch = pitch ?? Double(midi)
    }

    /// The note named against the singer's own tuning (see `Harmonizer.tuning`).
    func retuned(_ offset: Double) -> SungNote {
        SungNote(midi: Int((pitch - offset).rounded()), start: start, end: end, pitch: pitch)
    }
}

struct SongKey: Equatable {
    let root: Int
    let minor: Bool
    /// 0…1: how clearly the notes point to this key rather than the runner-up.
    let confidence: Double

    func same(_ other: SongKey?) -> Bool { other.map { $0.root == root && $0.minor == minor } ?? false }
}

/// A chord suggestion for one bar (or half bar), with runners-up.
struct ChordSlot: Equatable {
    struct Option: Equatable {
        let root: Int
        let quality: String
        let numeral: String
    }
    var options: [Option]
    /// Index into `options` the user picked (0 = best).
    var chosen = 0
    /// No notes were sung here; the previous chord carries on.
    var held = false
    var chord: Option { options[min(chosen, options.count - 1)] }
}

/// Beat times through a take, and the conversion between seconds and (fractional) beat positions.
struct BeatGrid: Equatable {
    var beats: [Double] = []

    /// Seconds at beat position `x` (0 = the first beat), carrying on in a straight line past either end.
    func time(_ x: Double) -> Double {
        let n = beats.count
        guard n >= 2 else { return (beats.first ?? 0) + x * 0.6 }
        if x <= 0 { return beats[0] + x * (beats[1] - beats[0]) }
        if x >= Double(n - 1) { return beats[n - 1] + (x - Double(n - 1)) * (beats[n - 1] - beats[n - 2]) }
        let i = Int(x)
        return beats[i] + (x - Double(i)) * (beats[i + 1] - beats[i])
    }

    /// Average tempo between two times, from the beats in between.
    func bpm(from a: Double, to b: Double) -> Double? {
        let inside = beats.filter { $0 >= a - 0.1 && $0 <= b + 0.1 }
        guard inside.count >= 3, let f = inside.first, let l = inside.last, l > f else { return nil }
        return 60 * Double(inside.count - 1) / (l - f)
    }

    /// The beat position at `t` seconds: the inverse of `time`.
    func position(_ t: Double) -> Double {
        let n = beats.count
        guard n >= 2 else { return (t - (beats.first ?? 0)) / 0.6 }
        if t <= beats[0] { return (t - beats[0]) / (beats[1] - beats[0]) }
        if t >= beats[n - 1] { return Double(n - 1) + (t - beats[n - 1]) / (beats[n - 1] - beats[n - 2]) }
        var lo = 0, hi = n - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if beats[mid] <= t { lo = mid } else { hi = mid }
        }
        return Double(lo) + (t - beats[lo]) / (beats[hi] - beats[lo])
    }
}

/// Melody → chords. Finds the key (Krumhansl–Schmuckler profiles plus tonal-centre hints, then the key
/// whose chords fit best), follows the beat, and picks the whole chord sequence at once (Viterbi): each
/// chord must fit its bar's notes *and* lead naturally into the next, so the result is a progression
/// rather than a string of independent guesses.
enum Harmonizer {
    private static let majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    private static func pc(_ m: Int) -> Int { ((m % 12) + 12) % 12 }

    /// Keys ranked by how well the melody's notes fit them.
    static func keys(_ notes: [SungNote]) -> [SongKey] {
        var hist = [Double](repeating: 0, count: 12)
        for n in notes { hist[pc(n.midi)] += min(n.duration, 1.5) * (n.duration > 0.4 ? 1.2 : 1) }
        guard hist.filter({ $0 > 0 }).count >= 3 else { return [] }
        // Melodies come home to the tonic, often start on it, and hold it longest. These hints separate
        // keys that share every note (C major and A minor).
        let last = notes.last { $0.duration > 0.25 } ?? notes.last
        let first = notes.first { $0.duration > 0.2 } ?? notes.first
        let longest = notes.max { $0.duration < $1.duration }
        var scores: [(root: Int, minor: Bool, r: Double)] = []
        for root in 0..<12 {
            for minor in [false, true] {
                let profile = minor ? minorProfile : majorProfile
                let rotated = (0..<12).map { profile[(($0 - root) % 12 + 12) % 12] }
                var r = correlation(hist, rotated)
                if let l = last, pc(l.midi) == root { r += l.duration > 0.4 ? 0.08 : 0.05 }
                if let f = first, pc(f.midi) == root { r += 0.05 }
                if let g = longest, pc(g.midi) == root { r += 0.04 }
                scores.append((root, minor, r))
            }
        }
        scores.sort { $0.r > $1.r }
        return scores.indices.map { i in
            let next = i + 1 < scores.count ? scores[i + 1].r : scores[i].r - 0.2
            return SongKey(root: scores[i].root, minor: scores[i].minor,
                           confidence: max(0, min(1, (scores[i].r - next) * 4 + scores[i].r * 0.5)))
        }
    }

    /// Picks the key the way a musician would: try the likeliest few and keep the one whose chords
    /// fit the melody best, not just the one whose notes count up best. `prefer` (the key on screen
    /// while singing) keeps its place unless another clearly fits better, so it doesn't flicker.
    static func bestKey(_ notes: [SungNote], bounds: [Double], style: Int, prefer: SongKey? = nil) -> SongKey? {
        let ranked = keys(notes)
        guard let first = ranked.first, bounds.count > 1 else { return ranked.first }
        var best = (key: first, score: -Double.infinity)
        for (rank, k) in ranked.prefix(3).enumerated() {
            let fit = harmonizeScored(notes, key: k, bounds: bounds, style: style).score
            // A small edge for the statistically likelier key keeps close calls stable.
            var score = fit / Double(bounds.count - 1) - Double(rank) * 0.03
            if k.same(prefer) { score += 0.025 }
            if score > best.score { best = (k, score) }
        }
        return best.key
    }

    private static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let ma = a.reduce(0, +) / 12, mb = b.reduce(0, +) / 12
        var num = 0.0, da = 0.0, db = 0.0
        for i in 0..<12 {
            num += (a[i] - ma) * (b[i] - mb)
            da += (a[i] - ma) * (a[i] - ma)
            db += (b[i] - mb) * (b[i] - mb)
        }
        return da > 0 && db > 0 ? num / sqrt(da * db) : 0
    }

    /// How far the singer sits from concert pitch, in semitones (−0.5…0.5). Plenty of people sing a
    /// little flat or sharp all the way through; measured against their own tuning, every note gets its
    /// right name instead of tipping over to the neighbour.
    static func tuning(_ notes: [SungNote]) -> Double {
        guard notes.count >= 4 else { return 0 }
        var s = 0.0, c = 0.0, w = 0.0
        for n in notes {
            let a = 2 * Double.pi * (n.pitch - n.pitch.rounded())
            let k = min(n.duration, 1)
            s += k * sin(a)
            c += k * cos(a)
            w += k
        }
        // Only a consistent offset counts; scattered intonation averages out to nothing.
        guard w > 0, sqrt(s * s + c * c) / w > 0.55 else { return 0 }
        return atan2(s, c) / (2 * .pi)
    }

    /// Tempo of a free (unclicked) take, from the time between onsets: the beat that the gaps between
    /// nearby notes are whole multiples of. Only notes a few seconds apart are compared, so a singer who
    /// slows down or rushes still reads clearly. `near` (the tempo on screen while singing) holds unless
    /// the singing clearly says otherwise.
    static func tempo(_ notes: [SungNote], near: Double? = nil) -> Double? {
        guard notes.count >= 6 else { return nil }
        var pairs: [(d: Double, w: Double)] = []
        for i in notes.indices {
            var j = i + 1
            while j < notes.count, notes[j].start - notes[i].start < 3.2 {
                pairs.append((notes[j].start - notes[i].start, min(notes[i].duration, 1) * min(notes[j].duration, 1)))
                j += 1
            }
        }
        let wsum = pairs.reduce(0) { $0 + $1.w }
        guard wsum > 0 else { return nil }
        func fit(_ bpm: Double) -> Double { pairs.reduce(0) { $0 + $1.w * cos(2 * .pi * $1.d * bpm / 60) } / wsum }
        var best = (bpm: 100.0, score: -Double.infinity)
        for bpm in stride(from: 60.0, through: 170, by: 0.5) {
            // A pull towards everyday tempos, and while singing towards the tempo already shown.
            var score = fit(bpm) - 0.08 * pow(log2(bpm / 105), 2)
            if let near { score += 0.03 * exp(-pow((bpm - near) / 2.5, 2)) }
            if score > best.score { best = (bpm, score) }
        }
        // Eighth notes make twice the tempo fit as well. The beat is the slowest pulse that most of the
        // singing moves on: a melody of long notes with a few quick pairs is at 80, not 160.
        let b = best.bpm
        let levels = [b / 3, b / 2, b, b * 2, b * 3].filter { (55...185).contains($0) }
        let level = levels.first { onGrid(notes, bpm: $0) >= 0.82 } ?? levels.max { onGrid(notes, bpm: $0) < onGrid(notes, bpm: $1) } ?? b
        return (-12...12).map { level * (1 + Double($0) / 200) }.max { fit($0) < fit($1) } ?? level
    }

    /// Share of the sung time whose gaps between onsets are whole beats at `bpm`.
    private static func onGrid(_ notes: [SungNote], bpm: Double) -> Double {
        let beat = 60 / bpm
        var hit = 0.0, total = 0.0
        for (a, b) in zip(notes, notes.dropFirst()) {
            let gap = b.start - a.start
            let x = gap / beat
            total += gap
            if x.rounded() >= 1 && abs(x - x.rounded()) < 0.15 { hit += gap }
        }
        return total > 0 ? hit / total : 0
    }

    /// Beat times through a take sung without a click, by dynamic programming over the note onsets
    /// (after Ellis, 2007). Beats settle on the sung onsets, but each beat may only stretch a little from
    /// the tempo around it, so the grid follows a singer who slows down or rushes without chasing every
    /// early or late note. `stiffness` above 1 holds it closer to `period` (a tempo the user set).
    static func beats(_ notes: [SungNote], from start: Double, to end: Double, period: Double,
                      stiffness: Double = 1) -> [Double] {
        let dt = 0.01
        let n = Int(((end - start) / dt).rounded(.up)) + 1
        let p0 = max(period, 0.25)
        guard let first = notes.first else { return [start, start + p0] }
        func extend(_ beats: [Double]) -> [Double] {
            var out = beats.isEmpty ? [first.start] : beats
            let k = min(4, out.count - 1)
            let step = k > 0 ? max(0.25, (out[out.count - 1] - out[out.count - 1 - k]) / Double(k)) : p0
            while out[out.count - 1] < end { out.append(out[out.count - 1] + step) }
            out.append(out[out.count - 1] + step)
            return out
        }
        guard n > Int(p0 / dt) * 2 else { return extend([first.start]) }

        // Onset strength: a narrow bump at each note's start, taller for longer notes.
        var onset = [Double](repeating: 0, count: n)
        for note in notes {
            let c = (note.start - start) / dt
            let w = 0.5 + min(note.duration, 1.2)
            let lo = max(0, Int(c) - 9), hi = min(n - 1, Int(c) + 9)
            guard lo <= hi else { continue }
            for i in lo...hi {
                let d = (Double(i) - c) * dt / 0.035
                onset[i] += w * exp(-0.5 * d * d)
            }
        }
        let alpha = 60 * stiffness
        let maxGap = Int(p0 / dt * 2) + 2
        let logs = (0...maxGap).map { $0 > 0 ? log(Double($0)) : 0 }
        let anchor = Int(((first.start - start) / dt).rounded())
        var local = [Double](repeating: p0 / dt, count: n)
        var path: [Int] = []
        for pass in 0..<2 {
            var score = [Double](repeating: -.infinity, count: n)
            var back = [Int](repeating: -1, count: n)
            // The first beat is the first note, give or take a few frames.
            for i in max(0, anchor - 5)...min(n - 1, max(0, anchor + 5)) { score[i] = onset[i] }
            for i in 0..<n {
                let p = local[i], lp = log(local[i])
                let lo = max(0, i - min(maxGap, Int(p * 1.6))), hi = i - Int(p * 0.6)
                guard hi >= lo else { continue }
                var best = -Double.infinity, arg = -1
                for j in lo...hi where score[j] > -.infinity {
                    let r = logs[i - j] - lp
                    let s = score[j] - alpha * r * r
                    if s > best { best = s; arg = j }
                }
                if arg >= 0, best + onset[i] > score[i] {
                    score[i] = best + onset[i]
                    back[i] = arg
                }
            }
            // End on the strongest beat in the last stretch, then trace the chain back.
            var last = -1
            for i in max(0, n - 1 - Int(local[n - 1] * 1.6))..<n where score[i] > -.infinity {
                if last < 0 || score[i] >= score[last] { last = i }
            }
            guard last >= 0 else { break }
            path = []
            var i = last
            while i >= 0 { path.append(i); i = back[i] }
            path.reverse()
            // Second pass: each beat is measured against the tempo around it, so a gradual slowdown is
            // followed through held notes too, not pulled back to the take's average.
            guard pass == 0, path.count >= 5 else { break }
            let gaps = zip(path.dropFirst(), path).map { Double($0 - $1) }
            for k in gaps.indices {
                let around = gaps[max(0, k - 3)...min(gaps.count - 1, k + 3)].sorted()
                for b in path[k]..<path[k + 1] { local[b] = min(Double(maxGap) / 1.6, around[around.count / 2]) }
            }
            for b in path[path.count - 1]..<n { local[b] = local[path[path.count - 1] - 1] }
        }
        return extend(path.map { start + Double($0) * dt })
    }

    typealias Candidate = (offset: Int, quality: String, numeral: String, prior: Double)

    /// Chords for the key, with how common each is. Style 0: the four everyday chords. Otherwise the
    /// whole key, plus the chords songs borrow most (secondary dominants, the minor iv).
    private static func candidates(_ key: SongKey, style: Int) -> [Candidate] {
        if key.minor {
            let core: [Candidate] = [(0, "m", "i", 0.25), (5, "m", "iv", 0.14), (7, "", "V", 0.14), (8, "", "VI", 0.13)]
            return style == 0 ? core : core + [(7, "7", "V7", 0.05), (7, "m", "v", 0.05), (3, "", "III", 0.1),
                                               (10, "", "VII", 0.12), (2, "dim", "ii°", 0.02), (5, "", "IV", 0.015)]
        }
        let core: [Candidate] = [(0, "", "I", 0.25), (5, "", "IV", 0.16), (7, "", "V", 0.17), (9, "m", "vi", 0.13)]
        return style == 0 ? core : core + [(2, "m", "ii", 0.09), (4, "m", "iii", 0.06), (7, "7", "V7", 0.06),
                                           (10, "", "♭VII", 0.03), (2, "7", "V7/V", 0.02), (4, "7", "V7/vi", 0.02),
                                           (5, "m", "iv", 0.015)]
    }

    /// How naturally one chord follows another (common-practice and pop motion).
    private static func transition(_ a: (offset: Int, quality: String), _ b: (offset: Int, quality: String), minor: Bool) -> Double {
        // Staying put is as natural as most moves: chords often last two bars.
        if a.offset == b.offset && a.quality == b.quality { return 0.08 }
        switch (a.offset, b.offset) {
        case (7, 0): return 0.16                // V → I
        case (7, 9): return minor ? 0 : 0.06    // V → vi, the deceptive cadence (I–V–vi–IV)
        case (2, 7): return 0.1                 // ii → V (and V/V → V)
        case (5, 7): return 0.07                // IV → V
        case (5, 0): return 0.05                // IV → I
        case (9, 5), (9, 2): return minor ? 0 : 0.05   // vi → IV, vi → ii
        case (0, 5), (0, 7), (0, 9): return 0.04
        case (10, 0): return 0.06               // ♭VII → I
        case (8, 10): return minor ? 0.05 : 0   // VI → VII
        case (0, 8), (8, 3), (3, 10), (10, 3): return minor ? 0.04 : 0   // i → VI → III → VII, minor pop
        case (3, 8), (3, 5): return minor ? 0.04 : 0
        case (4, 9): return minor ? 0 : 0.04    // iii → vi (and V/vi → vi)
        default: return 0
        }
    }

    /// Chord `i` runs from `bounds[i]` to `bounds[i + 1]`; `firstBar` is the slot where bar 1 starts.
    static func harmonize(_ notes: [SungNote], key: SongKey, bounds: [Double], style: Int, firstBar: Int = 0) -> [ChordSlot] {
        harmonizeScored(notes, key: key, bounds: bounds, style: style, firstBar: firstBar).slots
    }

    static func harmonizeScored(_ notes: [SungNote], key: SongKey, bounds: [Double], style: Int,
                                firstBar: Int = 0) -> (slots: [ChordSlot], score: Double) {
        let cands = candidates(key, style: style)
        let scale = Set((key.minor ? [0, 2, 3, 5, 7, 8, 10, 11] : [0, 2, 4, 5, 7, 9, 11]).map { (key.root + $0) % 12 })
        let count = bounds.count - 1
        guard count > 0 else { return ([], 0) }

        // Each slot's notes, weighted by how long they sound there: held notes and downbeats count more,
        // quick passing notes less. A slot where nothing new is sung and little sounds (the tail of the
        // last note, a breath) just carries the chord on.
        var bars: [[(pc: Int, w: Double)]] = []
        var held: [Bool] = []
        for i in 0..<count {
            let a = bounds[i], b = bounds[i + 1]
            var weights: [(pc: Int, w: Double)] = []
            var sounding = 0.0, onsets = 0
            for n in notes where n.end > a && n.start < b {
                var w = min(n.end, b) - max(n.start, a)
                sounding += w
                if n.start >= a - 0.05 { onsets += 1 }
                if n.start >= a - 0.05 && n.start < a + (b - a) / 4 { w *= 1.5 }
                w *= n.duration >= 0.4 ? 1.2 : (n.duration < 0.18 ? 0.5 : 1)
                weights.append((pc(n.midi), w))
            }
            bars.append(weights)
            held.append(sounding <= 0.05 || (onsets == 0 && sounding < (b - a) * 0.25))
        }

        // How well each chord fits each slot.
        var emission = [[Double]](repeating: [Double](repeating: 0, count: cands.count), count: count)
        for i in 0..<count {
            let total = bars[i].reduce(0) { $0 + $1.w }
            for (j, c) in cands.enumerated() {
                guard !held[i] else { emission[i][j] = c.prior * 0.3; continue }
                let root = (key.root + c.offset) % 12
                let tones = Chords.quality(c.quality).intervals.map { (root + $0) % 12 }
                var fit = 0.0
                for (p, w) in bars[i] {
                    // Melodies sing thirds and fifths as often as roots, so every chord tone counts the same.
                    if tones.contains(p) {
                        fit += w
                    } else if tones.contains((p + 1) % 12) || tones.contains((p + 11) % 12) {
                        // A half step from a chord tone: rubs unless it's just passing.
                        fit -= w * (scale.contains(p) ? 0.35 : 0.6)
                    } else {
                        fit -= w * 0.15
                    }
                }
                // A chord from outside the key needs the melody to sing its outside note.
                let outside = tones.filter { !scale.contains($0) }
                if !outside.isEmpty && !bars[i].contains(where: { outside.contains($0.pc) }) { fit -= total * 0.35 }
                emission[i][j] = fit / total + c.prior * 1.4
            }
        }
        let tonic = cands.indices.first { cands[$0].offset == 0 } ?? 0
        emission[min(firstBar, count - 1)][tonic] += 0.08
        if let lastSung = held.lastIndex(of: false) {
            for (j, c) in cands.enumerated() where c.offset == 0 || (c.offset == 7 && c.quality != "m") {
                emission[lastSung][j] += c.offset == 0 ? 0.08 : 0.03
            }
        }

        // Viterbi over the slots.
        func trans(_ p: Int, _ c: Int, _ bar: Int) -> Double {
            // Through a slot with no singing, the chord simply carries on.
            if held[bar] { return p == c ? 0.35 : -0.1 }
            return transition((cands[p].offset, cands[p].quality), (cands[c].offset, cands[c].quality), minor: key.minor)
        }
        var score = emission[0]
        var back = [[Int]](repeating: [Int](repeating: 0, count: cands.count), count: count)
        for i in 1..<max(1, count) where count > 1 {
            var next = [Double](repeating: -.infinity, count: cands.count)
            for c in cands.indices {
                for p in cands.indices {
                    let s = score[p] + trans(p, c, i) + emission[i][c]
                    if s > next[c] { next[c] = s; back[i][c] = p }
                }
            }
            score = next
        }
        var path = [Int](repeating: 0, count: count)
        path[count - 1] = score.indices.max { score[$0] < score[$1] }!
        let total = score[path[count - 1]]
        if count > 1 { for i in stride(from: count - 1, to: 0, by: -1) { path[i - 1] = back[i][path[i]] } }

        // Runners-up: the chords that fit this slot best given its neighbours on the chosen path.
        var slots: [ChordSlot] = []
        for i in 0..<count {
            let chosen = path[i]
            let ranked = cands.indices.filter { $0 != chosen }.sorted { a, b in
                func local(_ c: Int) -> Double {
                    emission[i][c] + (i > 0 ? trans(path[i - 1], c, i) : 0) + (i + 1 < count ? trans(c, path[i + 1], i + 1) : 0)
                }
                return local(a) > local(b)
            }
            let sum = bars[i].reduce(0) { $0 + $1.w }
            let options = ([chosen] + ranked.prefix(2)).map { j -> ChordSlot.Option in
                let c = cands[j]
                let root = (key.root + c.offset) % 12
                if style >= 2, !held[i] { return enrich(root: root, quality: c.quality, numeral: c.numeral, bar: bars[i], total: sum) }
                return .init(root: root, quality: c.quality, numeral: c.numeral)
            }
            slots.append(ChordSlot(options: options, held: held[i]))
        }
        return (slots, total)
    }

    /// Richer chords where the melody itself sings the colour tone: a 7th, 9th or 6th held in the bar.
    private static func enrich(root: Int, quality: String, numeral: String, bar: [(pc: Int, w: Double)],
                               total: Double) -> ChordSlot.Option {
        func share(_ interval: Int) -> Double {
            bar.filter { $0.pc == (root + interval) % 12 }.reduce(0) { $0 + $1.w } / max(total, 1e-6)
        }
        var q = quality
        switch quality {
        case "":
            if share(11) >= 0.15 && numeral != "V" { q = "maj7" }
            else if share(10) >= 0.15 { q = "7" }
            else if share(2) >= 0.18 { q = "add9" }
            else if share(9) >= 0.18 { q = "6" }
            else if share(5) >= 0.25 && share(4) < 0.05 { q = "sus4" }
        case "m":
            if share(10) >= 0.15 { q = "m7" }
            else if share(2) >= 0.18 { q = "madd9" }
            else if share(9) >= 0.18 { q = "m6" }
        case "7":
            if share(2) >= 0.18 { q = "9" }
        default: break
        }
        guard q != quality else { return .init(root: root, quality: quality, numeral: numeral) }
        // Secondary dominants keep their numeral; elsewhere the numeral's case already says major or
        // minor, so add just the colour.
        guard !numeral.contains("/") else { return .init(root: root, quality: q, numeral: numeral) }
        let suffix = ["maj7": "maj7", "7": "7", "add9": "add9", "6": "6", "sus4": "sus4", "m7": "7", "madd9": "add9",
                      "m6": "6", "9": "9"][q] ?? ""
        let base = numeral.hasSuffix("7") ? String(numeral.dropLast()) : numeral
        return .init(root: root, quality: q, numeral: base + suffix)
    }
}

/// Listens while the user sings and keeps the notes, key, beat and chord suggestions up to date.
final class SingModel: ObservableObject {
    static let shared = SingModel()

    @Published private(set) var recording = false
    /// Beats left in the count-in before recording starts (metronome on).
    @Published private(set) var countIn: Int?
    /// The sung notes, named against the singer's own tuning.
    @Published private(set) var notes: [SungNote] = []
    @Published private(set) var key: SongKey?
    /// The likeliest keys, to pick another by hand.
    @Published private(set) var keyOptions: [SongKey] = []
    /// A key picked by hand (nil: found from the singing).
    @Published private(set) var keyChoice: SongKey?
    /// The key found from the singing, also while another is picked by hand.
    @Published private(set) var foundKey: SongKey?
    @Published private(set) var slots: [ChordSlot] = []
    /// Live pitch (seconds into the take, MIDI), for the melody strip.
    @Published private(set) var trace: [(t: Double, m: Double)] = []
    @Published private(set) var elapsed = 0.0
    @Published var playing: Int?
    /// The sung take, cleaned up, for playback with the chords.
    @Published private(set) var voice: SampleNote?
    /// The beats: the metronome's when it clicked along, else followed through the singing.
    @Published private(set) var grid = BeatGrid()
    /// Where each chord starts, plus where the last one ends (seconds into the take).
    @Published private(set) var bounds: [Double] = []
    /// The take's tempo: the metronome's, found from the singing, or set by hand.
    @Published private(set) var tempo: Double?
    /// Beats sung before bar 1 (a pickup), set by hand.
    @Published private(set) var shift = 0
    /// How far the singer sits from concert pitch, in semitones.
    @Published private(set) var tuning = 0.0
    /// Semitones the chords (and melody) are moved for display, playback and export.
    @Published private(set) var transpose = 0

    private let tuner = TunerModel.shared
    private let prefs = Prefs.shared
    private var subs: Set<AnyCancellable> = []
    private var start = Date()
    /// Notes as segmented, before the singer's tuning is taken into account.
    private var raw: [SungNote] = []
    private var current: [Double] = []
    private var currentStart = 0.0
    private var lastTime = 0.0
    private var leap: [Double] = []
    /// An onset handed on to the next note: a scoop into it, or a syllable sung again on the same pitch.
    private var carry: Double?
    /// Loudness of the current note, frame by frame (dB).
    private var levels: [(t: Double, db: Double)] = []
    private var sub: AnyCancellable?
    private var timer: Timer?
    private var countTimer: Timer?
    private var clicked = false
    /// The user set the tempo, so the beat keeps closer to it.
    private var tempoSet = false
    /// The tempo the onsets suggest, before the beat is followed through the take.
    private var estimate: Double?
    /// The last beat tracking, reused while nothing new was sung.
    private var tracked: (notes: Int, tempo: Double, beats: [Double])?
    private var playStart: UInt64 = 0
    private var playTimer: Timer?
    /// Chords the user picked by hand, by slot, kept across re-harmonizing.
    private var overrides: [Int: ChordSlot.Option] = [:]

    /// Beats per chord: a bar, or half a bar.
    var beatsPerSlot: Double { Double(prefs.beatsPerBar) / (prefs.singChordEvery == 2 ? 2 : 1) }
    /// The first slot holds a pickup: notes sung before bar 1.
    var pickup: Bool { Double(shift).truncatingRemainder(dividingBy: beatsPerSlot) > 0.01 }

    init() {
        Prefs.shared.$singPlayVoice.sink { [weak self] on in Synth.shared.setVoiceEnabled(on && (self?.transpose ?? 0) == 0) }
            .store(in: &subs)
        // Settings that change how bars are cut or which chords are used re-harmonize at once.
        Prefs.shared.$singChordEvery.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.rebuild() } }.store(in: &subs)
        Prefs.shared.$singChords.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.rebuild() } }.store(in: &subs)
    }

    func toggle() { recording || countIn != nil ? stop() : startRecording() }

    /// Light, transparent clean-up like a voice-memo app: remove DC and rumble below ~80 Hz, soften the
    /// edges, and bring the peak to −3 dBFS. Nothing that colours the voice.
    static func clean(_ x: [Float], rate: Double) -> [Float]? {
        guard x.count > Int(rate * 0.2), let peakIn = x.map(abs).max(), peakIn > 0.0005 else { return nil }
        var y = [Float](repeating: 0, count: x.count)
        // 2nd-order Butterworth high-pass at 80 Hz.
        let w = 2 * Double.pi * 80 / rate, q = 0.7071, alpha = sin(w) / (2 * q), c = cos(w), a0 = 1 + alpha
        let b0 = (1 + c) / 2 / a0, b1 = -(1 + c) / a0, b2 = b0, a1 = -2 * c / a0, a2 = (1 - alpha) / a0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in x.indices {
            let v = Double(x[i])
            let o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = v; y2 = y1; y1 = o
            y[i] = Float(o)
        }
        let fade = Int(rate * 0.01)
        for i in 0..<min(fade, y.count) {
            let f = Float(i) / Float(fade)
            y[i] *= f
            y[y.count - 1 - i] *= f
        }
        guard let peak = y.map(abs).max(), peak > 0 else { return nil }
        let gain = 0.708 / peak
        return y.map { $0 * gain }
    }

    // MARK: Recording

    func startRecording() {
        stopPlayback()
        reset()
        clicked = prefs.singClick
        tuner.singing = true
        tuner.acquire("sing")
        guard clicked else { return begin() }
        // One bar of clicks first, so the song starts exactly on bar 1.
        MetronomeModel.shared.start()
        countIn = prefs.beatsPerBar
        countTimer = Timer.scheduledTimer(withTimeInterval: 60 / prefs.bpm, repeats: true) { [weak self] t in
            guard let self, let n = self.countIn else { return t.invalidate() }
            if n <= 1 {
                t.invalidate()
                self.countIn = nil
                self.begin()
            } else {
                self.countIn = n - 1
            }
        }
    }

    private func begin() {
        start = Date()
        recording = true
        tempo = clicked ? prefs.bpm : nil
        tuner.startTake()
        // Every analysis frame, timed in the take's own samples, so notes line up with the recording.
        sub = tuner.frames.sink { [weak self] f in
            guard let self, let t = f.time else { return }
            self.feed(f, at: t)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsed = Date().timeIntervalSince(self.start)
            self.refresh()
        }
    }

    func stop() {
        countTimer?.invalidate()
        countTimer = nil
        if countIn != nil {
            countIn = nil
            tuner.singing = false
            tuner.release("sing")
            if clicked { MetronomeModel.shared.stop() }
            return
        }
        guard recording else { return }
        recording = false
        sub = nil
        timer?.invalidate()
        timer = nil
        closeNote(at: lastTime + 0.02)
        let take = tuner.finishTake()
        voice = Self.clean(take.samples, rate: take.rate).map { SampleNote(midi: 0, data: $0, rate: take.rate, level: 1) }
        tuner.singing = false
        tuner.release("sing")
        if clicked { MetronomeModel.shared.stop() }
        refresh()
    }

    private func reset() {
        raw = []
        notes = []
        trace = []
        slots = []
        key = nil
        keyChoice = nil
        foundKey = nil
        keyOptions = []
        current = []
        carry = nil
        leap = []
        elapsed = 0
        voice = nil
        overrides = [:]
        transpose = 0
        tempo = nil
        tempoSet = false
        estimate = nil
        tracked = nil
        shift = 0
        tuning = 0
        grid = BeatGrid()
        bounds = []
    }

    #if SNAPSHOT
    /// Offline test hook: run a take from analysis frames (with `time` set) without the microphone.
    func simulate(_ frames: [Analyzer.Output], clicked: Bool = false, tempo: Double? = nil, shift: Int = 0) {
        reset()
        self.clicked = clicked
        self.tempo = tempo
        self.shift = shift
        recording = true
        for f in frames { feed(f, at: f.time ?? 0) }
        closeNote(at: lastTime + 0.02)
        recording = false
        elapsed = frames.last?.time ?? 0
        refresh()
    }
    #endif

    func clear() {
        stop()
        stopPlayback()
        reset()
    }

    func choose(_ option: Int, in slot: Int) {
        guard slots.indices.contains(slot), slots[slot].options.indices.contains(option) else { return }
        slots[slot].chosen = option
        overrides[slot] = slots[slot].options[option]
        let c = shifted(slots[slot].chord)
        ChordsView.play(root: c.root, quality: Chords.quality(c.quality), instrument: prefs.instrument,
                        tuning: prefs.tuning, a4: prefs.a4)
    }

    /// One analysis frame (every 20 ms): extends, splits or ends the current note.
    func feed(_ frame: Analyzer.Output, at t: Double) {
        guard recording, t >= 0 else { return }
        let db = frame.db
        // The same pitch sung again: the loudness dipped for a moment below the note's own level (a
        // consonant between syllables) and came back. Vibrato and slow swells don't dip that sharply.
        var again: Double?
        if !current.isEmpty, levels.count >= 8 {
            let sorted = levels.suffix(25).map(\.db).sorted()
            let sustain = sorted[sorted.count / 2]
            if let low = levels.suffix(4).min(by: { $0.db < $1.db }), low.db <= sustain - 4.5, db >= low.db + 3.5,
               db >= sustain - 3, low.t - currentStart > 0.1 {
                again = low.t
            }
        }
        if !current.isEmpty { levels.append((t, db)) }
        guard frame.fresh else {
            // Consonants and breaths drop the pitch for a moment; a longer gap ends the note.
            if !current.isEmpty, t - lastTime > 0.12 { closeNote(at: lastTime + 0.02) }
            return
        }
        let m = frame.reading.midi
        // Octave slips happen at onsets and when a note fades; a big leap only counts once a few
        // frames in a row agree on it.
        let reference = current.isEmpty ? raw.last.map(\.pitch) : current.reduce(0, +) / Double(current.count)
        if let ref = reference, abs(m - ref) > 6, t - lastTime < 0.25 {
            if let p = leap.first, abs(m - p) > 0.7 { leap = [] }
            leap.append(m)
            guard leap.count >= 4 else { return }
            closeNote(at: t)
        }
        leap = []
        trace.append((t, m))
        if trace.count > 3000 { trace.removeFirst(trace.count - 3000) }
        if !current.isEmpty {
            let mean = current.reduce(0, +) / Double(current.count)
            if abs(m - mean) > 0.6 {
                // Vibrato and slides stay one note; a move of more than ~0.6 semitone starts the next. A
                // scoop into it, too short to be a note of its own, hands on its start.
                let scoop = lastTime - currentStart < 0.12 && abs(m - mean) < 3 ? currentStart : nil
                closeNote(at: t, keepTrace: scoop != nil)
                carry = scoop
            } else if let dipAt = again {
                closeNote(at: dipAt)
                carry = (dipAt + t) / 2
            }
        }
        if current.isEmpty {
            currentStart = carry ?? t
            carry = nil
            levels = [(t, db)]
        }
        current.append(m)
        lastTime = t
    }

    func closeNote(at t: Double, keepTrace: Bool = false) {
        defer { current = [] }
        guard current.count >= 4, lastTime - currentStart >= 0.1 else {
            // Too short to be a note (a slip or a breath): drop its line from the strip as well.
            if !current.isEmpty && !keepTrace { trace.removeAll { $0.t >= currentStart - 0.001 && $0.t <= lastTime + 0.001 } }
            return
        }
        let sorted = current.sorted()
        let p = sorted[sorted.count / 2]
        raw.append(SungNote(midi: Int(p.rounded()), start: currentStart, end: max(currentStart + 0.1, min(t, lastTime + 0.02)), pitch: p))
    }

    /// Re-harmonizes from scratch, so a key or beat that becomes clearer later fixes the earlier bars too.
    func refresh() {
        guard let first = raw.first else { return }
        tuning = Harmonizer.tuning(raw)
        notes = raw.map { $0.retuned(tuning) }
        let end = max(elapsed, notes.last?.end ?? 0)
        if clicked {
            let p = 60 / (tempo ?? prefs.bpm)
            grid = BeatGrid(beats: Array(stride(from: 0, through: end + p, by: p)))
        } else {
            // Sung freely: the first note is beat 1, and the beat is followed through the singing. The
            // tempo shown is the average of the beats found.
            let origin = max(0, first.start - 0.03)
            if !tempoSet, let bpm = Harmonizer.tempo(notes, near: recording ? estimate : nil) { estimate = bpm }
            let bpm = tempoSet ? (tempo ?? prefs.bpm) : (estimate ?? prefs.bpm)
            if let c = tracked, c.notes == notes.count, c.tempo == bpm, let last = c.beats.last, last > end {
                grid = BeatGrid(beats: c.beats)
            } else {
                let beats = Harmonizer.beats(notes, from: origin, to: end, period: 60 / bpm, stiffness: tempoSet ? 6 : 1)
                tracked = (notes.count, bpm, beats)
                grid = BeatGrid(beats: beats)
            }
            if !tempoSet { tempo = grid.bpm(from: first.start, to: notes.last?.start ?? end).map { ($0 * 10).rounded() / 10 } ?? bpm }
        }
        bounds = Self.bounds(grid, perSlot: beatsPerSlot, shift: shift, end: end)
        let style = prefs.singChords
        keyOptions = Array(Harmonizer.keys(notes).prefix(5))
        foundKey = Harmonizer.bestKey(notes, bounds: bounds, style: style, prefer: recording ? foundKey : nil)
        guard let k = keyChoice ?? foundKey else { return }
        key = k
        var fresh = Harmonizer.harmonize(notes, key: k, bounds: bounds, style: style, firstBar: pickup ? 1 : 0)
        // After the take, the silence at the end isn't a bar of its own.
        while !recording, fresh.count > 1, fresh.last?.held == true {
            fresh.removeLast()
            bounds.removeLast()
        }
        for (i, o) in overrides where i < fresh.count {
            if let j = fresh[i].options.firstIndex(of: o) { fresh[i].chosen = j } else { fresh[i].options.insert(o, at: 0) }
        }
        slots = fresh
    }

    /// Re-cuts the slots from scratch: hand-picked chords belonged to the old ones.
    private func rebuild() {
        overrides = [:]
        refresh()
    }

    /// Chord boundaries in seconds: every `perSlot` beats from bar 1, which starts `shift` beats in (the
    /// notes before it, a pickup, get a slot of their own). The last one lies past `end`.
    static func bounds(_ grid: BeatGrid, perSlot: Double, shift: Int, end: Double) -> [Double] {
        guard !grid.beats.isEmpty else { return [] }
        var x = Double(shift).truncatingRemainder(dividingBy: perSlot)
        if x < 0.01 { x += perSlot }
        var out = [grid.time(0)]
        while out.count < 500 {
            let t = grid.time(x)
            out.append(t)
            if t >= end { break }
            x += perSlot
        }
        return out
    }

    // MARK: Key, beat, tempo & transpose

    /// Use this key (nil: back to the one found from the singing).
    func chooseKey(_ k: SongKey?) {
        keyChoice = k
        rebuild()
    }

    /// Moves bar 1 by a beat, for songs that start with a pickup.
    func nudgeShift(_ delta: Int) {
        let n = max(1, prefs.beatsPerBar)
        shift = ((shift + delta) % n + n) % n
        rebuild()
    }

    func nudgeTempo(_ delta: Double) {
        setTempo((tempo ?? prefs.bpm).rounded() + delta)
    }

    /// A tempo by hand (nil: back to the one found from the singing). Half and double time fix the
    /// usual mix-up of a beat finder.
    func setTempo(_ bpm: Double?) {
        if let bpm {
            tempo = min(240, max(30, bpm))
            tempoSet = true
        } else {
            tempoSet = false
        }
        rebuild()
    }

    /// The tempo was set by hand.
    var tempoIsSet: Bool { tempoSet }

    func setTranspose(_ semitones: Int) {
        transpose = min(6, max(-6, semitones))
        // The recorded voice can't follow a key change, so it sits out while transposed.
        Synth.shared.setVoiceEnabled(prefs.singPlayVoice && transpose == 0)
    }

    func shifted(_ o: ChordSlot.Option) -> ChordSlot.Option {
        .init(root: ((o.root + transpose) % 12 + 12) % 12, quality: o.quality, numeral: o.numeral)
    }

    func shifted(_ k: SongKey) -> SongKey {
        SongKey(root: ((k.root + transpose) % 12 + 12) % 12, minor: k.minor, confidence: k.confidence)
    }

    var shiftedKey: SongKey? { key.map(shifted) }

    /// For guitar: a capo that turns the chords into open shapes, e.g. capo 3 → G, D, Em, C.
    var capoSuggestion: (capo: Int, shapes: [String])? {
        guard prefs.instrument.id == "guitar6" || prefs.instrument.id == "guitar7", !slots.isEmpty else { return nil }
        let open: Set<String> = ["0|", "2|", "4|", "7|", "9|", "9|m", "4|m", "2|m", "0|7", "2|7", "4|7", "7|7", "9|7", "11|7",
                                 "9|m7", "4|m7", "2|m7", "0|maj7", "5|maj7", "2|sus2", "2|sus4", "9|sus2", "9|sus4", "4|sus4",
                                 "0|add9", "7|add9", "9|5", "4|5", "2|5"]
        let chords = slots.filter { !$0.held }.map { shifted($0.chord) }
        func score(_ capo: Int) -> Int { chords.filter { open.contains("\((($0.root - capo) % 12 + 12) % 12)|\($0.quality)") }.count }
        let base = score(0)
        guard let best = (1...7).max(by: { score($0) < score($1) || (score($0) == score($1) && $0 > $1) }),
              score(best) > base else { return nil }
        var seen: [String] = []
        for c in chords {
            let name = ChordsView.name((c.root - best + 12) % 12, c.quality, prefs.notation)
            if !seen.contains(name) { seen.append(name) }
        }
        return (best, seen)
    }

    // MARK: Playback

    /// Plays the chords on the take's own beat (down on the chord, a lighter upstroke halfway), and as
    /// wanted the sung take and the melody on the instrument. Everything is scheduled on the audio clock,
    /// so it stays together, also where the singer slowed down or rushed.
    func play() {
        if playing != nil { return stopPlayback() }
        guard !slots.isEmpty, bounds.count == slots.count + 1 else { return }
        let synth = Synth.shared
        synth.prepare()
        synth.keepAlive = true
        let sr = synth.outputSampleRate
        playStart = synth.now + UInt64(sr * 0.15)
        func at(_ t: Double) -> UInt64 { playStart + UInt64(max(0, t) * sr) }
        // The voice is always scheduled; "My voice" mutes it live, even mid-playback.
        synth.setVoiceEnabled(prefs.singPlayVoice && transpose == 0)
        if let v = voice { synth.schedule(audio: v, at: playStart) }
        for (i, s) in slots.enumerated() where !s.held {
            let c = shifted(s.chord)
            let chordNotes = ChordsView.notes(root: c.root, quality: Chords.quality(c.quality), instrument: prefs.instrument,
                                              tuning: prefs.tuning, a4: prefs.a4)
            let a = bounds[i], b = bounds[i + 1]
            synth.schedule(strum: chordNotes, at: at(a), up: false, velocity: 0.78, hold: (b - a) / 2)
            synth.schedule(strum: chordNotes, at: at((a + b) / 2), up: true, velocity: 0.62, hold: (b - a) / 2)
        }
        if prefs.singPlayMelody {
            for n in notes {
                let f = Music.frequency(midi: Double(n.midi + transpose + 12 * (n.midi < 52 ? 1 : 0)), a4: prefs.a4)
                synth.schedule(strum: [Synth.Note(frequency: f, string: nil)], at: at(n.start),
                               up: false, velocity: 0.9, hold: n.duration)
            }
        }
        let length = max(bounds.last ?? 0, voice.map { Double($0.data.count) / $0.rate } ?? 0)
        playing = 0
        playTimer?.invalidate()
        playTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = synth.now
            let t = now > self.playStart ? Double(now - self.playStart) / sr : 0
            if t > length + 0.3 { return self.stopPlayback() }
            let i = min(self.slots.count - 1, max(0, self.bounds.lastIndex { $0 <= t } ?? 0))
            if self.playing != i { self.playing = i }
        }
    }

    func stopPlayback() {
        playTimer?.invalidate()
        playTimer = nil
        if playing != nil {
            Synth.shared.cancelScheduled()
            Synth.shared.silence()
            Synth.shared.keepAlive = false
        }
        playing = nil
    }

    // MARK: Sharing

    /// Hands the chords to the Progressions tab to loop with a rhythm and drums (without the pickup).
    func sendToProgressions() {
        guard let k = shiftedKey, !slots.isEmpty else { return }
        var steps: [ProgressionStep] = []
        for s in slots.dropFirst(pickup && slots.count > 1 ? 1 : 0).prefix(16) {
            let c = shifted(s.chord)
            steps.append(ProgressionStep(offset: ((c.root - k.root) % 12 + 12) % 12, quality: c.quality, numeral: c.numeral))
        }
        stopPlayback()
        let player = ProgressionPlayer.shared
        player.stop()
        player.progression = Progression(key: k.root, minor: k.minor, mood: "Sing & Find", steps: steps)
        prefs.progressionBPM = (tempo ?? prefs.bpm).rounded()
        prefs.progressionBeats = prefs.singChordEvery == 2 ? max(1, prefs.beatsPerBar / 2) : prefs.beatsPerBar
        AppState.shared.tab = .progressions
    }

    /// A plain-text chord chart, four bars to a line (a pickup goes in front, in brackets).
    var chart: String {
        guard let k = shiftedKey else { return "" }
        var names = slots.map { s in s.held ? "%" : { c in ChordsView.name(c.root, c.quality, prefs.notation) }(shifted(s.chord)) }
        var lines = ["\(prefs.notation.name(pc: k.root)) \(k.minor ? "minor" : "major") · \(Int((tempo ?? prefs.bpm).rounded())) BPM"]
        if pickup, names.count > 1 { lines.append("(\(names.removeFirst()))") }
        for row in stride(from: 0, to: names.count, by: 4) {
            lines.append("| " + names[row..<min(names.count, row + 4)].joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    func copyChart() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(chart, forType: .string)
    }

    /// Melody and chords as a standard MIDI file, ready for any DAW. The tempo map follows the take beat
    /// by beat, so the DAW's bars line up with the singing even where it drifted.
    func midiData() -> Data {
        let perBar = max(1, prefs.beatsPerBar)
        // A pickup sits at the end of an otherwise empty first bar, so bar 1 lands on a bar line.
        let lead = Double((perBar - shift % perBar) % perBar)
        func tick(_ t: Double) -> Int { max(0, Int(((grid.position(t) + lead) * 480).rounded())) }
        var tempos: [(tick: Int, bpm: Double)] = []
        let beats = grid.beats
        for k in 0..<max(0, beats.count - 1) where beats[k + 1] > beats[k] {
            let bpm = (60 / (beats[k + 1] - beats[k]) * 100).rounded() / 100
            if tempos.last?.bpm != bpm { tempos.append((Int((Double(k) + lead) * 480), bpm)) }
        }
        if tempos.isEmpty || tempos[0].tick > 0 { tempos.insert((0, tempos.first?.bpm ?? (tempo ?? prefs.bpm)), at: 0) }
        let chords = slots.enumerated().compactMap { i, s -> (tick: Int, length: Int, notes: [Int])? in
            guard !s.held, i + 1 < bounds.count else { return nil }
            let c = shifted(s.chord)
            let a = tick(bounds[i])
            return (a, tick(bounds[i + 1]) - a, PianoVoicing.playable(root: c.root, quality: Chords.quality(c.quality)))
        }
        let melody = notes.map { n -> (tick: Int, length: Int, notes: [Int]) in
            let a = tick(n.start)
            return (a, max(1, tick(n.end) - a), [n.midi + transpose])
        }
        return MIDIFile.make(tempos: tempos, beatsPerBar: perBar, tracks: [("Melody", melody), ("Chords", chords)])
    }
}

/// A minimal Standard MIDI File writer (format 1, 480 ticks per quarter note).
enum MIDIFile {
    /// `tempos` are (tick, BPM) changes; events are in ticks.
    static func make(tempos: [(tick: Int, bpm: Double)], beatsPerBar: Int,
                     tracks: [(name: String, events: [(tick: Int, length: Int, notes: [Int])])]) -> Data {
        let ppq = 480
        func vlq(_ v: Int) -> [UInt8] {
            var v = max(0, v), bytes = [UInt8(v & 0x7F)]
            v >>= 7
            while v > 0 { bytes.insert(UInt8(v & 0x7F) | 0x80, at: 0); v >>= 7 }
            return bytes
        }
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
            let n = body.count
            return Array(type.utf8) + [UInt8(n >> 24 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)] + body
        }
        func text(_ meta: UInt8, _ s: String) -> [UInt8] { [0, 0xFF, meta] + vlq(s.utf8.count) + Array(s.utf8) }

        var conductor = text(0x03, "Chorden")
        conductor += [0, 0xFF, 0x58, 4, UInt8(beatsPerBar), 2, 24, 8]
        var last = 0
        for t in tempos.sorted(by: { $0.tick < $1.tick }) {
            let us = Int((60_000_000 / max(t.bpm, 1)).rounded())
            conductor += vlq(t.tick - last) + [0xFF, 0x51, 3, UInt8(us >> 16 & 0xFF), UInt8(us >> 8 & 0xFF), UInt8(us & 0xFF)]
            last = max(last, t.tick)
        }
        conductor += [0, 0xFF, 0x2F, 0]
        var file = chunk("MThd", [0, 1, 0, UInt8(tracks.count + 1), UInt8(ppq >> 8), UInt8(ppq & 0xFF)]) + chunk("MTrk", conductor)

        for (channel, track) in tracks.enumerated() {
            var events: [(tick: Int, on: Bool, note: Int)] = []
            for e in track.events {
                for n in e.notes where (0...127).contains(n) {
                    events.append((e.tick, true, n))
                    events.append((e.tick + max(1, Int(Double(e.length) * 0.97)), false, n))
                }
            }
            // Note-offs before note-ons at the same tick, so repeated notes retrigger cleanly.
            events.sort { $0.tick != $1.tick ? $0.tick < $1.tick : (!$0.on && $1.on) }
            var body = text(0x03, track.name)
            var at = 0
            for e in events {
                body += vlq(e.tick - at)
                body += [UInt8((e.on ? 0x90 : 0x80) | channel), UInt8(e.note), e.on ? 92 : 0]
                at = e.tick
            }
            body += [0, 0xFF, 0x2F, 0]
            file += chunk("MTrk", body)
        }
        return Data(file)
    }
}
