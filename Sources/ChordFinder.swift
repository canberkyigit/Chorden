import SwiftUI

/// Reverse chord finder: the notes picked on the neck or keyboard. Kept across tab switches, never saved.
final class ChordFinderModel: ObservableObject {
    static let shared = ChordFinderModel()
    @Published var active = false
    /// Fret per string (nil = muted), in tuning order. Kept when only the tuning changes, so a
    /// shape can be re-read in Drop D; reset when the string count differs.
    @Published var frets: [Int?] = []
    /// Piano keys (MIDI).
    @Published var keys: Set<Int> = []

    func frets(for tuning: Tuning) -> [Int?] {
        frets.count == tuning.notes.count ? frets : Array(repeating: nil, count: tuning.notes.count)
    }

    /// Sounding notes in playing order (strings bass side first, keys low to high).
    func notes(_ instrument: Instrument, _ tuning: Tuning) -> [(midi: Int, string: Int?)] {
        if instrument.isKeyboard { return keys.sorted().map { ($0, nil) } }
        return frets(for: tuning).enumerated().compactMap { s, f in f.map { (tuning.notes[s] + $0, s) } }
    }

    /// Sets a string's note, or mutes it when the same fret is tapped again.
    func tap(string s: Int, fret f: Int, tuning: Tuning, a4: Double) {
        var fs = frets(for: tuning)
        guard s < fs.count else { return }
        if fs[s] == f {
            fs[s] = nil
        } else {
            fs[s] = f
            Synth.shared.strum([Synth.Note(frequency: Music.frequency(midi: Double(tuning.notes[s] + f), a4: a4), string: s)])
        }
        frets = fs
    }

    func tap(key m: Int, a4: Double) {
        if keys.remove(m) == nil {
            keys.insert(m)
            Synth.shared.strum([Synth.Note(frequency: Music.frequency(midi: Double(m), a4: a4))])
        }
    }

    func clear() {
        frets = []
        keys = []
    }
}

/// What a set of notes is called: the best name, its readings, and the tones to show.
struct ChordReading {
    let midis: [Int]
    let matches: [Chords.Match]

    /// `bassMatters` is off for re-entrant tunings (ukulele, banjo), whose lowest note isn't a bass.
    init(midis: [Int], bassMatters: Bool = true) {
        self.midis = midis.sorted()
        let pcs = Set(self.midis.map { $0 % 12 })
        var seen = Set<String>()
        // Same name twice (e.g. a quality whose tones overlap): keep the cheaper reading.
        matches = Chords.identify(pcs, bass: bassMatters ? self.midis.first.map { $0 % 12 } : nil)
            .filter { seen.insert("\($0.root)|\($0.quality)|\($0.bass ?? -1)").inserted }
    }

    var pcs: [Int] {
        var seen = Set<Int>()
        return midis.map { $0 % 12 }.filter { seen.insert($0).inserted }
    }
    var bass: Int? { midis.first.map { $0 % 12 } }
    var best: Chords.Match? { matches.first }

    /// A dyad reads as its interval, unless it is a power chord on its root.
    var headlineIsChord: Bool {
        guard let b = best else { return false }
        return pcs.count >= 3 || (b.quality == "5" && b.bass == nil)
    }

    static func name(_ m: Chords.Match, _ n: Notation) -> String {
        var s = ChordsView.name(m.root, m.quality, n)
        if let b = m.bass { s += "/" + n.name(pc: b) }
        if !m.extra.isEmpty { s += "(" + m.extra.map { Chords.addedLabel($0 - m.root) }.joined(separator: ",") + ")" }
        return s
    }

    /// Interval label of a pitch class inside the best reading, or above the bass.
    func label(_ pc: Int) -> String {
        if let m = best, headlineIsChord {
            let q = Chords.quality(m.quality)
            if let iv = q.intervals.first(where: { (m.root + $0) % 12 == pc }) { return q.label(iv) }
            return Chords.addedLabel(pc - m.root)
        }
        let d = ((pc - (bass ?? pc)) % 12 + 12) % 12
        return Chords.quality("").label(d)
    }

    func isRoot(_ pc: Int) -> Bool {
        if let m = best, headlineIsChord { return pc == m.root }
        return pc == bass
    }
}

/// The finder panel under the Chords tab's top row: result, other names, and the instrument to tap on.
struct ChordFinderView: View {
    let instrument: Instrument
    let tuning: Tuning
    let label: DotLabel
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var finder = ChordFinderModel.shared
    @State private var sounding = false
    @State private var token = 0

    private static let pianoLow = 36, pianoHigh = 84

    var body: some View {
        let notes = finder.notes(instrument, tuning)
        let reading = ChordReading(midis: notes.map(\.midi), bassMatters: instrument.pitchOrdered)

        VStack(alignment: .leading, spacing: 0) {
            header(reading)
                .frame(height: 42, alignment: .leading)
                .padding(.top, 18)

            alternatives(reading)
                .frame(height: 26, alignment: .leading)
                .padding(.top, 8)
                .padding(.horizontal, -8)

            HStack(spacing: 2) {
                Text(instrument.isKeyboard ? tr("Click keys to add or remove notes")
                                           : tr("Click a fret to set a string · again to mute"))
                    .font(.system(size: 11)).foregroundStyle(Theme.dim).padding(.leading, 8)
                    .lineLimit(1)
                Spacer(minLength: 8)
                ForEach([DotLabel.notes, .intervals], id: \.self) { l in
                    TextChoice(title: tr(l.rawValue.capitalized), selected: label == l, size: 11) { prefs.dotLabel = l }
                }
                Button { strum(notes) } label: {
                    Image(systemName: "play.fill").font(.system(size: 10))
                        .foregroundStyle(notes.isEmpty ? Theme.ghost : Theme.text)
                        .frame(width: 30, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(notes.isEmpty)
                .help(tr("Play"))
                .padding(.leading, 6)
                TextChoice(title: tr("Clear"), selected: false, size: 11) { finder.clear() }
                    .disabled(notes.isEmpty)
                    .opacity(notes.isEmpty ? 0.5 : 1)
            }
            .padding(.top, 14)
            .padding(.horizontal, -8)

            if instrument.isKeyboard {
                KeyboardView(low: Self.pianoLow, high: Self.pianoHigh, marks: keyMarks(reading),
                             active: sounding ? Set(reading.midis) : [], height: 150) { m in
                    finder.tap(key: m, a4: prefs.a4)
                }
                .padding(.top, 22)
            } else {
                let frets = finder.frets(for: tuning)
                NeckView(instrument: instrument, tuning: tuning, marks: neckMarks(frets, reading),
                         muted: Set(frets.indices.filter { frets[$0] == nil }),
                         onTap: { s, f in finder.tap(string: s, fret: f, tuning: tuning, a4: prefs.a4) },
                         rowH: frets.count >= 7 ? 28 : 32)
                .padding(.top, 26)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Result

    @ViewBuilder
    private func header(_ r: ChordReading) -> some View {
        let n = prefs.notation
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if r.midis.isEmpty {
                Text(tr("Pick some notes")).font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.ghost)
                Spacer()
            } else {
                Text(title(r)).font(.system(size: 30, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.6)
                if r.headlineIsChord, let m = r.best {
                    Button { open(m) } label: {
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.ghost)
                    }
                    .buttonStyle(.plain)
                    .help(tr("Open in chord view"))
                }
                Text(subtitle(r)).font(.system(size: 12)).foregroundStyle(Theme.dim).lineLimit(1)
                Spacer(minLength: 8)
                let list = tones(r)
                VStack(alignment: .trailing, spacing: 3) {
                    list.enumerated().reduce(Text("")) { acc, e in
                        acc + Text(e.offset == 0 ? "" : "  ")
                            + Text(n.name(pc: e.element.pc)).foregroundColor(e.element.present ? Theme.text : Theme.ghost)
                    }
                    .font(.system(size: 12, weight: .medium))
                    Text(list.map(\.label).joined(separator: "  "))
                        .font(.system(size: 11)).foregroundStyle(Theme.dim)
                }
                .fixedSize()
            }
        }
    }

    private func title(_ r: ChordReading) -> String {
        let n = prefs.notation
        if r.pcs.count == 1 { return n.name(pc: r.pcs[0]) }
        if r.headlineIsChord, let m = r.best { return ChordReading.name(m, n) }
        if r.pcs.count == 2 { return r.pcs.map { n.name(pc: $0) }.joined(separator: " + ") }
        return r.pcs.map { n.name(pc: $0) }.joined(separator: " ")
    }

    private func subtitle(_ r: ChordReading) -> String {
        if r.pcs.count == 1 {
            return r.midis.count > 1 ? tr("Octave") : prefs.notation.name(midi: r.midis[0])
        }
        if r.pcs.count == 2 {
            let lo = r.midis[0], hi = r.midis.first { $0 % 12 != lo % 12 } ?? lo
            let interval = tr(EarQuiz.intervalNames[(hi - lo) % 12])
            if r.headlineIsChord, let m = r.best { return tr(Chords.quality(m.quality).name) + " · " + interval }
            return interval
        }
        guard let m = r.best else { return tr("No common name") }
        let q = Chords.quality(m.quality)
        var parts = [tr(q.name)]
        if let b = m.bass, let iv = q.intervals.first(where: { (m.root + $0) % 12 == b }) {
            switch iv % 12 {
            case 3, 4: parts.append(tr("1st inversion"))
            case 6, 7, 8: parts.append(tr("2nd inversion"))
            case 9 where q.id == "dim7": parts.append(tr("3rd inversion"))
            case 10, 11: parts.append(tr("3rd inversion"))
            default: parts.append(trf("%@ in the bass", q.label(iv)))
            }
        }
        if m.rootless { parts.append(tr("rootless")) }
        return parts.joined(separator: " · ")
    }

    /// The tones shown on the right: the best chord's tones (left-out ones ghosted) plus any foreign note.
    private func tones(_ r: ChordReading) -> [(pc: Int, label: String, present: Bool)] {
        let played = Set(r.pcs)
        if let m = r.best, r.headlineIsChord {
            let q = Chords.quality(m.quality)
            var seen = Set<Int>()
            let chord = q.intervals.filter { seen.insert($0 % 12).inserted }
                .map { (pc: (m.root + $0) % 12, label: q.label($0), present: played.contains((m.root + $0) % 12)) }
            return chord + m.extra.map { (pc: $0, label: r.label($0), present: true) }
        }
        return r.pcs.map { (pc: $0, label: r.label($0), present: true) }
    }

    @ViewBuilder
    private func alternatives(_ r: ChordReading) -> some View {
        let shown = r.headlineIsChord ? Array(r.matches.dropFirst()) : r.matches
        let alts = Array(shown.prefix(4))
        HStack(spacing: 2) {
            if !alts.isEmpty {
                Text(r.headlineIsChord ? tr("or") : tr("could be"))
                    .font(.system(size: 11)).foregroundStyle(Theme.ghost)
                    .padding(.leading, 8).padding(.trailing, 4)
                ForEach(alts, id: \.self) { m in
                    TextChoice(title: ChordReading.name(m, prefs.notation), selected: false, size: 12) { open(m) }
                        .help(tr(Chords.quality(m.quality).name) + (m.rootless ? " · " + tr("rootless") : "")
                              + " · " + tr("Open in chord view"))
                }
            }
        }
    }

    // MARK: Marks

    private func dotLabel(_ midi: Int, _ r: ChordReading) -> String {
        label == .intervals && r.pcs.count >= 2 ? r.label(midi % 12) : prefs.notation.name(pc: midi)
    }

    private func neckMarks(_ frets: [Int?], _ r: ChordReading) -> [NeckMark] {
        frets.enumerated().compactMap { s, f in
            guard let f, s < tuning.notes.count else { return nil }
            let midi = tuning.notes[s] + f
            return NeckMark(string: s, position: Double(f), label: dotLabel(midi, r), root: r.isRoot(midi % 12),
                            approx: false, midi: Double(midi))
        }
    }

    private func keyMarks(_ r: ChordReading) -> [Int: KeyMark] {
        Dictionary(uniqueKeysWithValues: r.midis.map { ($0, KeyMark(label: dotLabel($0, r), root: r.isRoot($0 % 12))) })
    }

    // MARK: Actions

    private func open(_ m: Chords.Match) {
        prefs.chordRoot = m.root
        prefs.chordQuality = m.quality
        finder.active = false
    }

    private func strum(_ notes: [(midi: Int, string: Int?)]) {
        guard !notes.isEmpty else { return }
        Synth.shared.strum(notes.enumerated().map { i, n in
            Synth.Note(frequency: Music.frequency(midi: Double(n.midi), a4: prefs.a4), string: n.string ?? i)
        })
        guard instrument.isKeyboard else { return }
        sounding = true
        token += 1
        let t = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if token == t { sounding = false } }
    }
}
