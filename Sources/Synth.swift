import AVFoundation
import os

/// Plucked strings (see StringModel.swift: two-polarization Karplus–Strong, pick position, body
/// and room) for strumming chords, a soft sustained tone for tuning by ear, and the metronome, whose clicks
/// are scheduled inside the render callback so they never drift.
final class Synth {
    static let shared = Synth()

    private var engine: AVAudioEngine?
    private var idleTimer: Timer?
    private let lock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private var incoming: [PluckVoice] = []
    nonisolated(unsafe) private var incomingBows: [BowedVoice] = []
    nonisolated(unsafe) private var incomingSampled: [SampleVoice] = []
    nonisolated(unsafe) private var silenceRequested = false
    /// Recorded takes: played dry and centred, outside the instrument body and room.
    nonisolated(unsafe) private var incomingTracks: [(at: UInt64, voice: SampleVoice)] = []
    nonisolated(unsafe) private var voiceTarget: Float = 1
    /// Sequencer input: voices that must start at an absolute sample time.
    /// Something to start (or stop) at an absolute sample time.
    private struct Timed {
        let at: UInt64
        var plucks: [PluckVoice] = []
        var bows: [BowedVoice] = []
        var sampled: [SampleVoice] = []
        var drums: [DrumVoice] = []
        var backing: [BackingVoice] = []
        /// Stop every ringing string at this time (palm mutes, skanks).
        var mute = false
    }
    nonisolated(unsafe) private var incomingTimed: [Timed] = []
    nonisolated(unsafe) private var backingStopRequested = false
    /// Sample time at the start of the last render cycle, for the sequencer's clock.
    nonisolated(unsafe) private var publishedClock: UInt64 = 0
    /// Keeps the output running between sequenced events (a looping progression).
    nonisolated(unsafe) var keepAlive = false
    nonisolated(unsafe) private var toneTarget: Double?
    nonisolated(unsafe) private var lastSound = Date()
    private var sampleRate = 48000.0

    struct Metronome: Equatable {
        var running = false
        var bpm = 100.0
        var beats = 4
        var subdivision = 1
        var sound = MetronomeSound.classic
    }
    nonisolated(unsafe) private var metronome = Metronome()
    nonisolated(unsafe) private var metronomeRestart = false
    nonisolated(unsafe) private var incomingClicks: [ClickVoice] = []
    /// Last beat played (index in bar) and when, for the UI.
    nonisolated(unsafe) private var lastBeat: (index: Int, at: Date)?

    nonisolated(unsafe) private var incomingTimbre: Timbre?

    // Render-thread state.
    nonisolated(unsafe) private var voices: [PluckVoice] = []
    nonisolated(unsafe) private var bows: [BowedVoice] = []
    nonisolated(unsafe) private var drums: [DrumVoice] = []
    /// Recorded notes: they already carry their instrument's body, so they skip the body filter.
    nonisolated(unsafe) private var sampled: [SampleVoice] = []
    nonisolated(unsafe) private var tracks: [SampleVoice] = []
    /// The progression's bass and keys: their own instruments, mixed with their own level, place and room.
    nonisolated(unsafe) private var backing: [BackingVoice] = []
    nonisolated(unsafe) private var voiceGain: Float = 1
    nonisolated(unsafe) private var voiceGoal: Float = 1
    nonisolated(unsafe) private var clock: UInt64 = 0
    nonisolated(unsafe) private var bodyL = BodyFilter(), bodyR = BodyFilter()
    nonisolated(unsafe) private var room = Room(sampleRate: 48000)
    nonisolated(unsafe) private var roomLevel: Float = 0.2
    nonisolated(unsafe) private var timbreID = ""
    nonisolated(unsafe) private var lastTimbre: Timbre?
    nonisolated(unsafe) private var tone = ToneVoice()
    nonisolated(unsafe) private var clicks: [ClickVoice] = []
    nonisolated(unsafe) private var metro = Metronome()
    nonisolated(unsafe) private var tickCountdown = 0.0
    nonisolated(unsafe) private var tickIndex = 0
    nonisolated(unsafe) private var renderBeat: Int?

    func setMetronome(_ m: Metronome) {
        // Decode the click recordings here, on the main thread, before the audio thread needs them.
        _ = ClickSamples.shared
        if m.running { ensureRunning() }
        lock.withLockUnchecked {
            if m.running && !metronome.running { metronomeRestart = true; lastBeat = nil }
            metronome = m
        }
    }

    /// Lets the user hear a sound before choosing it: the downbeat, then a normal beat.
    func previewClick(_ sound: MetronomeSound) {
        _ = ClickSamples.shared
        ensureRunning()
        let sr = sampleRate
        let clicks = [ClickVoice(kind: .accent, sound: sound, sampleRate: sr),
                      ClickVoice(kind: .beat, sound: sound, sampleRate: sr, delay: Int(sr * 0.45))]
        lock.withLockUnchecked { incomingClicks += clicks }
    }

    var beat: (index: Int, at: Date)? { lock.withLockUnchecked { metronome.running ? lastBeat : nil } }

    struct Note {
        let frequency: Double
        /// String index, so a new note on the same string silences the old one.
        var string: Int? = nil
    }

    /// A strum like a hand makes it: low→high on a downstroke, high→low (lighter, mostly the treble
    /// strings) on an upstroke, with a little human variation in timing and force.
    func strum(_ notes: [Note], up: Bool = false, velocity: Double = 0.85) {
        ensureRunning()
        let timbre = Timbre.current()
        let (plucks, bows, recorded) = buildStrum(notes, up: up, velocity: velocity, timbre: timbre, hold: up ? 0.5 : 1.3)
        lock.withLockUnchecked {
            incoming += plucks
            incomingBows += bows
            incomingSampled += recorded
            incomingTimbre = timbre
        }
    }

    /// Voices for a strum: recorded notes when the instrument's samples are loaded, else the model.
    private func buildStrum(_ notes: [Note], up: Bool, velocity: Double, timbre: Timbre,
                            hold: Double, sweep: Double? = nil) -> ([PluckVoice], [BowedVoice], [SampleVoice]) {
        let sr = sampleRate
        let strings = max(2, Prefs.shared.tuning.notes.count)
        let pan = { (s: Int?) in s.map { max(-0.25, min(0.25, Double($0) / Double(strings - 1) * 0.5 - 0.25)) } ?? 0 }
        if let id = timbre.samples, let set = SampleLibrary.shared.notes(id), !set.isEmpty {
            if timbre.bowed {
                let voices = notes.enumerated().map { i, n in
                    SampleVoice(notes: set, midi: Music.midi(frequency: n.frequency, a4: 440), sampleRate: sr,
                                delay: Int(Double(i) * 0.04 * sr), velocity: velocity * (up ? 0.75 : 1), hold: hold,
                                string: n.string, pan: Double(i) / Double(max(1, notes.count - 1)) * 0.4 - 0.2, release: 0.12)
                }
                return ([], [], voices)
            }
            let keys = timbre.id == "piano"
            var order = up && !keys ? Array(notes.reversed()) : notes
            if up && order.count >= 5 && !keys { order = Array(order.prefix(4)) }
            // On piano an "upstroke" is the right hand alone, a little softer.
            if up && keys && order.count > 2 { order.removeFirst() }
            var t = 0.0
            let voices = order.map { n -> SampleVoice in
                let v = max(0.2, min(1, velocity * (up ? 0.7 : 1) + Double.random(in: -0.06...0.06)))
                let voice = SampleVoice(notes: set, midi: Music.midi(frequency: n.frequency, a4: 440), sampleRate: sr,
                                        delay: Int(t * sr), velocity: v, hold: nil, string: n.string, pan: pan(n.string))
                // Hands on keys are almost together; a pick sweeps across the strings.
                t += keys ? Double.random(in: 0.001...0.006) : (sweep ?? (up ? 0.014 : 0.019)) * Double.random(in: 0.75...1.25)
                return voice
            }
            return ([], [], voices)
        }
        if timbre.bowed {
            // A bowed chord: a quick roll across the strings, then sustained.
            let new = notes.enumerated().map { i, n in
                BowedVoice(frequency: n.frequency, sampleRate: sr, delay: Int(Double(i) * 0.04 * sr), duration: hold,
                           velocity: velocity * (up ? 0.75 : 1), timbre: timbre, string: n.string,
                           pan: Double(i) / Double(max(1, notes.count - 1)) * 0.4 - 0.2, seed: UInt32.random(in: 1...UInt32.max))
            }
            return ([], new, [])
        }
        var order = up ? Array(notes.reversed()) : notes
        if up && order.count >= 5 { order = Array(order.prefix(4)) }
        // Pan by the string's place on the instrument (not within this strum, which may be one note).
        var t = 0.0
        let new = order.enumerated().map { i, n -> PluckVoice in
            let v = max(0.2, min(1, velocity * (up ? 0.7 : 1) + Double.random(in: -0.06...0.06)))
            let voice = PluckVoice(frequency: n.frequency, sampleRate: sr, delay: Int(t * sr), velocity: v, timbre: timbre,
                                   string: n.string, pan: pan(n.string),
                                   seed: UInt32.random(in: 1...UInt32.max))
            t += (sweep ?? (up ? 0.014 : 0.019)) * Double.random(in: 0.75...1.25)
            _ = i
            return voice
        }
        return (new, [], [])
    }

    /// Clears filter and room state (render thread).
    private func resetBus() {
        if let t = lastTimbre {
            bodyL = BodyFilter(t, sampleRate: sampleRate)
            bodyR = BodyFilter(t, sampleRate: sampleRate)
        }
        room = Room(sampleRate: sampleRate)
    }

    // MARK: - Sequencer

    var outputSampleRate: Double { sampleRate }

    /// Sample time of the audio being rendered now.
    var now: UInt64 {
        #if SNAPSHOT
        if let t = testClock { return t }
        #endif
        return lock.withLockUnchecked { publishedClock }
    }

    func prepare() {
        #if SNAPSHOT
        if testClock != nil { return }
        #endif
        ensureRunning()
    }

    #if SNAPSHOT
    /// Tests drive the sequencer with a fake clock and record what it schedules instead of playing it.
    var testClock: UInt64?
    var testRecorder: ((String, UInt64) -> Void)?
    #endif

    /// A strum that starts exactly at sample `at` (see `now`). `hold` is how long bowed notes last, in seconds.
    func schedule(strum notes: [Note], at: UInt64, up: Bool, velocity: Double, hold: Double, sweep: Double? = nil) {
        #if SNAPSHOT
        if let r = testRecorder { return r(notes.count == 1 ? "pick" : (up ? "U" : "D"), at) }
        #endif
        let timbre = Timbre.current()
        let (plucks, bows, recorded) = buildStrum(notes, up: up, velocity: velocity, timbre: timbre, hold: hold, sweep: sweep)
        lock.withLockUnchecked {
            incomingTimed.append(Timed(at: at, plucks: plucks, bows: bows, sampled: recorded))
            incomingTimbre = timbre
        }
    }

    /// Stops every ringing string at sample `at` (a palm mute or a choked strum).
    func schedule(muteAt at: UInt64) {
        #if SNAPSHOT
        if let r = testRecorder { return r("mute", at) }
        #endif
        lock.withLockUnchecked { incomingTimed.append(Timed(at: at, mute: true)) }
    }

    func schedule(drum: DrumKind, at: UInt64, velocity: Double) {
        #if SNAPSHOT
        if let r = testRecorder { return r("\(drum)", at) }
        #endif
        let d = DrumVoice(kind: drum, sampleRate: sampleRate, velocity: velocity)
        lock.withLockUnchecked { incomingTimed.append(Timed(at: at, drums: [d])) }
    }

    /// The progression's backing band. Each part plays its own recorded instrument, whatever instrument is chosen.
    enum BackingPart: String {
        case bass, keys
        var samples: String { self == .bass ? "bass" : "piano" }
        /// Level over the set's own (which is set for a strummed chord): measured so the bass sits ~3 LU under the
        /// guitar's strumming and pads ~8 LU under it.
        var gain: Double { 1.3 }
        /// Bass in the centre, keys a little left of the guitar.
        var pan: Double { self == .bass ? 0 : -0.32 }
        /// Room: the bass nearly dry and tight, the piano with some air.
        var send: Float { self == .bass ? 0.05 : 0.5 }
        /// How fast a let-go note dies: a bassist's muting hand, a piano damper.
        var release: Double { self == .bass ? 0.04 : 0.14 }
    }

    /// Bass or keys notes (MIDI, at A4 = 440 before the user's reference pitch) starting at sample `at`, held `hold` seconds.
    func schedule(_ part: BackingPart, notes: [Int], at: UInt64, velocity: Double, hold: Double) {
        #if SNAPSHOT
        if let r = testRecorder { return r("\(part.rawValue) " + notes.map(String.init).joined(separator: ","), at) }
        #endif
        guard !notes.isEmpty, let set = SampleLibrary.shared.notes(part.samples), !set.isEmpty else { return }
        let sr = sampleRate
        let shift = 12 * log2(Prefs.shared.a4 / 440)
        var t = 0.0
        let voices = notes.map { m -> BackingVoice in
            let v = max(0.15, min(1, velocity + Double.random(in: -0.04...0.04)))
            let voice = SampleVoice(notes: set, midi: Double(m) + shift, sampleRate: sr, delay: Int(t * sr), velocity: v,
                                    hold: hold, string: nil, pan: part.pan, release: part.release, gain: part.gain)
            // A pianist's fingers land almost, not quite, together.
            t += Double.random(in: 0.002...0.007)
            return BackingVoice(voice: voice, send: part.send)
        }
        lock.withLockUnchecked { incomingTimed.append(Timed(at: at, backing: voices)) }
    }

    /// Lets go of the bass and keys (the loop stopped): no pad left hanging.
    func stopBacking() {
        lock.withLockUnchecked { backingStopRequested = true }
    }

    /// Plays a recording (the user's sung take) starting exactly at sample `at`.
    func schedule(audio note: SampleNote, at: UInt64) {
        let v = SampleVoice(notes: [note], midi: note.midi, sampleRate: sampleRate, delay: 0, velocity: 1, hold: nil,
                            string: nil, pan: 0, release: 0.05, raw: true)
        lock.withLockUnchecked { incomingTracks.append((at, v)) }
    }

    /// Mutes or unmutes the user's voice track, even while it plays (a short fade, no click).
    func setVoiceEnabled(_ on: Bool) { lock.withLockUnchecked { voiceTarget = on ? 1 : 0 } }

    /// Drops everything scheduled but not yet sounding (the loop was stopped).
    func cancelScheduled() {
        lock.withLockUnchecked {
            incomingTimed.removeAll()
            incomingTracks.removeAll()
        }
    }

    /// Notes one after another (scales), `stagger` seconds apart.
    func strum(_ frequencies: [Double], stagger: Double = 0.028) {
        ensureRunning()
        let sr = sampleRate
        let timbre = Timbre.current()
        if let id = timbre.samples, let set = SampleLibrary.shared.notes(id), !set.isEmpty {
            // Recorded melody: bowed notes legato, plucked notes left to ring a little into the next.
            let hold = timbre.bowed ? max(0.25, stagger + 0.03) : (frequencies.count > 1 ? stagger * 2.5 : nil)
            let new = frequencies.enumerated().map { i, f in
                SampleVoice(notes: set, midi: Music.midi(frequency: f, a4: 440), sampleRate: sr,
                            delay: Int(Double(i) * stagger * sr), velocity: 0.75, hold: hold, string: nil, pan: 0,
                            release: timbre.bowed ? 0.1 : 0.25)
            }
            lock.withLockUnchecked { incomingSampled += new; incomingTimbre = timbre }
            return
        }
        if timbre.bowed {
            // Bowed melody: legato, each note held until the next one.
            let hold = frequencies.count > 1 ? max(0.25, stagger + 0.03) : 0.9
            let new = frequencies.enumerated().map { i, f in
                BowedVoice(frequency: f, sampleRate: sr, delay: Int(Double(i) * stagger * sr), duration: hold, velocity: 0.8,
                           timbre: timbre, string: nil, pan: 0, seed: UInt32.random(in: 1...UInt32.max))
            }
            lock.withLockUnchecked { incomingBows += new; incomingTimbre = timbre }
            return
        }
        let new = frequencies.enumerated().map { i, f in
            PluckVoice(frequency: f, sampleRate: sr, delay: Int(Double(i) * stagger * sr), velocity: 0.75, timbre: timbre,
                       string: nil, pan: 0, seed: UInt32.random(in: 1...UInt32.max))
        }
        lock.withLockUnchecked {
            incoming += new
            incomingTimbre = timbre
        }
    }

    func pluck(_ frequency: Double) { strum([frequency]) }

    /// Stops everything that is playing or scheduled (a scale run the user stopped).
    func silence() {
        lock.withLockUnchecked {
            incoming.removeAll()
            incomingBows.removeAll()
            incomingSampled.removeAll()
            incomingTracks.removeAll()
            silenceRequested = true
        }
    }

    /// Sustained reference tone; nil fades it out.
    func setTone(_ frequency: Double?) {
        if frequency != nil { ensureRunning() }
        lock.withLockUnchecked { toneTarget = frequency }
    }

    private func ensureRunning() {
        if engine?.isRunning == true { return }
        let engine = AVAudioEngine()
        let format = engine.outputNode.inputFormat(forBus: 0)
        sampleRate = format.sampleRate > 0 ? format.sampleRate : 48000
        let sr = sampleRate
        let stereo = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        room = Room(sampleRate: sr)
        let source = AVAudioSourceNode(format: stereo) { [unowned self] _, _, frameCount, abl in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            let outL = buffers[0].mData!.assumingMemoryBound(to: Float.self)
            let outR = buffers[buffers.count > 1 ? 1 : 0].mData!.assumingMemoryBound(to: Float.self)
            let frames = Int(frameCount)
            if let target = self.lock.withLockIfAvailableUnchecked({ () -> Double in
                // A new note on a string releases whatever that string was still sounding.
                for s in (self.incoming.compactMap(\.string) + self.incomingBows.compactMap(\.string)
                          + self.incomingSampled.compactMap(\.string)) {
                    for v in self.voices.indices where self.voices[v].string == s { self.voices[v].release() }
                    for b in self.bows.indices where self.bows[b].string == s { self.bows[b].release() }
                    for v in self.sampled.indices where self.sampled[v].string == s { self.sampled[v].release() }
                }
                self.sampled += self.incomingSampled
                self.incomingSampled.removeAll(keepingCapacity: true)
                if self.silenceRequested {
                    self.silenceRequested = false
                    for v in self.voices.indices { self.voices[v].release() }
                    for b in self.bows.indices { self.bows[b].release() }
                    for v in self.sampled.indices { self.sampled[v].release() }
                    for t in self.tracks.indices { self.tracks[t].release() }
                    self.tracks.removeAll { !$0.started }
                    // Notes still waiting for their turn never start.
                    self.voices.removeAll { !$0.started }
                    self.bows.removeAll { !$0.started }
                    self.sampled.removeAll { !$0.started }
                }
                self.publishedClock = self.clock
                // Before anything newly queued joins: a stop followed by a restart keeps the new notes.
                if self.backingStopRequested {
                    self.backingStopRequested = false
                    self.backing.removeAll { !$0.voice.started }
                    for v in self.backing.indices { self.backing[v].voice.release() }
                }
                for item in self.incomingTimed {
                    let offset = item.at > self.clock ? Int(item.at - self.clock) : 0
                    if item.mute {
                        for v in self.voices.indices where self.voices[v].string != nil && self.voices[v].delay <= offset {
                            self.voices[v].releaseAt(offset)
                        }
                        for v in self.sampled.indices where self.sampled[v].string != nil && self.sampled[v].delay <= offset {
                            self.sampled[v].releaseAt(offset)
                        }
                        continue
                    }
                    for s in item.plucks.compactMap(\.string) + item.bows.compactMap(\.string) + item.sampled.compactMap(\.string) {
                        // A scheduled strum chokes its strings when it starts, not when it is queued.
                        // Includes notes queued earlier that will have started by then.
                        for v in self.voices.indices where self.voices[v].string == s && self.voices[v].delay <= offset {
                            self.voices[v].releaseAt(offset)
                        }
                        for v in self.sampled.indices where self.sampled[v].string == s && self.sampled[v].delay <= offset {
                            self.sampled[v].releaseAt(offset)
                        }
                    }
                    self.sampled += item.sampled.map { var v = $0; v.delay += offset; return v }
                    self.voices += item.plucks.map { var v = $0; v.delay += offset; return v }
                    self.bows += item.bows.map { var v = $0; v.delay += offset; return v }
                    // A closed hi-hat (or the hat struck again) chokes an open one still ringing.
                    if item.drums.contains(where: { $0.kind == .hat || $0.kind == .openHat }) {
                        for v in self.drums.indices where self.drums[v].kind == .openHat && self.drums[v].delay < offset {
                            self.drums[v].chokeAt(offset)
                        }
                    }
                    self.drums += item.drums.map { var v = $0; v.delay += offset; return v }
                    self.backing += item.backing.map { var v = $0; v.voice.delay += offset; return v }
                }
                self.incomingTimed.removeAll(keepingCapacity: true)
                for (at, v) in self.incomingTracks {
                    var voice = v
                    voice.delay += at > self.clock ? Int(at - self.clock) : 0
                    self.tracks.append(voice)
                }
                self.incomingTracks.removeAll(keepingCapacity: true)
                self.voiceGoal = self.voiceTarget
                self.voices += self.incoming
                self.incoming.removeAll(keepingCapacity: true)
                self.bows += self.incomingBows
                self.incomingBows.removeAll(keepingCapacity: true)
                if let t = self.incomingTimbre, t.id != self.timbreID {
                    self.timbreID = t.id
                    self.lastTimbre = t
                    self.bodyL = BodyFilter(t, sampleRate: sr)
                    self.bodyR = BodyFilter(t, sampleRate: sr)
                    self.roomLevel = Float(t.reverb)
                }
                self.incomingTimbre = nil
                self.clicks += self.incomingClicks
                self.incomingClicks.removeAll(keepingCapacity: true)
                if self.keepAlive || !self.tracks.isEmpty || !self.backing.isEmpty || !self.sampled.isEmpty || !self.drums.isEmpty || !self.voices.isEmpty || !self.bows.isEmpty || !self.clicks.isEmpty || self.toneTarget != nil || self.tone.amp > 0.0001 || self.metronome.running {
                    self.lastSound = Date()
                }
                if self.metronomeRestart {
                    self.metronomeRestart = false
                    self.tickCountdown = 0
                    self.tickIndex = 0
                }
                self.metro = self.metronome
                if let b = self.renderBeat {
                    self.lastBeat = (b, Date())
                    self.renderBeat = nil
                }
                return self.toneTarget ?? 0
            }) {
                self.tone.target = target
            }
            let m = self.metro
            for i in 0..<frames {
                if m.running {
                    if self.tickCountdown <= 0 {
                        let sub = self.tickIndex % m.subdivision
                        let beat = (self.tickIndex / m.subdivision) % m.beats
                        let kind: ClickVoice.Kind = sub != 0 ? .sub : (beat == 0 ? .accent : .beat)
                        self.clicks.append(ClickVoice(kind: kind, sound: m.sound, sampleRate: sr))
                        if sub == 0 { self.renderBeat = beat }
                        self.tickCountdown += sr * 60 / m.bpm / Double(m.subdivision)
                        self.tickIndex += 1
                    }
                    self.tickCountdown -= 1
                }
                var l: Float = 0, r: Float = 0
                for v in self.voices.indices {
                    let x = self.voices[v].next()
                    l += x * self.voices[v].panL
                    r += x * self.voices[v].panR
                }
                for b in self.bows.indices {
                    let x = self.bows[b].next()
                    l += x * self.bows[b].panL
                    r += x * self.bows[b].panR
                }
                l = Float(self.bodyL.process(Double(l)))
                r = Float(self.bodyR.process(Double(r)))
                for v in self.sampled.indices {
                    let x = self.sampled[v].next()
                    l += x * self.sampled[v].panL
                    r += x * self.sampled[v].panR
                }
                // Never let a bad sample poison the filters: a NaN would silence everything from then on.
                if !l.isFinite || !r.isFinite {
                    l = 0
                    r = 0
                    self.resetBus()
                }
                var roomIn = l + r
                for v in self.backing.indices {
                    let x = self.backing[v].voice.next()
                    l += x * self.backing[v].voice.panL
                    r += x * self.backing[v].voice.panR
                    roomIn += x * self.backing[v].send
                }
                let (wl, wr) = self.room.process(roomIn)
                l += wl * self.roomLevel
                r += wr * self.roomLevel
                var center = self.tone.next(sr)
                for c in self.clicks.indices { center += self.clicks[c].next() }
                var dl: Float = 0, dr: Float = 0
                for d in self.drums.indices {
                    let x = self.drums[d].next()
                    dl += x * self.drums[d].panL
                    dr += x * self.drums[d].panR
                }
                if !self.tracks.isEmpty {
                    self.voiceGain += (self.voiceGoal - self.voiceGain) * 0.002
                    for t in self.tracks.indices { center += self.tracks[t].next() * self.voiceGain }
                }
                outL[i] = tanhf(l + center + dl)
                outR[i] = tanhf(r + center + dr)
            }
            self.voices.removeAll { $0.finished }
            self.bows.removeAll { $0.finished }
            self.clicks.removeAll { $0.finished }
            self.drums.removeAll { $0.finished }
            self.sampled.removeAll { $0.finished }
            self.backing.removeAll { $0.voice.finished }
            self.tracks.removeAll { $0.finished }
            self.clock += UInt64(frames)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: stereo)
        engine.mainMixerNode.outputVolume = 0.8
        do { try engine.start() } catch { return }
        self.engine = engine

        // Release the output device after a few quiet seconds.
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self else { return t.invalidate() }
            let quiet = self.lock.withLockUnchecked { Date().timeIntervalSince(self.lastSound) > 4 }
            if quiet {
                self.engine?.stop()
                self.engine = nil
                self.voices = []
                self.bows = []
                self.sampled = []
                self.backing = []
                self.tracks = []
                self.tone = ToneVoice()
                t.invalidate()
            }
        }
    }
}

/// A bass or keys note and how much of it goes to the room.
struct BackingVoice {
    var voice: SampleVoice
    let send: Float
}

enum DrumKind {
    case kick, snare, rim, hat, openHat, clap, shaker, ride, tom

    /// Name of its recording in Resources/Samples/drums.
    var file: String {
        switch self {
        case .openHat: "openhat"
        default: "\(self)"
        }
    }

    /// Kick, snare and hi-hat have a soft layer, played below this velocity.
    var softBelow: Double? {
        switch self {
        case .kick, .snare, .hat: 0.5
        default: nil
        }
    }

    /// Where it sits in the stereo picture (-1 left … 1 right), heard from the audience: hats a little right,
    /// ride and floor tom a little left, kick, snare and hand percussion near the middle.
    var pan: Float {
        switch self {
        case .kick, .clap: 0
        case .snare, .rim: -0.05
        case .hat, .openHat: 0.3
        case .shaker: 0.15
        case .ride: -0.35
        case .tom: -0.25
        }
    }
}

/// The progression player's recorded kit (Resources/Samples/drums, made by tools/render_drums.swift): one-shots
/// from a real acoustic kit, already balanced against one another, with soft layers for kick, snare and hi-hat.
/// Decoded once, off the audio thread (the first `DrumVoice` made loads them).
final class DrumSamples {
    static let shared = DrumSamples()
    /// The velocity a soft layer was recorded to stand for (see render_drums.swift).
    static let softVelocity = 0.35
    let rate: Double
    private var hits: [String: [Float]] = [:]  // written only in init

    private init() {
        var rate = 48000.0
        let dir = Bundle.main.url(forResource: "drums", withExtension: nil, subdirectory: "Samples")
        func read(_ name: String) -> [Float]? {
            guard let url = dir?.appendingPathComponent(name + ".wav"),
                  let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil, buffer.frameLength > 0 else { return nil }
            rate = file.processingFormat.sampleRate
            // Trailing zeros let the interpolator read past the end.
            return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))) + [0, 0, 0]
        }
        let kinds: [DrumKind] = [.kick, .snare, .rim, .hat, .openHat, .clap, .shaker, .ride, .tom]
        for k in kinds {
            hits[k.file] = read(k.file)
            if k.softBelow != nil { hits[k.file + "-soft"] = read(k.file + "-soft") }
        }
        self.rate = rate
    }

    /// The recording for a hit, or nil when it is missing (the synthesized drum stands in).
    func hit(_ kind: DrumKind, soft: Bool) -> [Float]? {
        soft ? hits[kind.file + "-soft"] ?? hits[kind.file] : hits[kind.file]
    }
}

/// One drum hit for the progression player, started exactly on its sample: the recorded kit, or a small
/// synthesized one when the recordings are missing (a bare dev build).
struct DrumVoice {
    let kind: DrumKind
    private let sr: Double
    private let gain: Double
    let panL: Float, panR: Float
    var delay = 0
    private var n = 0
    private let length: Int
    private var phase = 0.0
    private var seed: UInt32 = 0x1234_5679
    private var hpX = 0.0, hpY = 0.0
    // Recorded hit.
    private let data: [Float]?
    private let step: Double
    private var pos = 0.0
    /// Samples until a closed hi-hat chokes this one (open hat), then a fast fade.
    private var chokeIn: Int?
    private var choke: Float = 1
    var finished: Bool {
        if delay > 0 { return false }
        if choke < 0.001 { return true }
        if let data { return Int(pos) + 2 >= data.count }
        return n >= length
    }

    init(kind: DrumKind, sampleRate: Double, velocity: Double) {
        self.kind = kind
        sr = sampleRate
        panL = min(1, 1 - kind.pan)
        panR = min(1, 1 + kind.pan)
        let kit = DrumSamples.shared
        let soft = kind.softBelow.map { velocity < $0 } ?? false
        if let d = kit.hit(kind, soft: soft) {
            data = d
            // No two hits quite alike: a touch of variation in force and tuning, as from a drummer's hand.
            step = kit.rate / sampleRate * Double.random(in: 0.996...1.004)
            gain = (soft ? velocity / DrumSamples.softVelocity : velocity) * Double.random(in: 0.94...1.06)
            length = 0
            return
        }
        data = nil
        step = 1
        let (g, len): (Double, Double) = switch kind {
        case .kick: (0.95, 0.4)
        case .snare: (0.55, 0.25)
        case .rim: (0.4, 0.06)
        case .hat: (0.3, 0.06)
        case .openHat: (0.3, 0.3)
        case .clap: (0.45, 0.22)
        case .shaker: (0.42, 0.07)
        case .ride: (0.3, 1.0)
        case .tom: (0.7, 0.35)
        }
        gain = g * velocity
        length = Int(sampleRate * len)
    }

    /// Closes the hi-hat `offset` samples from now (render thread).
    mutating func chokeAt(_ offset: Int) {
        if chokeIn == nil || offset < chokeIn! { chokeIn = offset }
    }

    private mutating func noise() -> Double {
        seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
        return Double(seed) / Double(UInt32.max) * 2 - 1
    }

    mutating func next() -> Float {
        if let c = chokeIn {
            if c > 0 { chokeIn = c - 1 } else { choke *= 0.9985 }  // ~14 ms to close (at 48 kHz)
        }
        if delay > 0 { delay -= 1; return 0 }
        if let data {
            let i = Int(pos)
            guard i + 2 < data.count else { return 0 }
            let t = Float(pos - Double(i))
            let y0 = i > 0 ? data[i - 1] : 0, y1 = data[i], y2 = data[i + 1], y3 = data[i + 2]
            let s = y1 + 0.5 * t * (y2 - y0 + t * (2 * y0 - 5 * y1 + 4 * y2 - y3 + t * (3 * (y1 - y2) + y3 - y0)))
            pos += step
            return s * Float(gain) * choke
        }
        let t = Double(n) / sr
        n += 1
        let v: Double
        switch kind {
        case .kick:
            // A sine whose pitch drops fast (the beater) into a low boom.
            let f = 48 + 90 * exp(-t / 0.03)
            phase += f / sr
            v = sin(2 * .pi * phase) * exp(-t / 0.22) + (t < 0.002 ? noise() * 0.3 : 0)
        case .snare:
            let x = noise()
            hpY = 0.7 * (hpY + x - hpX); hpX = x
            v = 0.55 * sin(2 * .pi * 190 * t) * exp(-t / 0.04) + hpY * exp(-t / 0.09)
        case .rim:
            v = (sin(2 * .pi * 1700 * t) * 0.6 + sin(2 * .pi * 520 * t)) * exp(-t / 0.012)
        case .hat, .openHat:
            let x = noise()
            hpY = 0.55 * (hpY + x - hpX); hpX = x
            v = hpY * exp(-t / (kind == .hat ? 0.018 : 0.11))
        case .clap:
            // Three quick slaps, then the room.
            let x = noise()
            hpY = 0.75 * (hpY + x - hpX); hpX = x
            let bursts = [0.0, 0.011, 0.022].reduce(0.0) { $0 + (t >= $1 ? exp(-(t - $1) / 0.006) : 0) }
            v = hpY * (bursts * 0.6 + exp(-t / 0.06) * 0.5)
        case .shaker:
            let x = noise()
            hpY = 0.4 * (hpY + x - hpX); hpX = x
            v = hpY * min(1, t / 0.006) * exp(-t / 0.025)
        case .ride:
            // Inharmonic partials of a cymbal bell, over a wash of noise.
            let partials = [3150.0, 4230.0, 5370.0, 6810.0, 8100.0]
            var metal = 0.0
            for f in partials { metal += sin(2 * .pi * f * t) > 0 ? 1 : -1 }
            let x = noise()
            hpY = 0.5 * (hpY + x - hpX); hpX = x
            v = (metal * 0.12 + hpY * 0.5) * (0.65 * exp(-t / 0.07) + 0.35 * exp(-t / 0.6))
        case .tom:
            let f = 95 + 60 * exp(-t / 0.05)
            phase += f / sr
            v = sin(2 * .pi * phase) * exp(-t / 0.25)
        }
        return Float(v * gain) * choke
    }
}

enum MetronomeSound: String, CaseIterable {
    case classic, wood, cowbell, hihat, beep

    var name: String {
        switch self {
        case .classic: "Classic"
        case .wood: "Woodblock"
        case .beep: "Beep"
        case .cowbell: "Cowbell"
        case .hihat: "Hi-hat"
        }
    }

    var detail: String {
        switch self {
        case .classic: "mechanical tick, bell on one"
        case .wood: "warm and woody"
        case .beep: "clean electronic tone"
        case .cowbell: "cuts through a band"
        case .hihat: "soft, drummer-friendly"
        }
    }
}

/// The metronome's recorded hits (Resources/Samples/metronome, made by tools/render_metronome.swift):
/// for every sound a downbeat and a beat, already balanced and at the same loudness as the other sounds.
/// Decoded once on the main thread (see `Synth.setMetronome`), never on the audio thread.
final class ClickSamples {
    static let shared = ClickSamples()
    let rate: Double
    private var hits: [MetronomeSound: (accent: [Float], beat: [Float])] = [:]  // written only in init

    private init() {
        var rate = 48000.0
        let dir = Bundle.main.url(forResource: "metronome", withExtension: nil, subdirectory: "Samples")
        func read(_ name: String) -> [Float]? {
            guard let url = dir?.appendingPathComponent(name + ".wav"),
                  let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil, buffer.frameLength > 0 else { return nil }
            rate = file.processingFormat.sampleRate
            // Trailing zeros let the interpolator read past the end.
            return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))) + [0, 0, 0]
        }
        // Without the recordings (a bare dev build), a plain beep keeps the metronome audible.
        func beep(_ f: Double) -> [Float] {
            (0..<Int(rate * 0.08)).map { Float(0.35 * sin(2 * .pi * f * Double($0) / rate) * exp(-Double($0) / rate / 0.02)) } + [0, 0, 0]
        }
        for s in MetronomeSound.allCases {
            hits[s] = (read("\(s.rawValue)-accent") ?? beep(1760), read("\(s.rawValue)-beat") ?? beep(1318.5))
        }
        self.rate = rate
    }

    func hit(_ sound: MetronomeSound, accent: Bool) -> [Float] {
        guard let h = hits[sound] else { return [0, 0, 0] }
        return accent ? h.accent : h.beat
    }
}

/// One metronome click: a recorded hit started exactly on its sample; subdivisions are a softer beat.
struct ClickVoice {
    enum Kind { case accent, beat, sub }
    private let data: [Float]
    private let step: Double
    private let gain: Float
    private var pos = 0.0
    private var delay: Int
    var finished: Bool { delay == 0 && Int(pos) + 2 >= data.count }

    init(kind: Kind, sound: MetronomeSound, sampleRate: Double, delay: Int = 0) {
        let kit = ClickSamples.shared
        data = kit.hit(sound, accent: kind == .accent)
        step = kit.rate / sampleRate
        gain = kind == .sub ? 0.58 : 1
        self.delay = delay
    }

    mutating func next() -> Float {
        if delay > 0 { delay -= 1; return 0 }
        let i = Int(pos)
        guard i + 2 < data.count else { return 0 }
        let t = Float(pos - Double(i))
        let y0 = i > 0 ? data[i - 1] : 0, y1 = data[i], y2 = data[i + 1], y3 = data[i + 2]
        // Catmull-Rom when the output rate differs from the recordings' (exact samples when it doesn't).
        let s = y1 + 0.5 * t * (y2 - y0 + t * (2 * y0 - 5 * y1 + 4 * y2 - y3 + t * (3 * (y1 - y2) + y3 - y0)))
        pos += step
        return s * gain
    }
}

struct ToneVoice {
    var target = 0.0
    private var freq = 0.0
    private var phase = 0.0
    private(set) var amp: Float = 0

    mutating func next(_ sr: Double) -> Float {
        if target > 0 { freq = target }
        let goal: Float = target > 0 ? 0.22 : 0
        amp += (goal - amp) * (goal > amp ? 0.0015 : 0.0006)
        guard amp > 0.00005, freq > 0 else { return 0 }
        phase += freq / sr
        if phase >= 1 { phase -= 1 }
        let x = 2 * Double.pi * phase
        // A few soft harmonics so low notes are audible on laptop speakers.
        let v = sin(x) + 0.5 * sin(2 * x) + 0.25 * sin(3 * x) + 0.12 * sin(4 * x)
        return Float(v / 1.87) * amp
    }
}
