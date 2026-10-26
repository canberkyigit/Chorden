import Foundation

/// How the right hand plays each chord.
enum StrumPattern: String, CaseIterable {
    case whole, quarters, downUp, folk, pop16, shuffle, reggae, funk, rock, chug, gallop, arpeggio, travis, bossa

    var name: String {
        switch self {
        case .whole: "Whole"
        case .quarters: "Quarters"
        case .downUp: "Down-up"
        case .folk: "Folk strum"
        case .pop16: "Pop 16ths"
        case .shuffle: "Shuffle"
        case .reggae: "Reggae skank"
        case .funk: "Funk scratch"
        case .rock: "Rock 8ths"
        case .chug: "Palm-mute chug"
        case .gallop: "Gallop"
        case .arpeggio: "Fingerpicking"
        case .travis: "Travis picking"
        case .bossa: "Bossa nova"
        }
    }

    enum Hit {
        /// A strum; `mute` stops the strings that many beats later (skanks, scratches).
        case strum(up: Bool, velocity: Double, mute: Double? = nil)
        /// One string of the chord: 0–2 count up from the bass, 3–5 are the three highest strings.
        case pick(Int, velocity: Double)
        /// The treble strings plucked together, as fingers do in bossa nova.
        case pinch(velocity: Double)
        /// The three lowest strings, palm-muted.
        case chug(velocity: Double, mute: Double)
    }

    /// Hits within one 4/4 bar: (beat, hit).
    var bar: [(Double, Hit)] {
        func down(_ beat: Double, _ v: Double, mute: Double? = nil) -> (Double, Hit) { (beat, .strum(up: false, velocity: v, mute: mute)) }
        func up(_ beat: Double, _ v: Double, mute: Double? = nil) -> (Double, Hit) { (beat, .strum(up: true, velocity: v, mute: mute)) }
        var hits: [(Double, Hit)] = []
        switch self {
        case .whole:
            hits = [down(0, 0.9)]
        case .quarters:
            hits = [down(0, 0.9), down(1, 0.7), down(2, 0.8), down(3, 0.7)]
        case .downUp:
            for b in 0..<4 {
                hits.append(down(Double(b), b % 2 == 0 ? 0.88 : 0.75))
                hits.append(up(Double(b) + 0.5, 0.6))
            }
        case .folk:
            // The campfire classic: D, D U, U D U.
            hits = [down(0, 0.9), down(1, 0.75), up(1.5, 0.6), up(2.5, 0.6), down(3, 0.8), up(3.5, 0.6)]
        case .pop16:
            // Continuous sixteenths, the eighths pushed and the in-betweens brushed lightly.
            for i in 0..<16 {
                let t = Double(i) * 0.25
                hits.append(i % 2 == 0 ? down(t, i % 4 == 0 ? 0.82 : 0.66) : up(t, 0.4))
            }
        case .shuffle:
            // Long-short triplet feel: the upstroke lands on the last third of each beat.
            for b in 0..<4 {
                hits.append(down(Double(b), b % 2 == 0 ? 0.88 : 0.74))
                hits.append(up(Double(b) + 2.0 / 3, 0.55))
            }
        case .reggae:
            // Choppy upstrokes on every off-beat, cut short.
            for b in 0..<4 { hits.append(up(Double(b) + 0.5, 0.72, mute: 0.18)) }
        case .funk:
            // Sixteenth-note scratching, mostly muted, with a few chords left to bark.
            let accents: Set<Int> = [0, 3, 6, 10, 12]
            for i in 0..<16 {
                let t = Double(i) * 0.25
                let v = accents.contains(i) ? 0.85 : 0.32
                hits.append(i % 2 == 0 ? down(t, v, mute: 0.12) : up(t, v, mute: 0.12))
            }
        case .rock:
            for i in 0..<8 { hits.append(down(Double(i) * 0.5, i % 2 == 0 ? 0.9 : 0.62)) }
        case .chug:
            for i in 0..<8 { hits.append((Double(i) * 0.5, .chug(velocity: i % 2 == 0 ? 0.9 : 0.7, mute: 0.22))) }
        case .gallop:
            // Eighth and two sixteenths on every beat.
            for b in 0..<4 {
                let t = Double(b)
                hits += [(t, .chug(velocity: 0.92, mute: 0.2)), (t + 0.5, .chug(velocity: 0.62, mute: 0.12)),
                         (t + 0.75, .chug(velocity: 0.66, mute: 0.12))]
            }
        case .arpeggio:
            // p-i-m-a-m-i over eighths: bass, then up and back down the treble strings.
            for (i, slot) in [0, 3, 4, 5, 4, 3, 4, 5].enumerated() {
                hits.append((Double(i) * 0.5, .pick(slot, velocity: i == 0 ? 0.85 : 0.65)))
            }
        case .travis:
            // The thumb alternates two bass strings on the beat; fingers answer on the off-beats.
            hits = [(0, .pick(0, velocity: 0.85)), (0, .pick(5, velocity: 0.6)), (0.5, .pick(4, velocity: 0.55)),
                    (1, .pick(2, velocity: 0.72)), (1.5, .pick(3, velocity: 0.55)), (2, .pick(0, velocity: 0.8)),
                    (2.5, .pick(4, velocity: 0.55)), (3, .pick(2, velocity: 0.72)), (3.5, .pick(5, velocity: 0.58))]
        case .bossa:
            // Thumb on root and fifth, fingers plucking the chord on the syncopation.
            hits = [(0, .pick(0, velocity: 0.8)), (1, .pick(1, velocity: 0.7)), (2, .pick(0, velocity: 0.78)),
                    (3, .pick(1, velocity: 0.7)), (0, .pinch(velocity: 0.7)), (1.5, .pinch(velocity: 0.62)),
                    (2.5, .pinch(velocity: 0.62)), (3, .pinch(velocity: 0.66))]
        }
        return hits
    }
}

enum DrumPattern: String, CaseIterable {
    case off, click, groove, rock, ballad, disco, funk, shuffle, jazz, bossa, reggae, hiphop, halftime

    var name: String {
        switch self {
        case .off: "Off"
        case .click: "Click"
        case .groove: "Groove"
        case .rock: "Rock beat"
        case .ballad: "Ballad"
        case .disco: "Four on the floor"
        case .funk: "Funk beat"
        case .shuffle: "Blues shuffle"
        case .jazz: "Jazz swing"
        case .bossa: "Bossa groove"
        case .reggae: "One drop"
        case .hiphop: "Boom bap"
        case .halftime: "Half-time"
        }
    }

    /// Hits within one 4/4 bar.
    var bar: [(Double, DrumKind, Double)] {
        var hits: [(Double, DrumKind, Double)] = []
        func eighths(_ kind: DrumKind, _ strong: Double, _ weak: Double) {
            for e in 0..<8 { hits.append((Double(e) * 0.5, kind, e % 2 == 0 ? strong : weak)) }
        }
        func triplets(_ kind: DrumKind, _ strong: Double, _ weak: Double) {
            for b in 0..<4 { hits += [(Double(b), kind, strong), (Double(b) + 2.0 / 3, kind, weak)] }
        }
        switch self {
        case .off, .click:
            break
        case .groove:
            hits = [(0, .kick, 1), (2, .kick, 0.9), (2.5, .kick, 0.6), (1, .snare, 0.9), (3, .snare, 0.9)]
            for e in 0..<8 { hits.append((Double(e) * 0.5, e == 7 ? .openHat : .hat, e % 2 == 0 ? 0.8 : 0.5)) }
        case .rock:
            hits = [(0, .kick, 1), (1.75, .kick, 0.7), (2, .kick, 0.95), (2.5, .kick, 0.75), (1, .snare, 1), (3, .snare, 1)]
            eighths(.hat, 0.85, 0.7)
        case .ballad:
            hits = [(0, .kick, 1), (2.5, .kick, 0.5), (1, .rim, 0.7), (3, .rim, 0.7)] + (0..<4).map { (Double($0), .hat, 0.5) }
        case .disco:
            hits = (0..<4).map { (Double($0), .kick, 1) } + [(1, .snare, 0.7), (3, .snare, 0.7), (1, .clap, 0.8), (3, .clap, 0.8)]
            for b in 0..<4 { hits += [(Double(b), .hat, 0.45), (Double(b) + 0.5, .openHat, 0.6)] }
        case .funk:
            hits = [(0, .kick, 1), (0.75, .kick, 0.7), (2.5, .kick, 0.85), (3.25, .kick, 0.6),
                    (1, .snare, 1), (3, .snare, 1), (1.75, .snare, 0.25), (3.5, .snare, 0.22)]
            for i in 0..<16 { hits.append((Double(i) * 0.25, .hat, i % 2 == 0 ? 0.6 : 0.3)) }
        case .shuffle:
            hits = [(0, .kick, 1), (2, .kick, 0.9), (2 + 2.0 / 3, .kick, 0.55), (1, .snare, 0.95), (3, .snare, 0.95)]
            triplets(.hat, 0.7, 0.45)
        case .jazz:
            // Ride "ding, ding-a ding", hi-hat foot on 2 and 4, kick feathered under every beat.
            hits = [(0, .ride, 0.6), (1, .ride, 0.65), (1 + 2.0 / 3, .ride, 0.42), (2, .ride, 0.6), (3, .ride, 0.65),
                    (3 + 2.0 / 3, .ride, 0.42), (1, .hat, 0.45), (3, .hat, 0.45)]
            hits += (0..<4).map { (Double($0), .kick, 0.22) }
        case .bossa:
            hits = [(0, .kick, 0.7), (1.5, .kick, 0.55), (2, .kick, 0.7), (3.5, .kick, 0.55),
                    (0, .rim, 0.6), (0.75, .rim, 0.55), (1.5, .rim, 0.6), (2.5, .rim, 0.55), (3, .rim, 0.6)]
            for i in 0..<16 { hits.append((Double(i) * 0.25, .shaker, i % 2 == 0 ? 0.45 : 0.3)) }
        case .reggae:
            // The one drop: nothing on one, kick and rim together on three.
            hits = [(2, .kick, 1), (2, .rim, 0.85)]
            triplets(.hat, 0.5, 0.35)
        case .hiphop:
            hits = [(0, .kick, 1), (1.75, .kick, 0.75), (2.5, .kick, 0.9), (1, .snare, 0.9), (3, .snare, 0.9),
                    (1, .clap, 0.6), (3, .clap, 0.6)]
            eighths(.hat, 0.6, 0.4)
        case .halftime:
            hits = [(0, .kick, 1), (1.5, .kick, 0.6), (2, .snare, 1), (3.5, .tom, 0.6)]
            eighths(.hat, 0.6, 0.45)
        }
        return hits
    }
}

extension DrumPattern {
    /// What a drummer plays into the top of the loop, over its last `beats` beats (1 or 2), as (offset from the
    /// fill's start, drum, velocity). Nil where the groove carries on through (bossa, the click).
    func fill(beats: Int) -> [(Double, DrumKind, Double)]? {
        func run(_ kinds: [DrumKind], step: Double, from v0: Double, to v1: Double) -> [(Double, DrumKind, Double)] {
            kinds.enumerated().map { i, k in
                (Double(i) * step, k, v0 + (v1 - v0) * Double(i) / Double(max(1, kinds.count - 1)))
            }
        }
        switch self {
        case .off, .click, .bossa:
            return nil
        case .jazz, .shuffle:
            // Snare triplets, swelling into the downbeat.
            return run(Array(repeating: .snare, count: 3 * beats), step: 1.0 / 3, from: 0.35, to: 0.85)
        case .ballad:
            // A soft eighth-note roll around the toms.
            return run(beats == 1 ? [.tomHigh, .tomMid] : [.tomHigh, .tomHigh, .tomMid, .tom], step: 0.5, from: 0.45, to: 0.7)
        case .reggae:
            return run(Array(repeating: .rim, count: 4 * beats), step: 0.25, from: 0.45, to: 0.85)
        case .groove, .rock, .disco, .funk, .hiphop, .halftime:
            // Sixteenths from the snare down the toms, with the kick under the last one.
            let kinds: [DrumKind] = beats == 1 ? [.snare, .snare, .tomHigh, .tomMid]
                : [.snare, .snare, .snare, .snare, .tomHigh, .tomHigh, .tomMid, .tom]
            return run(kinds, step: 0.25, from: 0.6, to: 0.95) + [(Double(beats) - 0.25, .kick, 0.85)]
        }
    }
}

/// Plays the current progression in a loop with the chosen pattern, tempo and drums.
/// Events are queued ~300 ms ahead on the synth's sample clock, so the groove never drifts.
final class ProgressionPlayer: ObservableObject {
    static let shared = ProgressionPlayer()

    @Published var progression: Progression?
    @Published private(set) var playing = false
    /// Chord and beat under the playhead, for the UI.
    @Published private(set) var chord: Int?
    @Published private(set) var beat: Int?

    private let prefs = Prefs.shared
    private let synth = Synth.shared
    private var timer: Timer?
    private var anchorSample: UInt64 = 0
    private var anchorBeat = 0.0
    private var anchorBPM = 90.0
    private var scheduledUntil = 0.0
    /// Beat where a pass through the progression starts. Adding or removing a chord moves it, so the loop
    /// carries on from the same chord instead of jumping.
    private var loopOrigin = 0.0
    private let band = BackingBand()
    /// Played once: the final chord has been queued.
    private var endingQueued = false

    var beatsPerChord: Int { prefs.progressionBeats }
    var totalBeats: Double { Double((progression?.steps.count ?? 0) * beatsPerChord) }

    func generate() {
        progression = Progressions.generate(length: prefs.progressionLength, mood: prefs.progressionMood, avoiding: progression)
        if playing { restart() }
    }

    func toggle() { playing ? stop() : start() }

    func start() {
        if progression == nil { generate() }
        preloadBand()
        synth.prepare()
        synth.keepAlive = true
        anchorBPM = prefs.progressionBPM
        // A short lead-in so the first beat is scheduled with room to spare.
        anchorSample = synth.now + UInt64(synth.outputSampleRate * 0.15)
        anchorBeat = 0
        scheduledUntil = 0
        // A count-in bar comes first: the progression starts after it.
        loopOrigin = prefs.progressionCountIn ? 4 : 0
        endingQueued = false
        band.reset()
        playing = true
        applyMix()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    func stop() {
        guard playing else { return }
        playing = false
        timer?.invalidate()
        timer = nil
        synth.cancelScheduled()
        synth.stopBacking()
        synth.keepAlive = false
        synth.setMix(Synth.Mix())
        chord = nil
        beat = nil
    }

    /// Settings that change what's already queued (length, pattern) restart from the top of the loop.
    func restart() {
        guard playing else { return }
        stop()
        start()
    }

    private var sampleRate: Double { synth.outputSampleRate }

    // MARK: - Mixer

    static let parts = ["instrument", "bass", "keys", "drums"]

    func level(_ part: String) -> Double { prefs.progressionMuted.contains(part) ? 0 : prefs.progressionLevels[part] ?? 1 }

    /// The mixer's levels take effect at once while the loop plays; outside it everything plays at full level.
    func applyMix() {
        guard playing else { return }
        synth.setMix(Synth.Mix(instrument: Float(level("instrument")), bass: Float(level("bass")),
                               keys: Float(level("keys")), drums: Float(level("drums"))))
    }

    // MARK: - Band

    /// Bass and keys as they'll play now: Auto follows the drums and rhythm, and steps aside when the chosen
    /// instrument already plays that part (a bass guitar, the piano).
    var bandStyles: (bass: BassStyle, keys: KeysStyle) {
        let auto = autoStyles
        let bass = BassStyle(rawValue: prefs.progressionBass) ?? .auto
        let keys = KeysStyle(rawValue: prefs.progressionKeys) ?? .auto
        return (bass == .auto ? auto.bass : bass, keys == .auto ? auto.keys : keys)
    }

    /// What Auto plays with the current drums, rhythm and instrument.
    var autoStyles: (bass: BassStyle, keys: KeysStyle) {
        let auto = BackingBand.auto(drums: DrumPattern(rawValue: prefs.progressionDrums) ?? .off,
                                    rhythm: StrumPattern(rawValue: prefs.progressionPattern) ?? .downUp)
        return (["bass", "contrabass"].contains(Timbre.current().samples) ? .off : auto.bass,
                prefs.instrument.isKeyboard ? .off : auto.keys)
    }

    /// Decodes the bass and piano recordings ahead of the first beat.
    func preloadBand() {
        let styles = bandStyles
        if styles.bass != .off { SampleLibrary.shared.preload(Synth.BackingPart.bass.samples) }
        if styles.keys != .off { SampleLibrary.shared.preload(Synth.BackingPart.keys.samples) }
    }

    private static func mod(_ a: Double, _ m: Double) -> Double { let r = a.truncatingRemainder(dividingBy: m); return r < 0 ? r + m : r }

    // MARK: - Editing
    // Edits never stop the loop: beats already queued play out (~300 ms), the next one picks up the change.

    func setChord(_ i: Int, root: Int, quality: String) {
        guard let p = progression, p.steps.indices.contains(i) else { return }
        var steps = p.steps
        steps[i] = Progressions.step(offset: root - p.key, quality: quality, minor: p.minor)
        replace(Progression(key: p.key, minor: p.minor, mood: p.mood, steps: steps)) { $0 }
    }

    /// Adds a chord that fits at the end; returns its index.
    @discardableResult
    func appendChord() -> Int? {
        guard let p = progression, p.steps.count < Progressions.lengths.upperBound else { return nil }
        let steps = p.steps + [Progressions.fittingChord(after: p.steps, minor: p.minor)]
        replace(Progression(key: p.key, minor: p.minor, mood: p.mood, steps: steps)) { $0 }
        return steps.count - 1
    }

    /// Adds a given chord at the end; returns its index.
    @discardableResult
    func appendChord(root: Int, quality: String) -> Int? {
        guard let p = progression, p.steps.count < Progressions.lengths.upperBound else { return nil }
        let steps = p.steps + [Progressions.step(offset: root - p.key, quality: quality, minor: p.minor)]
        replace(Progression(key: p.key, minor: p.minor, mood: p.mood, steps: steps)) { $0 }
        return steps.count - 1
    }

    /// Moves the whole progression to another key; every chord keeps its place in the key.
    func setKey(_ key: Int) {
        guard let p = progression else { return }
        replace(Progression(key: ((key % 12) + 12) % 12, minor: p.minor, mood: p.mood, steps: p.steps)) { $0 }
    }

    func removeChord(at i: Int) {
        guard let p = progression, p.steps.count > Progressions.lengths.lowerBound, p.steps.indices.contains(i) else { return }
        var steps = p.steps
        steps.remove(at: i)
        // Removing the chord under the playhead hands its time to the one after it.
        replace(Progression(key: p.key, minor: p.minor, mood: p.mood, steps: steps)) { $0 > i ? $0 - 1 : $0 }
    }

    /// Swaps in an edited progression. When the chord count changes mid-loop, the loop is re-phased so the
    /// next unqueued beat lands on `map(old chord)` at the same place inside the chord: no jump, no restart.
    private func replace(_ new: Progression, map: (Int) -> Int) {
        if playing, let old = progression, old.steps.count != new.steps.count, !old.steps.isEmpty, !new.steps.isEmpty {
            let bpc = Double(beatsPerChord)
            let pos = Self.mod(scheduledUntil - loopOrigin, Double(old.steps.count) * bpc)
            let index = Int(pos / bpc)
            let inChord = pos - Double(index) * bpc
            loopOrigin = scheduledUntil - (Double(map(index) % new.steps.count) * bpc + inChord)
        }
        progression = new
        prefs.progressionLength = min(max(new.steps.count, Progressions.lengths.lowerBound), Progressions.lengths.upperBound)
    }

    private func beat(at sample: UInt64) -> Double {
        let dt = (Double(sample) - Double(anchorSample)) / sampleRate
        return anchorBeat + dt * anchorBPM / 60
    }

    private func sample(at beat: Double) -> UInt64 {
        let t = (beat - anchorBeat) * 60 / anchorBPM
        return UInt64(max(0, Double(anchorSample) + t * sampleRate))
    }

    private func tick() {
        guard playing, let p = progression else { return }
        let now = synth.now
        let nowBeat = beat(at: now)
        // Tempo changes take effect from now: re-anchor the clock.
        if prefs.progressionBPM != anchorBPM {
            anchorBeat = max(nowBeat, anchorBeat)
            anchorSample = max(now, anchorSample)
            anchorBPM = prefs.progressionBPM
        }
        let horizon = beat(at: now) + 0.3 * anchorBPM / 60
        let total = totalBeats
        while scheduledUntil < horizon {
            if !prefs.progressionLoop && scheduledUntil - loopOrigin >= total {
                // Played once: end on the first chord, with a crash, and let it ring.
                if !endingQueued { scheduleEnding(at: scheduledUntil, progression: p) }
                break
            }
            schedule(beat: scheduledUntil, progression: p)
            scheduledUntil += 1
        }
        // Playhead for the UI.
        let b = beat(at: now)
        if b - loopOrigin < 0 {
            // Counting in.
            if chord != nil { chord = nil }
            if beat != nil { beat = nil }
        } else if b >= 0 {
            if !prefs.progressionLoop && b - loopOrigin >= total + 3 { return stop() }
            let inLoop = Self.mod(b - loopOrigin, max(1, total))
            let c = min(p.steps.count - 1, Int(inLoop) / beatsPerChord)
            let bt = Int(inLoop) % beatsPerChord
            if chord != c { chord = c }
            if beat != bt { beat = bt }
        }
    }

    /// Queues every hit falling in beat [b, b + 1). Patterns are written per 4/4 bar.
    private func schedule(beat b: Double, progression p: Progression) {
        if b < loopOrigin {
            // The count-in: sticks on every beat, the first one louder.
            synth.schedule(drum: .rim, at: sample(at: b), velocity: b == 0 ? 0.95 : 0.7)
            return
        }
        let bpc = Double(beatsPerChord)
        let loopBeat = Self.mod(b - loopOrigin, Double(p.steps.count) * bpc)
        let index = Int(loopBeat / bpc)
        let inChord = loopBeat - Double(index) * bpc
        let swing = prefs.progressionSwing
        // Absolute time of a pattern offset, given where this beat sits in the pattern's bar.
        func at(_ offset: Double, barBeat: Double) -> UInt64 {
            let frac = offset - floor(offset)
            // Swing pushes the off-beat eighth late, to the last third of the beat.
            let shifted = swing && abs(frac - 0.5) < 0.01 ? floor(offset) + 2.0 / 3 : offset
            return sample(at: b + shifted - barBeat)
        }

        let barBeat = inChord.truncatingRemainder(dividingBy: 4)
        let notes = chordNotes(root: p.root(index), quality: p.steps[index].quality)
        let pattern = StrumPattern(rawValue: prefs.progressionPattern) ?? .downUp
        let secondsPerBeat = 60 / anchorBPM
        for (offset, hit) in pattern.bar where offset >= barBeat && offset < barBeat + 1 && offset < bpc {
            // Bowed notes last until the next hit.
            let next = pattern.bar.map(\.0).filter { $0 > offset }.min() ?? min(4, bpc)
            let hold = (next - offset) * secondsPerBeat * 0.95
            let t = at(offset, barBeat: barBeat)
            let mute = { (beats: Double) in t + UInt64(beats * secondsPerBeat * self.sampleRate) }
            switch hit {
            case .strum(let up, let v, let m):
                synth.schedule(strum: notes, at: t, up: up, velocity: v, hold: m.map { $0 * secondsPerBeat } ?? hold)
                if let m { synth.schedule(muteAt: mute(m)) }
            case .pick(let k, let v):
                guard !notes.isEmpty else { continue }
                // Slots 0–2 count up from the bass; 3–5 are the three highest strings of the chord.
                let i = k < 3 ? min(k, notes.count - 1) : max(min(2, notes.count - 1), notes.count - 1 - (5 - k))
                synth.schedule(strum: [notes[i]], at: t, up: false, velocity: v, hold: hold * 2)
            case .pinch(let v):
                let treble = Array(notes.dropFirst(notes.count >= 5 ? 2 : 1))
                synth.schedule(strum: treble, at: t, up: false, velocity: v, hold: hold, sweep: 0.004)
            case .chug(let v, let m):
                synth.schedule(strum: Array(notes.prefix(3)), at: t, up: false, velocity: v, hold: m * secondsPerBeat, sweep: 0.006)
                synth.schedule(muteAt: mute(m))
            }
        }

        let drums = DrumPattern(rawValue: prefs.progressionDrums) ?? .off
        let barPos = b.truncatingRemainder(dividingBy: 4)
        if drums == .click {
            synth.schedule(drum: barPos == 0 ? .rim : .hat, at: sample(at: b), velocity: barPos == 0 ? 0.9 : 0.7)
        }
        // The drummer marks the loop: a crash on its first downbeat, a fill over its last beat (two beats every
        // fourth time round). Short loops (under two bars) only get the crash the first time.
        let total = totalBeats
        let pass = Int((b - loopOrigin) / max(1, total))
        let long = total >= 8
        if drums != .off && drums != .click && loopBeat == 0 && (long || pass == 0) {
            synth.schedule(drum: .crash, at: sample(at: b), velocity: 0.75)
        }
        let fillBeats = long && pass % 4 == 3 ? 2 : 1
        let fill = long ? drums.fill(beats: fillBeats) : nil
        let fillStart = total - Double(fillBeats)
        if let fill, loopBeat >= fillStart {
            for (offset, kind, v) in fill where offset >= loopBeat - fillStart && offset < loopBeat - fillStart + 1 {
                synth.schedule(drum: kind, at: sample(at: b + offset - (loopBeat - fillStart)), velocity: v)
            }
        } else {
            for (offset, kind, v) in drums.bar where offset >= barPos && offset < barPos + 1 {
                synth.schedule(drum: kind, at: at(offset, barBeat: barPos), velocity: v)
            }
        }

        // Bass and keys follow the drummer's feel: swung eighths with a jazz or shuffle groove, or with Swing on.
        let styles = bandStyles
        guard styles.bass != .off || styles.keys != .off else { return }
        let feel = swing || drums == .jazz || drums == .shuffle
        func time(_ beat: Double) -> UInt64 {
            let frac = beat - floor(beat)
            return sample(at: feel && abs(frac - 0.5) < 0.01 ? floor(beat) + 2.0 / 3 : beat)
        }
        let next = (index + 1) % p.steps.count
        let context = BackingBand.Beat(beat: b, barPos: barPos, inChord: inChord, chordBeats: bpc,
                                       root: p.root(index), quality: Chords.quality(p.steps[index].quality),
                                       nextRoot: p.root(next), nextQuality: Chords.quality(p.steps[next].quality),
                                       key: p.key, minor: p.minor, drums: drums)
        if styles.bass != .off {
            for e in band.bass(styles.bass, context) {
                synth.schedule(.bass, notes: e.notes, at: time(e.beat), velocity: e.velocity, hold: e.length * secondsPerBeat)
            }
        }
        if styles.keys != .off {
            for e in band.keys(styles.keys, context, bassPlaying: styles.bass != .off, high: prefs.instrument.isKeyboard) {
                synth.schedule(.keys, notes: e.notes, at: time(e.beat), velocity: e.velocity, hold: e.length * secondsPerBeat)
            }
        }
    }

    /// The last beat of a progression played once: its first chord again, struck and left to ring, with the bass
    /// on the root and a crash.
    private func scheduleEnding(at b: Double, progression p: Progression) {
        endingQueued = true
        let t = sample(at: b)
        let secondsPerBeat = 60 / anchorBPM
        synth.schedule(strum: chordNotes(root: p.root(0), quality: p.steps[0].quality), at: t, up: false, velocity: 0.9,
                       hold: 3 * secondsPerBeat)
        let drums = DrumPattern(rawValue: prefs.progressionDrums) ?? .off
        if drums != .off && drums != .click {
            synth.schedule(drum: .crash, at: t, velocity: 0.85)
            synth.schedule(drum: .kick, at: t, velocity: 0.9)
        }
        let styles = bandStyles
        let root = p.root(0)
        if styles.bass != .off { synth.schedule(.bass, notes: [28 + (root + 8) % 12], at: t, velocity: 0.85, hold: 3 * secondsPerBeat) }
        if styles.keys != .off {
            synth.schedule(.keys, notes: PianoVoicing.playable(root: root, quality: Chords.quality(p.steps[0].quality)).dropFirst().map { $0 },
                           at: t, velocity: 0.7, hold: 3 * secondsPerBeat)
        }
    }

    /// The chord's first shape on the current instrument, low to high, with string numbers.
    private func chordNotes(root: Int, quality: String) -> [Synth.Note] {
        let instrument = prefs.instrument, tuning = prefs.tuning
        let q = Chords.quality(quality)
        if instrument.isKeyboard {
            return PianoVoicing.playable(root: root, quality: q).enumerated().map { i, m in
                Synth.Note(frequency: Music.frequency(midi: Double(m), a4: prefs.a4), string: i)
            }
        }
        if let v = ChordsView.voicings(root: root, quality: q, instrument: instrument, tuning: tuning).first {
            return v.frets.enumerated().compactMap { s, f in
                f.map { Synth.Note(frequency: Music.frequency(midi: Double(tuning.notes[s] + $0), a4: prefs.a4), string: s) }
            }
        }
        return q.intervals.enumerated().map { i, iv in
            Synth.Note(frequency: Music.frequency(midi: Double(48 + root + iv), a4: prefs.a4), string: i)
        }
    }
}
