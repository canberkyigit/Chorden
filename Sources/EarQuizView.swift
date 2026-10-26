import Combine
import SwiftUI

/// Runs the quiz: asks, plays, checks and keeps score. Per-item scores are kept between launches and
/// steer the questions towards what is still being missed.
final class EarQuizModel: ObservableObject {
    static let shared = EarQuizModel()
    private let d = UserDefaults.standard
    private let prefs = Prefs.shared

    @Published var mode: EarMode {
        didSet {
            guard mode != oldValue else { return }
            d.set(mode.rawValue, forKey: "earQuiz.mode")
            reset()
        }
    }
    @Published private(set) var sets: [String: [String]]
    @Published private(set) var waySets: [String: [String]]
    @Published var autoNext: Bool { didSet { d.set(autoNext, forKey: "earQuiz.autoNext") } }
    /// Choosing which answers are in play.
    @Published var editing = false
    @Published private(set) var question: EarQuestion?
    /// The answer given to the current question.
    @Published private(set) var chosen: String?
    @Published private(set) var playing = false
    /// The item last played back for comparison after answering.
    @Published private(set) var sounding: String?
    /// This session's score per mode: right, asked, current streak.
    @Published private(set) var session: [String: [Int]] = [:]
    /// "mode.item" → [right, asked], kept between launches.
    @Published private(set) var stats: [String: [Int]]
    @Published private(set) var best: [String: Int]

    /// Sing: where the microphone is with the question on screen.
    enum Voice: Equatable {
        case idle
        /// The first note is playing; listening starts when it ends.
        case waiting
        case listening
        /// A held note was heard: its pitch (MIDI) and its distance from the nearest right answer in cents.
        case heard(midi: Double, cents: Double)
        /// Nothing steady was sung in time.
        case silent
    }
    @Published private(set) var voice = Voice.idle
    /// Sing: the pitch being sung right now (fractional MIDI).
    @Published private(set) var liveMidi: Double?
    /// Find: the note clicked as the answer, and its string on a neck (nil on a keyboard).
    @Published private(set) var tapped: (midi: Int, string: Int?)?

    private var misses: [String: Int] = [:]
    private var recent: [String] = []
    private var token = 0
    private var pending: DispatchWorkItem?
    /// Sing: the microphone is held for the whole session, so it doesn't restart between questions.
    private var micOn = false
    private var micSub: AnyCancellable?
    private var listenWork: DispatchWorkItem?
    private var silenceWork: DispatchWorkItem?
    private var heard: [Double] = []

    private init() {
        mode = EarMode(rawValue: d.string(forKey: "earQuiz.mode") ?? "") ?? .mixed
        sets = d.dictionary(forKey: "earQuiz.sets") as? [String: [String]] ?? [:]
        waySets = d.dictionary(forKey: "earQuiz.ways") as? [String: [String]] ?? [:]
        autoNext = d.object(forKey: "earQuiz.autoNext") as? Bool ?? true
        stats = d.dictionary(forKey: "earQuiz.stats") as? [String: [Int]] ?? [:]
        best = d.dictionary(forKey: "earQuiz.best") as? [String: Int] ?? [:]
    }

    // MARK: The answers in play

    /// The kind of the question on screen: the chosen tab, or in Mixed the kind just asked.
    var current: EarMode { mode == .mixed ? (question?.mode ?? .intervals) : mode }

    var allItems: [EarItem] { EarQuiz.items(current) }

    /// Answers in play, in the canonical order (number keys follow it).
    var inPlay: [String] { inPlay(current) }

    private func inPlay(_ m: EarMode) -> [String] {
        let chosen = Set(sets[m.rawValue] ?? EarQuiz.defaultSet(m))
        return EarQuiz.items(m).map(\.id).filter(chosen.contains)
    }

    var ways: [String] { ways(current) }

    private func ways(_ m: EarMode) -> [String] { waySets[m.rawValue] ?? EarQuiz.defaultWays(m) }

    /// The preset the current set matches, if any.
    var presetID: String? {
        let s = Set(inPlay)
        return EarQuiz.presets(current).first { Set($0.items) == s }?.id
    }

    func choose(_ preset: EarPreset) {
        sets[current.rawValue] = preset.items
        d.set(sets, forKey: "earQuiz.sets")
        newSet()
    }

    func toggle(_ item: String) {
        var s = inPlay
        if let i = s.firstIndex(of: item) {
            guard s.count > 2 else { return }
            s.remove(at: i)
        } else {
            s.append(item)
        }
        sets[current.rawValue] = s
        d.set(sets, forKey: "earQuiz.sets")
        newSet()
    }

    func toggleWay(_ id: String) {
        var w = ways
        if let i = w.firstIndex(of: id) {
            if EarQuiz.needsWay(current) && w.count == 1 { return }
            w.remove(at: i)
        } else {
            w.append(id)
        }
        waySets[current.rawValue] = w
        d.set(waySets, forKey: "earQuiz.ways")
        if let q = question, chosen == nil, !w.contains(q.way), q.way != "" { next() }
    }

    /// A question about an item no longer in play is replaced.
    private func newSet() {
        if let q = question, !inPlay.contains(q.item) {
            stopSound()
            question = nil
            chosen = nil
        }
    }

    // MARK: Score

    private func key(_ item: String) -> String { key(current, item) }
    private func key(_ m: EarMode, _ item: String) -> String { m.rawValue + "." + item }

    func accuracy(_ item: String) -> Int? {
        guard let s = stats[key(item)], s[1] >= 3 else { return nil }
        return Int((Double(s[0]) / Double(s[1]) * 100).rounded())
    }

    var right: Int { session[mode.rawValue]?[0] ?? 0 }
    var asked: Int { session[mode.rawValue]?[1] ?? 0 }
    var streak: Int { session[mode.rawValue]?[2] ?? 0 }
    var bestStreak: Int { best[mode.rawValue] ?? 0 }

    /// Items in play that are answered wrong most often (at least three tries, under 70 %).
    var weak: [String] {
        inPlay.compactMap { id in accuracy(id).flatMap { $0 < 70 ? (id, $0) : nil } }
            .sorted { $0.1 < $1.1 }
            .prefix(2)
            .map(\.0)
    }

    func resetSession() {
        session[mode.rawValue] = nil
        misses = [:]
    }

    func forgetScores() {
        if mode == .mixed {
            stats = [:]
            best = [:]
        }
        for id in allItems.map(\.id) { stats[key(id)] = nil }
        best[mode.rawValue] = nil
        d.set(stats, forKey: "earQuiz.stats")
        d.set(best, forKey: "earQuiz.best")
        resetSession()
    }

    // MARK: Flow

    var answered: Bool { chosen != nil }

    func isCorrect(_ item: String) -> Bool {
        guard let q = question else { return false }
        return EarQuiz.sameSound(q.mode, item, q.item)
    }

    /// Space: the first question, or the current one again.
    func space() {
        if editing { editing = false }
        if question == nil { next() } else { replay() }
    }

    /// Return: the next question once this one is answered.
    func advance() {
        if editing { editing = false; return }
        if question == nil || answered { next() }
    }

    func replay() {
        guard let q = question else { return }
        sounding = nil
        // Sing: before answering, the first note again and another try; afterwards, the right answer.
        if q.mode == .sing && answered { return play(EarQuiz.answerEvents(q)) }
        ask(q)
    }

    func next() {
        pending?.cancel()
        pending = nil
        var rng = SystemRandomNumberGenerator()
        var m = mode
        if mode == .mixed {
            // A different kind more often than not, so the questions keep changing.
            let kinds = EarMode.mixable.map { k in (k.mode, k.weight * (k.mode == question?.mode ? 0.35 : 1)) }
            var pick = Double.random(in: 0..<kinds.reduce(0) { $0 + $1.1 }, using: &rng)
            m = kinds.last!.0
            for (k, w) in kinds {
                if pick < w { m = k; break }
                pick -= w
            }
        }
        let prefix = m.rawValue + "."
        let pool = inPlay(m)
        let stat = Dictionary(uniqueKeysWithValues: pool.map { id -> (String, (Int, Int)) in
            let s = stats[key(m, id)] ?? [0, 0]
            return (id, (s[0], s[1]))
        })
        let missed = Dictionary(uniqueKeysWithValues: misses.filter { $0.key.hasPrefix(prefix) }
            .map { (String($0.key.dropFirst(prefix.count)), $0.value) })
        let lately = recent.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        var q = EarQuiz.makeQuestion(mode: m, set: pool, ways: ways(m),
                                     register: EarQuiz.register(prefs.instrument, prefs.tuning),
                                     stats: stat, misses: missed, recent: lately, random: &rng)
        if m == .find, q.way == "string", !prefs.instrument.isKeyboard {
            q.string = prefs.tuning.notes.indices.randomElement(using: &rng)
        }
        recent = Array((recent + [key(m, q.item)]).suffix(8))
        question = q
        chosen = nil
        sounding = nil
        tapped = nil
        ask(q)
    }

    /// Plays the question; Sing then listens for the answer.
    private func ask(_ q: EarQuestion) {
        let events = EarQuiz.events(q, item: q.item)
        play(events)
        guard q.mode == .sing else { return }
        stopListening()
        voice = .waiting
        let work = DispatchWorkItem { [weak self] in self?.listen() }
        listenWork = work
        let end = events.map { $0.at + $0.hold }.max() ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + end + 0.25, execute: work)
    }

    /// The tuner or instrument changed: a Find question may name a string that isn't there any more.
    func instrumentChanged() {
        stop()
        if current == .find && question != nil { next() }
    }

    /// Keys that answer, in order: 1–9, 0, then − and = (all twelve notes).
    static let keys = Array("1234567890-=")

    /// Answers by the number key's place among the answers in play.
    func answer(index: Int) {
        guard !editing, question != nil, current.answersByButton else { return }
        let s = inPlay
        guard s.indices.contains(index) else { return }
        answer(s[index])
    }

    /// The first answer counts; after that every answer just plays, to compare with the right one.
    func answer(_ item: String) {
        guard let q = question else { return next() }
        if answered {
            pending?.cancel()
            pending = nil
            sounding = item
            play(EarQuiz.events(q, item: item))
            return
        }
        record(item, right: isCorrect(item))
    }

    /// Scores the first answer to the question on screen.
    private func record(_ item: String, right: Bool) {
        guard let q = question else { return }
        chosen = item
        var s = session[mode.rawValue] ?? [0, 0, 0]
        s[1] += 1
        if right { s[0] += 1; s[2] += 1 } else { s[2] = 0 }
        session[mode.rawValue] = s
        if s[2] > bestStreak {
            best[mode.rawValue] = s[2]
            d.set(best, forKey: "earQuiz.best")
        }
        var st = stats[key(q.mode, q.item)] ?? [0, 0]
        st[1] += 1
        if right { st[0] += 1 }
        stats[key(q.mode, q.item)] = st
        d.set(stats, forKey: "earQuiz.stats")
        if right {
            misses[key(q.mode, q.item)] = max(0, (misses[key(q.mode, q.item)] ?? 0) - 1)
            if autoNext {
                let work = DispatchWorkItem { [weak self] in self?.next() }
                pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
            }
        } else {
            misses[key(q.mode, q.item), default: 0] += 2
            if q.mode.answersByButton { misses[key(q.mode, item), default: 0] += 1 }
        }
    }

    // MARK: Find

    /// Find: a place on the neck (its note and string) or a key was clicked. The first click answers;
    /// later ones just sound, to explore.
    func tap(midi: Int, string: Int?) {
        Synth.shared.strum([Synth.Note(frequency: Music.frequency(midi: Double(midi), a4: prefs.a4), string: string)])
        guard let q = question, q.mode == .find, !answered else { return }
        pending?.cancel()
        tapped = (midi, string)
        let pc = ((midi % 12) + 12) % 12
        let right = pc == q.root && (q.string == nil || q.string == string)
        record(right ? q.item : "\(pc)", right: right)
    }

    // MARK: Sing

    private func listen() {
        guard let q = question, q.mode == .sing, !answered else { return }
        // The question's last note must not be heard as the answer.
        Synth.shared.silence()
        if !micOn {
            micOn = true
            let tuner = TunerModel.shared
            tuner.singing = true
            tuner.acquire("earquiz")
            micSub = tuner.frames.sink { [weak self] in self?.hear($0) }
        }
        heard = []
        liveMidi = nil
        voice = .listening
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.voice == .listening else { return }
            self.voice = .silent
            self.liveMidi = nil
        }
        silenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 9, execute: work)
    }

    private func hear(_ f: Analyzer.Output) {
        guard voice == .listening else { return }
        guard f.reading.hasSignal else {
            heard = []
            liveMidi = nil
            return
        }
        guard f.fresh else { return }
        let m = f.reading.midi
        liveMidi = m
        // A different note (a slide into the pitch, a new attempt) starts the count again.
        if let last = heard.last, abs(m - last) > 0.8 { heard = [] }
        heard.append(m)
        // Held for about 0.4 s: that's the answer, read from its steady end.
        guard heard.count >= 20 else { return }
        judge(heard.suffix(12).sorted()[6])
    }

    /// Any octave of the asked note counts (low and high voices alike), but not the first note itself:
    /// an octave must really move.
    private func judge(_ sung: Double) {
        guard let q = question else { return }
        silenceWork?.cancel()
        let answers = (-3...3).map { Double(q.target + 12 * $0) }.filter { abs($0 - Double(q.root)) > 0.5 }
        let nearest = answers.min { abs($0 - sung) < abs($1 - sung) } ?? Double(q.target)
        let cents = (sung - nearest) * 100
        voice = .heard(midi: sung, cents: cents)
        liveMidi = nil
        let right = abs(cents) <= 50
        record(right ? q.item : "", right: right)
    }

    /// Stops listening for an answer; the microphone itself stays on until the session ends.
    private func stopListening() {
        listenWork?.cancel()
        listenWork = nil
        silenceWork?.cancel()
        silenceWork = nil
        if voice == .listening || voice == .waiting { voice = .idle }
        liveMidi = nil
    }

    #if SNAPSHOT
    /// Test hooks: the Sing question on screen answered as if `midi` were sung, or shown while listening.
    func injectSung(_ midi: Double) { judge(midi) }

    func injectListening(_ midi: Double?) {
        stopListening()
        voice = .listening
        liveMidi = midi
    }
    #endif

    private func releaseMic() {
        guard micOn else { return }
        micOn = false
        micSub = nil
        TunerModel.shared.singing = false
        TunerModel.shared.release("earquiz")
    }

    // MARK: Sound

    private func play(_ events: [EarEvent]) {
        stopSound()
        let synth = Synth.shared
        synth.prepare()
        let sr = synth.outputSampleRate
        let start = synth.now + UInt64(0.06 * sr)
        let a4 = prefs.a4
        for e in events {
            let notes = e.midis.enumerated().map { i, m in
                Synth.Note(frequency: Music.frequency(midi: m, a4: a4), string: e.strings.indices.contains(i) ? e.strings[i] : nil)
            }
            synth.schedule(strum: notes, at: start + UInt64((e.at * sr).rounded()), up: false, velocity: 0.8, hold: e.hold)
        }
        token += 1
        let t = token
        playing = true
        let length = (events.map { $0.at + ($0.midis.count > 1 ? 1.4 : 0.6) }.max() ?? 0) + 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + length) { [weak self] in
            guard let self, self.token == t else { return }
            self.playing = false
        }
    }

    private func stopSound() {
        token += 1
        if playing {
            Synth.shared.cancelScheduled()
            Synth.shared.silence()
        }
        playing = false
    }

    /// Leaving the tab or closing the window: quiet, and no question pops up later.
    func stop() {
        pending?.cancel()
        pending = nil
        stopSound()
        sounding = nil
        stopListening()
        releaseMic()
    }

    private func reset() {
        stop()
        editing = false
        question = nil
        chosen = nil
        tapped = nil
        voice = .idle
        recent = []
    }

    // MARK: Names

    func title(_ item: String) -> String {
        if current == .notes || current == .find { return prefs.notation.name(pc: Int(item) ?? 0) }
        let name = tr(allItems.first { $0.id == item }?.name ?? item)
        // Chord names are lower case in the chord library ("minor 7th").
        guard current == .chords, let first = name.first else { return name }
        return String(first).uppercased(with: Locale(identifier: prefs.language == .tr ? "tr" : "en")) + name.dropFirst()
    }

    /// The notes of the question, spelled: "C – E♭", "Cm7 · C E♭ G B♭", "G Rast · G A B♭¹ C D E F♯⁴".
    func spelled(_ q: EarQuestion) -> String {
        let n = prefs.notation
        switch q.mode {
        case .intervals:
            let s = EarQuiz.spelling(.intervals, q.item, root: q.root, n)
            switch q.way {
            case "down": return s[1] + " → " + s[0]
            case "together": return s[0] + " + " + s[1]
            default: return s[0] + " → " + s[1]
            }
        case .chords:
            let s = EarQuiz.spelling(.chords, q.item, root: q.root, n)
            return s[0] + q.item + "  ·  " + s.joined(separator: " ")
        case .scales:
            let scale = Scales.scale(q.item)
            let pc = ((q.root % 12) + 12) % 12
            return scale.degrees.indices.map { Scales.degreeLabel(scale, $0, root: pc, n) }.joined(separator: " ")
        case .notes:
            return n.name(pc: q.root) + "\(q.root / 12 - 1)"
        case .sing:
            // Spelled from the lower of the two notes, read in the order they are sung.
            if q.way == "down" {
                let s = EarQuiz.spelling(.intervals, q.item, root: q.target, n)
                return s[1] + " → " + s[0]
            }
            let s = EarQuiz.spelling(.intervals, q.item, root: q.root, n)
            return s[0] + " → " + s[1]
        case .find:
            return n.name(pc: q.root)
        case .mixed:
            return ""
        }
    }
}

// MARK: - View

struct EarQuizView: View {
    @ObservedObject var model = EarQuizModel.shared
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var tuner = TunerModel.shared

    var body: some View {
        let mode = model.mode
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                ForEach(EarMode.allCases, id: \.self) { m in
                    TextChoice(title: tr(m.title), selected: mode == m, size: 12) { model.mode = m }
                }
                Spacer()
                instrumentMenu
            }
            .padding(.top, 6)
            .padding(.horizontal, -8)

            if mode == .mixed {
                HStack(spacing: 6) {
                    Text(tr("Intervals, chords, scales and notes, all mixed, from each kind's set."))
                        .font(.system(size: 11)).foregroundStyle(Theme.dim)
                    Spacer()
                    if let q = model.question {
                        Text(tr(q.mode.title)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.line.opacity(0.6), in: Capsule())
                    }
                }
                .padding(.top, 12)
            } else {
            HStack(spacing: 2) {
                ForEach(EarQuiz.presets(mode)) { p in
                    TextChoice(title: tr(p.id), selected: !model.editing && model.presetID == p.id, size: 11) {
                        model.choose(p)
                    }
                }
                TextChoice(title: tr("Custom"), selected: model.editing || model.presetID == nil, size: 11) {
                    model.editing.toggle()
                }
                .help(tr("Choose which answers are in play"))
                Spacer()
                // A keyboard has no strings to name.
                ForEach(EarQuiz.ways(mode).filter { _ in mode != .find || !prefs.instrument.isKeyboard }) { w in
                    TextChoice(title: mode == .notes ? trf(w.name, prefs.notation.name(pc: 0)) : tr(w.name),
                               selected: model.ways.contains(w.id), size: 11) { model.toggleWay(w.id) }
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, -8)
            }

            Spacer(minLength: 12)
            prompt
            Group {
                if model.editing || model.current.answersByButton {
                    answers
                } else if model.current == .sing {
                    SingPanel(model: model, tuner: tuner)
                } else {
                    findBoard
                }
            }
            .padding(.top, 26)
            Spacer(minLength: 12)
            Rectangle().fill(Theme.line).frame(height: 1)
            footer
                .padding(.vertical, 12)
        }
        .padding(.horizontal, 28)
        .onChange(of: prefs.instrumentID) { _ in model.instrumentChanged() }
        .onChange(of: prefs.tuning) { _ in model.instrumentChanged() }
        // Leaving the tab stops the sound.
        .onDisappear { model.stop() }
    }

    // MARK: Parts

    private var instrumentMenu: some View {
        Dropdown {
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2").font(.system(size: 11))
                Text(tr(prefs.instrument.name)).font(.system(size: 12))
            }
            .foregroundStyle(Theme.dim)
        } content: {
            HStack(alignment: .top, spacing: 6) {
                column(["Guitar", "Bass", "Bowed"])
                column(["Keyboard", "Folk", "Turkish & Middle Eastern"])
            }
        }
        .help(tr("Instrument"))
    }

    private func column(_ groups: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups.filter { g in Catalog.all.contains { $0.group == g } }, id: \.self) { group in
                DropdownHeader(title: tr(group))
                ForEach(Catalog.all.filter { $0.group == group }) { inst in
                    DropdownItem(title: tr(inst.name), selected: prefs.instrumentID == inst.id) {
                        prefs.instrumentID = inst.id
                    }
                }
            }
        }
        .frame(width: 210)
    }

    private var prompt: some View {
        HStack(spacing: 22) {
            Button { model.space() } label: {
                Group {
                    // Find shows the note to look for; Sing shows when it's listening.
                    if model.current == .find, let q = model.question {
                        Text(prefs.notation.name(pc: q.root)).font(.system(size: 26, weight: .semibold))
                    } else if model.voice == .listening {
                        Image(systemName: "mic.fill").font(.system(size: 24))
                    } else {
                        Image(systemName: model.playing && model.sounding == nil ? "speaker.wave.2.fill" : "play.fill")
                            .font(.system(size: 22))
                    }
                }
                .foregroundStyle(Color(nsColor: Theme.windowBG))
                .frame(width: 72, height: 72)
                .background(Circle().fill(model.voice == .listening ? Theme.good : Theme.text))
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(tr("Play the question again (Space)"))

            VStack(alignment: .leading, spacing: 5) {
                headline
                detail
            }
            Spacer(minLength: 8)
            if model.editing {
                capsule(tr("Done")) { model.editing = false }
            } else if model.answered {
                capsule(tr("Next"), key: "return") { model.next() }
                    .help(tr("Next question (Return)"))
            }
        }
        .frame(height: 76)
    }

    @ViewBuilder private var headline: some View {
        let font = Font.system(size: 22, weight: .light)
        if model.editing {
            Text(tr("Choose what to practise")).font(font)
        } else if let q = model.question, !q.mode.answersByButton {
            // Sing and Find keep the task in view; a mark shows how it went.
            HStack(spacing: 8) {
                if let c = model.chosen {
                    Image(systemName: model.isCorrect(c) ? "checkmark" : "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(model.isCorrect(c) ? Theme.good : Theme.off)
                }
                Text(task(q)).font(font).lineLimit(1).minimumScaleFactor(0.7)
            }
        } else if let q = model.question, let c = model.chosen {
            HStack(spacing: 8) {
                // Right: a check. Wrong: just the answer; the red line below says what was chosen.
                if model.isCorrect(c) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.good)
                }
                Text(model.title(q.item)).font(font)
            }
        } else {
            Text(tr(model.current.prompt)).font(font)
        }
    }

    @ViewBuilder private var detail: some View {
        let small = Font.system(size: 12)
        if model.editing {
            Text(tr("Click answers to include or leave them out.")).font(small).foregroundStyle(Theme.dim)
        } else if let q = model.question, q.mode == .sing {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.answered ? model.spelled(q) : trf("From %@ · any octave counts", prefs.notation.name(midi: q.root)))
                    .font(small).foregroundStyle(Theme.dim)
                Text(model.answered ? (model.isCorrect(model.chosen ?? "") && model.autoNext ? tr("Next one in a moment.")
                                                                                           : tr("▶ plays the right answer."))
                                    : tr("▶ plays the first note again."))
                    .font(.system(size: 11)).foregroundStyle(Theme.ghost)
            }
        } else if let q = model.question, q.mode == .find {
            Text(findDetail(q)).font(small).foregroundStyle(model.answered && !model.isCorrect(model.chosen ?? "") ? Theme.off : Theme.dim)
        } else if let q = model.question, let c = model.chosen {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    if c != q.item {
                        Text(model.isCorrect(c) ? trf("%@ sounds almost the same", model.title(c)) : trf("Not %@", model.title(c)))
                            .foregroundStyle(model.isCorrect(c) ? Theme.dim : Theme.off)
                        Text("  ·  ").foregroundStyle(Theme.ghost)
                    }
                    Text(model.spelled(q)).foregroundStyle(Theme.dim)
                }
                .font(small)
                .lineLimit(1)
                Text(model.isCorrect(c) && model.autoNext ? tr("Next one in a moment.") : tr("Click any answer to hear it."))
                    .font(.system(size: 11)).foregroundStyle(Theme.ghost)
            }
        } else if model.question == nil {
            Text(tr("Press Space or ▶ to hear the first one.")).font(small).foregroundStyle(Theme.dim)
        } else {
            Text(tr("Space plays it again · number keys answer")).font(small).foregroundStyle(Theme.ghost)
        }
    }

    /// Sing and Find: what to do, in words.
    private func task(_ q: EarQuestion) -> String {
        let n = prefs.notation
        switch q.mode {
        case .sing:
            return trf(q.way == "down" ? "Sing down: %@" : "Sing up: %@", model.title(q.item))
        case .find:
            let note = n.name(pc: q.root)
            let tuning = prefs.tuning
            if let s = q.string, s < tuning.notes.count {
                // Strings are numbered from the highest, as players count them.
                return trf("Find %@ on string %d (%@)", note, tuning.notes.count - s, n.name(pc: tuning.notes[s]))
            }
            return trf(prefs.instrument.isKeyboard ? "Find %@ on the keyboard" : "Find %@ on the neck", note)
        default:
            return ""
        }
    }

    private func findDetail(_ q: EarQuestion) -> String {
        guard let c = model.chosen, let t = model.tapped else {
            return tr(prefs.instrument.isKeyboard ? "Click a key to answer." : "Click the neck to answer.")
        }
        if model.isCorrect(c) {
            return model.autoNext ? tr("Every place it's found is marked. Next one in a moment.")
                                  : tr("Every place it's found is marked.")
        }
        let pc = ((t.midi % 12) + 12) % 12
        if pc == q.root { return tr("Right note, but on another string.") }
        return trf("That was %@.", prefs.notation.name(pc: pc))
    }

    /// Find: the neck (or keyboard) to answer on; once answered, every right place is marked.
    @ViewBuilder private var findBoard: some View {
        let instrument = prefs.instrument
        let tuning = prefs.tuning
        let q = model.question
        let shown = model.answered ? q : nil
        if instrument.isKeyboard {
            let low = 48, high = 72
            let marks = Dictionary(uniqueKeysWithValues: (low...high).filter { m in
                shown.map { ((m % 12) + 12) % 12 == $0.root } ?? false
            }.map { ($0, KeyMark(label: prefs.notation.name(pc: $0), root: true)) })
            KeyboardView(low: low, high: high, marks: marks.merging(wrongKey) { a, _ in a }, height: 130) { m in
                model.tap(midi: m, string: nil)
            }
        } else {
            let fretless = instrument.frets == 0
            let right = shown.map { q in
                NeckMarks.build(tuning: tuning, frets: fretless ? 12 : min(instrument.frets, 15), fretless: fretless,
                                root: q.root, tones: [(0, prefs.notation.name(pc: q.root))])
                    .filter { q.string == nil || $0.string == q.string }
            } ?? []
            NeckView(instrument: instrument, tuning: tuning, marks: right + wrongNeck(tuning),
                     onTap: { s, f in model.tap(midi: tuning.notes[s] + f, string: s) },
                     rowH: 30, highlight: q?.string.flatMap { $0 < tuning.notes.count ? $0 : nil })
        }
    }

    /// The clicked place when it was wrong, named, so it's clear what was played.
    private func wrongNeck(_ tuning: Tuning) -> [NeckMark] {
        guard let c = model.chosen, !model.isCorrect(c), let t = model.tapped, let s = t.string, s < tuning.notes.count
        else { return [] }
        return [NeckMark(string: s, position: Double(t.midi - tuning.notes[s]), label: prefs.notation.name(pc: t.midi),
                         root: false, approx: false, midi: Double(t.midi))]
    }

    private var wrongKey: [Int: KeyMark] {
        guard let c = model.chosen, !model.isCorrect(c), let t = model.tapped else { return [:] }
        return [t.midi: KeyMark(label: prefs.notation.name(pc: t.midi), root: false)]
    }

    private var answers: some View {
        let editing = model.editing
        let inPlay = model.inPlay
        let shown = editing ? model.allItems.map(\.id) : inPlay
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], spacing: 8) {
            ForEach(Array(shown.enumerated()), id: \.element) { i, id in
                AnswerButton(key: editing || i >= EarQuizModel.keys.count ? nil : String(EarQuizModel.keys[i]),
                             title: model.title(id),
                             state: state(id, editing: editing, included: inPlay.contains(id)),
                             accuracy: editing ? nil : model.accuracy(id)) {
                    if editing { model.toggle(id) } else { model.answer(id) }
                }
            }
        }
    }

    private func state(_ id: String, editing: Bool, included: Bool) -> AnswerButton.Look {
        if editing { return included ? .included : .excluded }
        guard let q = model.question, let c = model.chosen else { return .idle }
        if id == q.item { return .right }
        if id == c { return model.isCorrect(c) ? .right : .wrong }
        return model.sounding == id ? .sounding : .after
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            stat("\(model.streak)", tr("streak"))
            stat("\(model.bestStreak)", tr("best"))
            stat(model.asked > 0 ? "\(Int((Double(model.right) / Double(model.asked) * 100).rounded()))%" : "–",
                 trf("%d of %d", model.right, model.asked))
            Spacer(minLength: 8)
            let weak = model.weak
            if !weak.isEmpty {
                Text(tr("Practise more:") + " " + weak.map(model.title).joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .help(tr("Missed most often; these come up more"))
            }
            Dropdown(chevron: false) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 18, height: 14)
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    DropdownItem(title: tr("Next question automatically"), detail: tr("after a right answer"),
                                 selected: model.autoNext) { model.autoNext.toggle() }
                    Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 8)
                    DropdownItem(title: tr("New session"), selected: false) { model.resetSession() }
                    DropdownItem(title: tr("Forget scores"), detail: tr(model.mode.title), selected: false) { model.forgetScores() }
                }
                .frame(minWidth: 260)
            }
            .padding(.trailing, -8)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
        .fixedSize()
    }

    private func capsule(_ title: String, key: String? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let key { Image(systemName: key).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.dim) }
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(Theme.line.opacity(0.6), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// One answer: its number key, its name and, once there are a few tries, how often it is heard right.
private struct AnswerButton: View {
    enum Look { case idle, right, wrong, after, sounding, included, excluded }

    let key: String?
    let title: String
    let look: Look
    let accuracy: Int?
    let action: () -> Void
    @State private var hover = false

    init(key: String?, title: String, state: Look, accuracy: Int?, action: @escaping () -> Void) {
        self.key = key
        self.title = title
        self.look = state
        self.accuracy = accuracy
        self.action = action
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Button(action: action) {
            HStack(spacing: 8) {
                if let key {
                    Text(key)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.ghost)
                        .frame(width: 8)
                }
                Text(title)
                    .font(.system(size: 13, weight: look == .right || look == .wrong ? .semibold : .medium))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                trailing
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .overlay(alignment: .bottom) { meter }
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(stroke, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(accuracy.map { trf("Right %d%% of the time", $0) } ?? "")
        .animation(.easeOut(duration: 0.15), value: look)
    }

    @ViewBuilder private var trailing: some View {
        switch look {
        case .right: Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.good)
        case .wrong: Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.off)
        case .sounding: Image(systemName: "speaker.wave.2.fill").font(.system(size: 9)).foregroundStyle(Theme.dim)
        case .included: Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.good)
        case .excluded: EmptyView()
        case .idle, .after: EmptyView()
        }
    }

    /// How often this one is heard right: a hairline along the bottom, amber while it's weak.
    @ViewBuilder private var meter: some View {
        if let accuracy, look == .idle || look == .after {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line.opacity(0.6))
                    Capsule().fill(accuracy < 60 ? Theme.warn.opacity(0.8) : Theme.dim.opacity(0.45))
                        .frame(width: max(2, g.size.width * Double(accuracy) / 100))
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 12)
            .padding(.bottom, 5)
        }
    }

    private var foreground: Color {
        switch look {
        case .right: return Theme.good
        case .wrong: return Theme.off
        case .after, .excluded: return Theme.dim
        default: return Theme.text
        }
    }

    private var fill: Color {
        switch look {
        case .right: return Theme.good.opacity(0.12)
        case .wrong: return Theme.off.opacity(0.10)
        case .excluded: return .clear
        default: return hover ? Theme.surface.opacity(0.6) : Theme.surface
        }
    }

    private var stroke: Color {
        switch look {
        case .right: return Theme.good.opacity(0.65)
        case .wrong: return Theme.off.opacity(0.55)
        case .excluded: return Theme.line.opacity(0.7)
        default: return hover ? Theme.faint : Theme.line
        }
    }
}

/// Sing: the note being sung while listening; afterwards, how far it was from the right one.
private struct SingPanel: View {
    @ObservedObject var model: EarQuizModel
    @ObservedObject var tuner: TunerModel
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(spacing: 14) {
            if tuner.status == .denied && model.voice != .idle {
                Text(tr("Chorden needs microphone access to hear you."))
                    .font(.system(size: 13)).foregroundStyle(Theme.dim)
                Button(tr("Open Privacy Settings")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
            } else {
                meter.frame(height: 62)
                Text(status).font(.system(size: 13, weight: .medium)).foregroundStyle(statusColor)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }

    @ViewBuilder private var meter: some View {
        switch model.voice {
        case .heard(let midi, let cents):
            CentsMeter(cents: cents,
                       label: abs(cents) <= 50 ? String(format: "%+.0f ¢", cents) : prefs.notation.name(midi: Int(midi.rounded())))
        case .listening:
            // What the microphone hears right now, so it's clear it's working.
            Text(model.liveMidi.map { prefs.notation.name(midi: Int($0.rounded())) } ?? "…")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(model.liveMidi == nil ? Theme.ghost : Theme.text)
        default:
            Image(systemName: "waveform").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.ghost)
        }
    }

    private var status: String {
        switch model.voice {
        case .idle: return model.question == nil ? tr("Press Space or ▶ to hear the first one.") : ""
        case .waiting: return tr("Listen to the first note…")
        case .listening: return tr("Now sing the note and hold it")
        case .silent: return tr("No steady note heard. ▶ tries again.")
        case .heard(let midi, let cents):
            guard let q = model.question else { return "" }
            if abs(cents) <= 15 { return tr("In tune") }
            if abs(cents) <= 50 { return tr(cents < 0 ? "Right note, a little flat" : "Right note, a little sharp") }
            let semis = abs(Int((midi - Double(q.root)).rounded()))
            let name = EarQuiz.intervalNames[semis > 0 && semis % 12 == 0 ? 12 : semis % 12]
            return trf("You sang %@ (%@)", prefs.notation.name(midi: Int(midi.rounded())), tr(name))
        }
    }

    private var statusColor: Color {
        guard case .heard(_, let cents) = model.voice else { return Theme.dim }
        return CentsMeter.color(cents)
    }
}

/// How far a sung note was from the right one: the in-tune band in the middle, the right-note band around it.
private struct CentsMeter: View {
    let cents: Double
    let label: String
    private let width: CGFloat = 320

    static func color(_ cents: Double) -> Color { abs(cents) <= 15 ? Theme.good : abs(cents) <= 50 ? Theme.warn : Theme.off }

    var body: some View {
        let c = max(-100, min(100, cents))
        VStack(spacing: 6) {
            Text(label).font(.system(size: 26, weight: .light).monospacedDigit()).foregroundStyle(Self.color(cents))
            // A wrong note is just named: off the scale, a dot at the edge would only say "very sharp".
            if abs(cents) <= 50 { scale(c) }
        }
    }

    private func scale(_ c: Double) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line.opacity(0.6)).frame(width: width, height: 4)
                Capsule().fill(Theme.good.opacity(0.16)).frame(width: width * 0.5, height: 10).offset(x: width * 0.25)
                Capsule().fill(Theme.good.opacity(0.4)).frame(width: width * 0.15, height: 10).offset(x: width * 0.425)
                Rectangle().fill(Theme.dim).frame(width: 1, height: 16).offset(x: width / 2 - 0.5)
                Circle().fill(Self.color(cents)).frame(width: 14, height: 14).offset(x: width * (c + 100) / 200 - 7)
            }
            .frame(width: width, height: 16)
            HStack {
                Text("♭")
                Spacer()
                Text("♯")
            }
            .font(.system(size: 11)).foregroundStyle(Theme.ghost).frame(width: width)
        }
    }
}
