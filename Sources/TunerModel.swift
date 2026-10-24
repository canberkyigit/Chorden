import AVFoundation
import Combine
import os

struct Reading: Equatable {
    /// A pitch is being heard right now; otherwise the last reading is held (dimmed).
    var hasSignal = false
    var frequency: Double = 0
    /// Detected pitch as a continuous MIDI number.
    var midi: Double = 0
    /// The note being tuned to, named by its nearest semitone…
    var target: Int?
    /// …and its exact pitch (differs from `target` for koma-inflected makam degrees).
    var targetPitch: Double = 0
    /// Smoothed deviation from `targetPitch`, in cents.
    var cents: Double = 0
    /// String index (instrument mode) or makam degree (makam mode).
    var string: Int?
    var inTune = false
    /// Input level 0…1, quantized to keep redraws cheap.
    var level: Double = 0
}

/// One string in the all-strings view.
struct PolyString: Equatable {
    var cents: Double?
    /// Heard in the last moment; stale readings are drawn dimmed.
    var fresh = false
}

enum TunerStatus: Equatable { case idle, listening, denied, failed(String) }

/// Owns the microphone while any view that needs it is on screen, analyses on a background queue
/// at 50 Hz and publishes the result: a single-pitch reading, all strings at once, or a chord.
final class TunerModel: ObservableObject {
    static let shared = TunerModel()

    @Published private(set) var reading = Reading()
    @Published private(set) var poly: [PolyString] = []
    @Published private(set) var chord: DetectedChord?
    @Published private(set) var status = TunerStatus.idle
    /// String (or makam degree) the user pinned; nil = pick the closest automatically.
    @Published var lockedString: Int? { didSet { pushConfig(); updateTone() } }
    /// Sustained reference tone for the active string (or note), for tuning by ear.
    @Published var referenceOn = false {
        didSet {
            updateTone()
            // The mic hears our own tone; ignore it for tuned-string marks until its fade-out is over.
            if !referenceOn { referenceQuietAt = Date().addingTimeInterval(1.2) }
        }
    }
    @Published private(set) var tunedStrings: Set<Int> = []
    /// Recent smoothed cents (nil = silence), newest last. Updated together with `reading`.
    private(set) var trace: [Double?] = []

    /// Set by the views that need these analyses while they're on screen.
    var polyActive = false { didSet { if polyActive != oldValue { pushConfig() } } }
    var chordListening = false { didSet { if chordListening != oldValue { chord = nil; pushConfig() } } }
    /// The intonation check measures raw pitch, not distance to a string.
    var intonationActive = false { didSet { if intonationActive != oldValue { pushConfig() } } }
    /// The Sing tab wants every pitch as it is (chromatic), whatever the tuner is set to.
    var singing = false { didSet { if singing != oldValue { pushConfig() } } }

    private var referenceQuietAt = Date.distantPast
    private let prefs = Prefs.shared
    private let input = AudioInput()
    private let queue = DispatchQueue(label: "tonic.analysis", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var analyzer = Analyzer()
    private let config = OSAllocatedUnfairLock(initialState: Analyzer.Config())
    private var clients: Set<String> = []
    private var stopWork: DispatchWorkItem?
    private var bag: Set<AnyCancellable> = []
    private var configObserver: NSObjectProtocol?
    /// A recording of the microphone (Sing & Find), filled on the analysis queue.
    /// Every input channel is kept, so the take never jumps between channels (2-channel interfaces).
    private var take: (active: Bool, start: Int, position: Int, channels: [[Float]]) = (false, -1, -1, [])
    /// Every analysis frame while singing, for Sing & Find (`reading` only changes when something shows).
    let frames = PassthroughSubject<Analyzer.Output, Never>()

    private init() {
        // Anything that changes what we tune to resets per-string progress.
        prefs.$instrumentID.combineLatest(prefs.$tuningIDs, prefs.$targetMode, prefs.$customTunings)
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.lockedString = nil
                    self?.tunedStrings = []
                    self?.poly = []
                    self?.pushConfig()
                }
            }
            .store(in: &bag)
        prefs.$makamID.combineLatest(prefs.$makamRoot)
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.lockedString = nil; self?.pushConfig() } }
            .store(in: &bag)
        prefs.$a4.combineLatest(prefs.$tolerance, prefs.$gate, prefs.$inputChannel)
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.pushConfig(); self?.updateTone() } }
            .store(in: &bag)
        prefs.$inputUID.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { if self?.status == .listening { self?.restart() } }
        }.store(in: &bag)
        pushConfig()
    }

    /// Instrument strings as MIDI notes (empty outside instrument mode).
    var strings: [Int] { prefs.targetMode == .instrument ? prefs.tuning.notes : [] }

    /// Makam degrees above the karar, in semitones (empty outside makam mode).
    var makamDegrees: [Double] { prefs.targetMode == .makam ? Scales.scale(prefs.makamID).degrees : [] }

    /// Every pitch the tuner may lock onto, with the string/degree it belongs to.
    private var targetSet: (pitches: [Double], labels: [Int]) {
        if intonationActive || singing { return ([], []) }
        switch prefs.targetMode {
        case .chromatic:
            return ([], [])
        case .instrument:
            let notes = prefs.tuning.notes
            return (notes.map(Double.init), Array(notes.indices))
        case .makam:
            var p: [Double] = [], l: [Int] = []
            for octave in 1...8 {
                for (i, d) in makamDegrees.enumerated() {
                    let pitch = Double(prefs.makamRoot + 12 * octave) + d
                    if pitch >= 24 && pitch <= 108 { p.append(pitch); l.append(i) }
                }
            }
            return (p, l)
        }
    }

    private func pushConfig() {
        let t = targetSet
        let mode: Analyzer.Mode = chordListening ? .chord
            : (polyActive && !clients.contains("popover") && prefs.targetMode == .instrument ? .poly : .single)
        let c = Analyzer.Config(mode: mode, targets: t.pitches, labels: t.labels,
                                strings: prefs.tuning.notes.map(Double.init), a4: prefs.a4,
                                tolerance: prefs.tolerance, gate: prefs.gate, channel: prefs.inputChannel,
                                locked: lockedString, makam: prefs.targetMode == .makam, voice: singing)
        config.withLock { $0 = c }
    }

    // MARK: - Lifecycle

    /// Views call acquire/release as they appear and disappear; the mic runs while anyone holds it.
    func acquire(_ client: String) {
        clients.insert(client)
        stopWork?.cancel()
        pushConfig()
        if status != .listening { start() }
    }

    func release(_ client: String) {
        clients.remove(client)
        pushConfig()
        guard clients.isEmpty else { return }
        // Short grace period so flipping tabs or reopening the popover doesn't bounce the mic.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.clients.isEmpty else { return }
            self.stop()
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func start() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, !self.clients.isEmpty else { return }
                    if granted { self.startEngine() } else { self.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    private func startEngine() {
        do {
            try input.start(deviceUID: prefs.inputUID)
        } catch {
            // A device that vanished (unplugged interface) falls back to the system default.
            if prefs.inputUID != nil, (try? input.start(deviceUID: nil)) != nil {
            } else {
                status = .failed(error.localizedDescription)
                return
            }
        }
        status = .listening
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.status == .listening else { return }
            self.restart()
        }
        let sampleRate = input.sampleRate, channels = input.channelCount
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20), leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let cfg = self.config.withLock { $0 }
            let written = self.input.totalWritten
            var out = self.analyzer.tick(input: self.input, sampleRate: sampleRate, channels: channels, cfg: cfg)
            if self.take.active {
                if self.take.position < 0 { (self.take.start, self.take.position) = (written, written) }
                // Pitch belongs to the middle of the window it was measured over, so notes line up with the recording.
                out.time = Double(written - out.lag - self.take.start) / sampleRate
                let chunk = self.input.readAll(from: &self.take.position)
                if self.take.channels.count != chunk.count { self.take.channels = Array(repeating: [], count: chunk.count) }
                for c in chunk.indices { self.take.channels[c] += chunk[c] }
            }
            DispatchQueue.main.async { self.apply(out) }
        }
        timer = t
        t.resume()
    }

    private func stop() {
        timer?.cancel()
        timer = nil
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        configObserver = nil
        input.stop()
        queue.async { [analyzer] in analyzer.reset() }
        status = .idle
        referenceOn = false
        // A new session starts with a clean slate.
        tunedStrings = []
        poly = []
        reading.hasSignal = false
        reading.inTune = false
        reading.level = 0
    }

    private func restart() {
        stop()
        if !clients.isEmpty { start() }
    }

    func retry() { restart() }

    private func apply(_ out: Analyzer.Output) {
        guard status == .listening else { return }
        if let p = out.poly, p != poly { poly = p }
        if out.chordChanged { chord = out.chord }
        trace = out.trace
        let followed = reading.string != out.reading.string || reading.target != out.reading.target
        if reading != out.reading { reading = out.reading }
        if singing { frames.send(out) }
        if followed && referenceOn && lockedString == nil { updateTone() }
        guard prefs.targetMode == .instrument, !intonationActive, !singing, let s = out.reading.string, out.reading.hasSignal,
              !referenceOn, Date() > referenceQuietAt else { return }
        if out.reading.inTune {
            if !tunedStrings.contains(s) { tunedStrings.insert(s) }
        } else if abs(out.reading.cents) > prefs.tolerance + 4 && out.stable, tunedStrings.contains(s) {
            tunedStrings.remove(s)
        }
    }

    private func updateTone() {
        guard referenceOn else { return Synth.shared.setTone(nil) }
        let pitch: Double
        switch prefs.targetMode {
        case .chromatic:
            pitch = Double(reading.target ?? 69)
        case .instrument:
            let s = strings
            pitch = Double(activeString.map { s[min($0, s.count - 1)] } ?? s.first ?? 69)
        case .makam:
            // The locked degree in the octave around middle C, else the last heard degree.
            if let d = lockedString, d < makamDegrees.count {
                pitch = Double(prefs.makamRoot + 60) + makamDegrees[d]
            } else {
                pitch = reading.target == nil ? Double(prefs.makamRoot + 60) : reading.targetPitch
            }
        }
        Synth.shared.setTone(Music.frequency(midi: pitch, a4: prefs.a4))
    }

    #if SNAPSHOT
    func inject(_ r: Reading, trace: [Double?], tuned: Set<Int>, poly: [PolyString] = [], chord: DetectedChord? = nil) {
        status = .listening
        self.trace = trace
        tunedStrings = tuned
        self.poly = poly
        self.chord = chord
        reading = r
    }
    #endif

    // MARK: - Recording

    func startTake() { queue.async { self.take = (true, -1, -1, []) } }

    /// Stops recording and returns the audio (the strongest channel) with its sample rate.
    func finishTake() -> (samples: [Float], rate: Double) {
        queue.sync {
            let energy = take.channels.map { ch in ch.reduce(0) { $0 + $1 * $1 } }
            let best = energy.indices.max { energy[$0] < energy[$1] }
            let s = best.map { take.channels[$0] } ?? []
            take = (false, -1, -1, [])
            return (s, input.sampleRate)
        }
    }

    // MARK: - String selection

    func clearTuned() { tunedStrings = [] }

    func toggleLock(_ index: Int) { lockedString = lockedString == index ? nil : index }

    /// Number of selectable strings (instrument) or degrees (makam).
    var lockCount: Int { prefs.targetMode == .makam ? makamDegrees.count : strings.count }

    func stepLock(_ delta: Int) {
        let n = lockCount
        guard n > 0 else { return }
        let current = lockedString ?? reading.string ?? (delta > 0 ? -1 : n)
        lockedString = max(0, min(n - 1, current + delta))
    }

    /// The string the UI should highlight: the pinned one, else the detected one.
    var activeString: Int? { lockedString ?? reading.string }
}

/// Analysis state. Lives on the analysis queue only.
final class Analyzer {
    enum Mode { case single, poly, chord }

    struct Config {
        var mode = Mode.single
        /// Exact target pitches (MIDI, may be fractional) and the string/degree each belongs to.
        var targets: [Double] = []
        var labels: [Int] = []
        /// Open-string pitches for the all-strings view.
        var strings: [Double] = []
        var a4 = 440.0
        var tolerance = 2.0
        var gate = -60.0
        var channel = 0
        var locked: Int?
        var makam = false
        /// Singing: search only the human voice range, which avoids octave slips.
        var voice = false
    }

    struct Output {
        var reading: Reading
        var trace: [Double?]
        /// Reading has settled (several consistent frames), so it's safe to judge a string as detuned.
        var stable: Bool
        var poly: [PolyString]?
        var chord: DetectedChord?
        var chordChanged = false
        /// A pitch was measured in this very frame, not held over from an earlier one.
        var fresh = false
        /// Loudness of the newest ~40 ms, in dBFS.
        var db = -120.0
        /// Samples from the centre of the analysed window to the newest input.
        var lag = 0
        /// Seconds into the current take (Sing & Find), measured at the window centre.
        var time: Double?
    }

    private var detector: PitchDetector?
    private var buffer: [Float] = []
    private var probe = [Float](repeating: 0, count: 1024)
    private var channelEnergy: [Double] = []
    private var history: [Double] = []
    private var pending: Double?
    private var smoothed: Double?
    private var currentTarget: Int?
    private var lastTarget: Double?
    private var misses = 0
    private var inTuneTicks = 0
    private var inTune = false
    private var level = 0.0
    private var trace: [Double?] = []
    private var last = Reading()

    private var ticks = 0
    private var spectrum: Spectrum?
    private var specBuffer: [Float] = []
    private var poly: [PolyString] = []
    private var polyAge: [Int] = []
    private var chordVotes: [DetectedChord?] = []
    private var chord: DetectedChord?
    private var chordSilence = 0

    func reset() {
        history = []
        pending = nil
        smoothed = nil
        currentTarget = nil
        misses = 0
        inTuneTicks = 0
        inTune = false
        trace = []
        last = Reading()
        poly = []
        polyAge = []
        chordVotes = []
        chord = nil
    }

    func tick(input: AudioInput, sampleRate: Double, channels: Int, cfg: Config) -> Output {
        ticks += 1
        let channel = pickChannel(input: input, channels: channels, cfg: cfg)
        switch cfg.mode {
        case .single:
            return single(input: input, channel: channel, sampleRate: sampleRate, cfg: cfg)
        case .poly:
            var out = Output(reading: levelOnly(input: input, channel: channel, sampleRate: sampleRate),
                             trace: trace, stable: false)
            // Spectra every 100 ms are plenty for a strum and keep the CPU idle in between.
            if ticks % 5 == 0 { polyTick(input: input, channel: channel, sampleRate: sampleRate, cfg: cfg) }
            out.poly = poly
            return out
        case .chord:
            var out = Output(reading: levelOnly(input: input, channel: channel, sampleRate: sampleRate),
                             trace: trace, stable: false)
            if ticks % 5 == 0 {
                let before = chord
                chordTick(input: input, channel: channel, sampleRate: sampleRate, cfg: cfg)
                out.chordChanged = before != chord
            }
            out.chord = chord
            return out
        }
    }

    // MARK: Single pitch

    private func single(input: AudioInput, channel: Int, sampleRate: Double, cfg: Config) -> Output {
        let targetFreqs = cfg.targets.map { Music.frequency(midi: $0, a4: cfg.a4) }
        // Instrument mode narrows the search to its range; chromatic and makam hear everything.
        let ranged = !cfg.targets.isEmpty && !cfg.makam
        var minF = ranged ? max(20, targetFreqs.min()! * 0.7) : 26
        var maxF = ranged ? min(4200, max(targetFreqs.max()! * 2.2, 1000)) : 4200
        if cfg.voice { minF = 65; maxF = 1300 }

        // Window: ~3 periods of the lowest expected pitch, as a power of two.
        var size = 2048
        while size < 16384 && Double(size) < sampleRate / minF * 3 { size <<= 1 }
        if detector?.size != size {
            detector = PitchDetector(size: size)
            buffer = [Float](repeating: 0, count: size)
        }
        input.latest(size, channel: channel, into: &buffer)
        let db = measureLevel(buffer, sampleRate: sampleRate)

        var result: PitchDetector.Result?
        if db > cfg.gate {
            result = buffer.withUnsafeBufferPointer {
                detector!.detect($0.baseAddress!, sampleRate: sampleRate, minFrequency: minF, maxFrequency: maxF)
            }
            if let r = result, r.clarity < 0.82 { result = nil }
        }

        var reading = last
        reading.level = (level * 20).rounded() / 20
        var stable = false
        var fresh = false

        if let r = result, let m = accept(Music.midi(frequency: r.frequency, a4: cfg.a4)) {
            misses = 0
            fresh = true
            history.append(m)
            if history.count > 5 { history.removeFirst() }
            let median = history.sorted()[history.count / 2]
            stable = history.count >= 4

            let targetPitch: Double
            var label: Int? = nil
            if cfg.targets.isEmpty {
                targetPitch = median.rounded()
            } else {
                let i = closestTarget(median, cfg)
                targetPitch = cfg.targets[i]
                label = cfg.labels[i]
            }
            let raw = (median - targetPitch) * 100
            if targetPitch != lastTarget || smoothed == nil || abs(raw - smoothed!) > 35 {
                smoothed = raw
                inTuneTicks = 0
                inTune = false
            } else {
                smoothed! += 0.3 * (raw - smoothed!)
            }
            lastTarget = targetPitch
            let c = smoothed!

            // ~0.25 s inside the tolerance to lock, a cent of hysteresis to let go.
            if abs(c) <= cfg.tolerance {
                inTuneTicks += 1
                if inTuneTicks >= 12 { inTune = true }
            } else if abs(c) > cfg.tolerance + 1 {
                inTuneTicks = 0
                inTune = false
            }

            reading.hasSignal = true
            reading.frequency = Music.frequency(midi: median, a4: cfg.a4)
            reading.midi = median
            reading.target = Int(targetPitch.rounded())
            reading.targetPitch = targetPitch
            reading.string = label
            reading.cents = c
            reading.inTune = inTune
            trace.append(c)
        } else {
            misses += 1
            // Bridge brief dropouts (pick noise, bow changes) before declaring silence.
            if misses > 12 {
                reading.hasSignal = false
                reading.inTune = false
                history = []
                pending = nil
                smoothed = nil
                inTuneTicks = 0
                inTune = false
                trace.append(nil)
            } else {
                trace.append(trace.last ?? nil)
            }
        }
        if trace.count > 200 { trace.removeFirst(trace.count - 200) }
        last = reading
        var out = Output(reading: reading, trace: trace, stable: stable)
        out.fresh = fresh
        out.db = db
        out.lag = size / 2
        return out
    }

    private func measureLevel(_ buf: [Float], sampleRate: Double) -> Double {
        // Level over the newest ~40 ms only, so the gate reacts quickly to a plucked string dying out.
        let recent = min(buf.count, Int(sampleRate * 0.04))
        var sum: Float = 0
        for i in (buf.count - recent)..<buf.count { sum += buf[i] * buf[i] }
        let db = 20 * log10(max(sqrt(Double(sum) / Double(recent)), 1e-9))
        level = 0.6 * level + 0.4 * max(0, min(1, (db + 70) / 60))
        return db
    }

    private func levelOnly(input: AudioInput, channel: Int, sampleRate: Double) -> Reading {
        if buffer.count != 2048 { buffer = [Float](repeating: 0, count: 2048); detector = nil }
        input.latest(2048, channel: channel, into: &buffer)
        _ = measureLevel(buffer, sampleRate: sampleRate)
        var r = last
        r.level = (level * 20).rounded() / 20
        r.hasSignal = false
        last = r
        return r
    }

    /// Guards against octave errors and attack transients: a jump of more than half a semitone
    /// is only taken once two consecutive frames agree on it.
    private func accept(_ m: Double) -> Double? {
        guard let prev = history.last else { return m }
        if abs(m - prev) < 0.5 {
            pending = nil
            return m
        }
        if let p = pending, abs(m - p) < 0.3 {
            pending = nil
            history = []
            return m
        }
        pending = m
        return nil
    }

    private func closestTarget(_ m: Double, _ cfg: Config) -> Int {
        let pool = cfg.targets.indices.filter { cfg.locked == nil || cfg.labels[$0] == cfg.locked }
        let candidates = pool.isEmpty ? Array(cfg.targets.indices) : pool
        let best = candidates.min { abs(m - cfg.targets[$0]) < abs(m - cfg.targets[$1]) }!
        // Hysteresis keeps the current target unless another is clearly closer; makam degrees sit
        // closer together than strings, so the margin scales down with them.
        let margin = cfg.makam ? 0.25 : 0.5
        if let cur = currentTarget, candidates.contains(cur),
           abs(m - cfg.targets[cur]) - abs(m - cfg.targets[best]) < margin {
            return cur
        }
        currentTarget = best
        return best
    }

    // MARK: All strings

    private func fillSpectrum(size: Int, input: AudioInput, channel: Int, sampleRate: Double) -> Spectrum {
        if spectrum?.size != size {
            spectrum = Spectrum(size: size)
            specBuffer = [Float](repeating: 0, count: size)
        }
        input.latest(size, channel: channel, into: &specBuffer)
        specBuffer.withUnsafeBufferPointer { spectrum!.compute($0.baseAddress!, sampleRate: sampleRate) }
        return spectrum!
    }

    /// Each string is estimated from its own fundamental and harmonics, so a strum reads all at once.
    private func polyTick(input: AudioInput, channel: Int, sampleRate: Double, cfg: Config) {
        let n = cfg.strings.count
        if poly.count != n { poly = Array(repeating: PolyString(), count: n); polyAge = Array(repeating: 99, count: n) }
        var size = 16384
        while Double(size) < sampleRate * 0.6 && size < 65536 { size <<= 1 }
        let spec = fillSpectrum(size: size, input: input, channel: channel, sampleRate: sampleRate)
        let gated = level < max(0, (cfg.gate + 70) / 60)
        let floor = spec.floor(from: 50, to: 2500)

        let nominal = cfg.strings.map { Music.frequency(midi: $0, a4: cfg.a4) }
        for s in 0..<n {
            polyAge[s] += 1
            if !gated {
                let f0 = nominal[s]
                var estimates: [(f: Double, w: Double, h: Int)] = []
                for h in 1...4 {
                    // A harmonic that lands on another string's fundamental or harmonic (E2×3 ≈ B3) can't
                    // be told apart from it, so only clean harmonics back up the fundamental.
                    if h > 1, nominal.indices.contains(where: { o in
                        o != s && (1...4).contains { k in abs(1200 * log2(f0 * Double(h) / (nominal[o] * Double(k)))) < 40 }
                    }) { continue }
                    guard let p = spec.peak(near: f0 * Double(h), cents: 90), p.mag > floor * 10 else { continue }
                    estimates.append((p.hz / Double(h), Double(p.mag) * Double(h), h))
                }
                // The fundamental anchors the estimate; harmonics only count where they agree with it.
                if let anchor = estimates.first(where: { $0.h == 1 }) ?? estimates.max(by: { $0.w < $1.w }) {
                    let agree = estimates.filter { abs(1200 * log2($0.f / anchor.f)) < 8 }
                    let f = agree.reduce(0) { $0 + $1.f * $1.w } / agree.reduce(0) { $0 + $1.w }
                    let cents = 1200 * log2(f / f0)
                    let prev = poly[s].cents
                    poly[s].cents = prev.map { abs($0 - cents) < 20 ? $0 + 0.5 * (cents - $0) : cents } ?? cents
                    polyAge[s] = 0
                }
            }
            poly[s].fresh = polyAge[s] < 15
        }
    }

    // MARK: Chords

    private func chordTick(input: AudioInput, channel: Int, sampleRate: Double, cfg: Config) {
        var size = 8192
        while Double(size) < sampleRate * 0.3 { size <<= 1 }
        let spec = fillSpectrum(size: size, input: input, channel: channel, sampleRate: sampleRate)
        let loud = level > max(0, (cfg.gate + 70) / 60)
        let result = loud ? ChordRecognizer.recognize(spec, a4: cfg.a4) : nil
        let vote = result.flatMap { $0.score > 0.72 ? $0.chord : nil }
        chordVotes.append(vote)
        if chordVotes.count > 3 { chordVotes.removeFirst() }
        // Two of the last three frames must agree before the name changes.
        if let v = vote, chordVotes.filter({ $0 == v }).count >= 2 { chord = v }
    }

    /// The input channel used on the last tick.
    private(set) var channel = 0

    private func pickChannel(input: AudioInput, channels: Int, cfg: Config) -> Int {
        channel = choose(input: input, channels: channels, cfg: cfg)
        return channel
    }

    private func choose(input: AudioInput, channels: Int, cfg: Config) -> Int {
        if cfg.channel > 0 { return min(cfg.channel, channels) - 1 }
        guard channels > 1 else { return 0 }
        if channelEnergy.count != channels { channelEnergy = Array(repeating: 0, count: channels) }
        for c in 0..<channels {
            input.latest(probe.count, channel: c, into: &probe)
            var e: Float = 0
            for v in probe { e += v * v }
            channelEnergy[c] = 0.9 * channelEnergy[c] + 0.1 * Double(e)
        }
        return channelEnergy.indices.max { channelEnergy[$0] < channelEnergy[$1] }!
    }
}
