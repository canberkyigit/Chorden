import SwiftUI

struct ChordsView: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                InstrumentPicker(allowModes: false)
                Spacer()
            }
            .padding(.top, 6)
            ChordLibrary()
        }
        .padding(.horizontal, 28)
    }

    private static var cache: [String: [Chords.Voicing]] = [:]

    static func voicings(root: Int, quality: ChordQuality, instrument: Instrument, tuning: Tuning) -> [Chords.Voicing] {
        guard instrument.hasChords, !instrument.isKeyboard else { return [] }
        let key = "\(instrument.id)|\(tuning.notes)|\(root)|\(quality.id)"
        if let hit = cache[key] { return hit }
        let v = Chords.voicings(root: root, quality: quality, instrument: instrument, tuning: tuning)
        cache[key] = v
        return v
    }

    /// Plays a chord: the first shape when there is one, else the chord tones in close position.
    static func play(root: Int, quality: ChordQuality, instrument: Instrument, tuning: Tuning, a4: Double, up: Bool = false) {
        Synth.shared.strum(notes(root: root, quality: quality, instrument: instrument, tuning: tuning, a4: a4), up: up)
    }

    /// The notes a chord is played with on this instrument: its first shape, piano voicing, or close position.
    static func notes(root: Int, quality: ChordQuality, instrument: Instrument, tuning: Tuning, a4: Double) -> [Synth.Note] {
        let notes: [Synth.Note]
        if instrument.isKeyboard {
            notes = PianoVoicing.playable(root: root, quality: quality).enumerated().map { i, m in
                Synth.Note(frequency: Music.frequency(midi: Double(m), a4: a4), string: i)
            }
        } else if let v = voicings(root: root, quality: quality, instrument: instrument, tuning: tuning).first {
            notes = v.frets.enumerated().compactMap { s, f in
                f.map { Synth.Note(frequency: Music.frequency(midi: Double(tuning.notes[s] + $0), a4: a4), string: s) }
            }
        } else {
            notes = quality.intervals.enumerated().map { i, iv in
                Synth.Note(frequency: Music.frequency(midi: Double(48 + root + iv), a4: a4), string: i)
            }
        }
        return notes
    }

    static func name(_ root: Int, _ quality: String, _ notation: Notation) -> String {
        notation.name(pc: root) + quality
    }
}

// MARK: - Library

private struct ChordLibrary: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var app = AppState.shared
    @ObservedObject var tuner = TunerModel.shared
    @State private var query = ""
    @State private var listening = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        let instrument = prefs.instrument
        let tuning = prefs.tuning
        let quality = Chords.quality(prefs.chordQuality)
        let root = prefs.chordRoot
        let shapes = instrument.hasChords && !instrument.isKeyboard && prefs.chordView == .shapes
        let favorite = prefs.favoriteChords.contains(prefs.chordKey)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button { toggleListening() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: listening ? "waveform" : "mic")
                            .font(.system(size: 11, weight: .medium))
                        Text(listening ? listenText : tr("Listen"))
                            .font(.system(size: 12, weight: listening ? .semibold : .regular))
                    }
                    .foregroundStyle(listening ? Theme.good : Theme.dim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(listening ? Theme.good.opacity(0.12) : Theme.line.opacity(0.5), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tr("Play a chord and Chorden names it"))
                Button {
                    let c = Progressions.randomChord()
                    prefs.chordRoot = c.root
                    prefs.chordQuality = c.quality
                    ChordsView.play(root: c.root, quality: Chords.quality(c.quality), instrument: instrument,
                                    tuning: tuning, a4: prefs.a4)
                } label: {
                    Image(systemName: "dice")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 28, height: 26)
                        .background(Theme.line.opacity(0.5), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tr("Random chord"))
                Spacer()
                TextField(tr("Find chord  e.g. F♯m7"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(width: 170)
                    .background(Theme.line.opacity(0.5), in: Capsule())
                    .focused($searchFocused)
                    .onChange(of: query) { q in
                        if let c = Chords.parse(q) {
                            prefs.chordRoot = c.root
                            prefs.chordQuality = c.quality
                        }
                    }
                    .onSubmit { query = "" }
            }
            .padding(.top, 14)

            HStack(spacing: 0) {
                ForEach(0..<12, id: \.self) { pc in
                    TextChoice(title: prefs.notation.name(pc: pc), selected: root == pc, size: 13) { prefs.chordRoot = pc }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 14)

            FlowLayout(spacing: 2, lineSpacing: 2) {
                ForEach(Chords.qualities) { q in
                    TextChoice(title: q.symbol, selected: quality.id == q.id, size: 12) { prefs.chordQuality = q.id }
                        .help(tr(q.name))
                }
            }
            .padding(.top, 8)

            if !prefs.favoriteChords.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Theme.warn).padding(.trailing, 4)
                    ForEach(prefs.favoriteChords, id: \.self) { key in
                        let parts = key.split(separator: "|", omittingEmptySubsequences: false)
                        let r = Int(parts[0]) ?? 0, q = parts.count > 1 ? String(parts[1]) : ""
                        TextChoice(title: ChordsView.name(r, q, prefs.notation), selected: key == prefs.chordKey, size: 12) {
                            prefs.chordRoot = r
                            prefs.chordQuality = q
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.leading, 8)
            }

            Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 16)

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(ChordsView.name(root, quality.id, prefs.notation))
                    .font(.system(size: 30, weight: .semibold))
                Button { prefs.toggleFavoriteChord() } label: {
                    Image(systemName: favorite ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundStyle(favorite ? Theme.warn : Theme.ghost)
                }
                .buttonStyle(.plain)
                .help(tr("Favorite"))
                Text(tr(quality.name)).font(.system(size: 12)).foregroundStyle(Theme.dim)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(quality.intervals.map { prefs.notation.name(pc: root + $0) }.joined(separator: "  "))
                        .font(.system(size: 12, weight: .medium))
                    Text(quality.intervals.map { quality.label($0) }.joined(separator: "  "))
                        .font(.system(size: 11)).foregroundStyle(Theme.dim)
                }
            }

            HStack(spacing: 2) {
                if instrument.isKeyboard {
                    Text(tr("Inversions and voicings · click a keyboard to hear it"))
                        .font(.system(size: 11)).foregroundStyle(Theme.dim).padding(.leading, 8)
                } else if instrument.hasChords {
                    ForEach(ChordView.allCases, id: \.self) { v in
                        TextChoice(title: tr(v.rawValue.capitalized), selected: prefs.chordView == v, size: 11) { prefs.chordView = v }
                    }
                } else {
                    Text(tr("Chord tones on the fingerboard"))
                        .font(.system(size: 11)).foregroundStyle(Theme.dim).padding(.leading, 8)
                }
                Spacer()
                ForEach(DotLabel.allCases, id: \.self) { l in
                    if shapes || l != .fingers {
                        TextChoice(title: tr(l.rawValue.capitalized), selected: effectiveLabel(shapes) == l, size: 11) {
                            prefs.dotLabel = l
                        }
                    }
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, -8)

            if instrument.isKeyboard {
                PianoChordsView(root: root, quality: quality, label: effectiveLabel(false))
            } else if shapes {
                let list = ChordsView.voicings(root: root, quality: quality, instrument: instrument, tuning: tuning)
                ScrollView {
                    if list.isEmpty {
                        Text(tr("No playable shape in this tuning."))
                            .font(.system(size: 12)).foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: diagramWidth(tuning) + 12), spacing: 18)],
                              spacing: 22) {
                        ForEach(list, id: \.self) { v in
                            ChordDiagram(voicing: v, tuning: tuning, root: root, quality: quality,
                                         label: effectiveLabel(true))
                        }
                    }
                    .padding(.vertical, 20)
                }
            } else {
                let label = effectiveLabel(false)
                ScrollView {
                    NeckView(instrument: instrument, tuning: tuning,
                             marks: NeckMarks.build(tuning: tuning, frets: instrument.frets > 0 ? min(instrument.frets, 15) : 12,
                                                    fretless: instrument.frets == 0, root: root,
                                                    tones: quality.intervals.map { iv in
                                                        (Double(iv % 12), label == .notes ? prefs.notation.name(pc: root + iv) : quality.label(iv))
                                                    }))
                        .padding(.vertical, 24)
                }
            }
        }
        .onChange(of: app.searchRequest) { _ in searchFocused = true }
        .onReceive(tuner.$chord) { c in
            guard listening, let c else { return }
            prefs.chordRoot = c.root
            prefs.chordQuality = c.quality
        }
        .onDisappear { if listening { toggleListening() } }
    }

    private var listenText: String {
        guard let c = tuner.chord else { return tr("Listening…") }
        return ChordsView.name(c.root, c.quality, prefs.notation) + (c.bass.map { "/" + prefs.notation.name(pc: $0) } ?? "")
    }

    private func toggleListening() {
        listening.toggle()
        tuner.chordListening = listening
        if listening { tuner.acquire("chords") } else { tuner.release("chords") }
    }

    private func effectiveLabel(_ shapes: Bool) -> DotLabel {
        !shapes && prefs.dotLabel == .fingers ? .intervals : prefs.dotLabel
    }

    private func diagramWidth(_ t: Tuning) -> CGFloat { CGFloat(t.notes.count - 1) * 18 + 44 }
}

// MARK: - Chord box

struct ChordDiagram: View {
    let voicing: Chords.Voicing
    let tuning: Tuning
    let root: Int
    let quality: ChordQuality
    let label: DotLabel
    /// Off inside progression cards, which handle clicks themselves.
    var interactive = true
    @ObservedObject var prefs = Prefs.shared
    @State private var hover = false

    private let spacing: CGFloat = 18
    private let fretH: CGFloat = 22
    private let rows = 5

    var body: some View {
        let n = tuning.notes.count
        let width = CGFloat(n - 1) * spacing
        let base = voicing.highestFret <= rows ? 1 : voicing.lowestFret
        Canvas { ctx, size in
            let left: CGFloat = 26, top: CGFloat = 22
            let x = { (s: Int) in left + CGFloat(s) * spacing }
            let y = { (fret: Int) in top + (CGFloat(fret - base) + 0.5) * fretH }

            // Grid.
            for r in 0...rows {
                let yy = top + CGFloat(r) * fretH
                let thick = r == 0 && base == 1
                ctx.fill(Path(CGRect(x: left, y: yy - (thick ? 2 : 0.5), width: width, height: thick ? 3 : 1)),
                         with: .color(thick ? Theme.text : Theme.faint))
            }
            for s in 0..<n {
                ctx.fill(Path(CGRect(x: x(s) - 0.5, y: top, width: 1, height: CGFloat(rows) * fretH)),
                         with: .color(Theme.faint))
            }
            if base > 1 {
                ctx.draw(Text("\(base)").font(.system(size: 10, weight: .medium)).foregroundColor(Theme.dim),
                         at: CGPoint(x: left - 13, y: y(base)))
            }

            // Open / muted markers.
            for s in 0..<n {
                let p = CGPoint(x: x(s), y: top - 11)
                switch voicing.frets[s] {
                case nil:
                    ctx.draw(Text("×").font(.system(size: 11)).foregroundColor(Theme.ghost), at: p)
                case 0?:
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)),
                               with: .color(isRoot(s, 0) ? Theme.text : Theme.dim), lineWidth: 1.2)
                default: break
                }
            }

            // Barre.
            if let b = voicing.barre {
                let r = CGRect(x: x(b.from) - 8, y: y(b.fret) - 8, width: x(b.to) - x(b.from) + 16, height: 16)
                ctx.fill(Path(roundedRect: r, cornerRadius: 8), with: .color(Theme.dim.opacity(0.9)))
            }

            // Dots.
            for s in 0..<n {
                guard let f = voicing.frets[s], f > 0 else { continue }
                let c = CGPoint(x: x(s), y: y(f))
                let rootDot = isRoot(s, f)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16)),
                         with: .color(rootDot ? Theme.text : Theme.dim))
                let text = dotText(s, f)
                if !text.isEmpty {
                    ctx.draw(Text(text).font(.system(size: text.count > 2 ? 7 : 9, weight: .bold))
                        .foregroundColor(Color(nsColor: Theme.windowBG)), at: c)
                }
            }
        }
        .frame(width: width + 44, height: 22 + CGFloat(rows) * fretH + 8)
        .padding(8)
        .background(hover ? Theme.line.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { strum() }
        .help(tr("Click to play"))
        .allowsHitTesting(interactive)
    }

    private func midi(_ s: Int, _ f: Int) -> Int { tuning.notes[s] + f }
    private func isRoot(_ s: Int, _ f: Int) -> Bool { (midi(s, f) - root) % 12 == 0 }

    private func dotText(_ s: Int, _ f: Int) -> String {
        switch label {
        case .fingers: return voicing.fingers[s].map(String.init) ?? ""
        case .notes: return prefs.notation.name(pc: midi(s, f))
        case .intervals:
            let pc = ((midi(s, f) - root) % 12 + 12) % 12
            return quality.intervals.first { $0 % 12 == pc }.map { quality.label($0) } ?? ""
        }
    }

    private func strum() {
        Synth.shared.strum(voicing.frets.enumerated().compactMap { s, f in
            f.map { Synth.Note(frequency: Music.frequency(midi: Double(midi(s, $0)), a4: prefs.a4), string: s) }
        })
    }
}

