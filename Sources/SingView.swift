import SwiftUI
import UniformTypeIdentifiers

/// Sing a melody; Chorden follows the pitch and the beat, finds the key and suggests a chord for every bar.
struct SingView: View {
    @ObservedObject var model = SingModel.shared
    @ObservedObject var tuner = TunerModel.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                KeyMenu()
                    .padding(.leading, -8)
                Spacer()
                ChordMenu()
                Rectangle().fill(Theme.line).frame(width: 1, height: 14).padding(.horizontal, 6)
                // These work any time, also while the take plays back.
                TextChoice(title: tr("My voice"), selected: prefs.singPlayVoice, size: 11) { prefs.singPlayVoice.toggle() }
                    .help(tr("Play your recorded voice with the chords (V)"))
                TextChoice(title: tr("Melody"), selected: prefs.singPlayMelody, size: 11) { prefs.singPlayMelody.toggle() }
                    .help(tr("Play your melody on the chosen instrument (M)"))
                TextChoice(title: trf("Click · %d BPM", Int(prefs.bpm)), selected: prefs.singClick, size: 11) {
                    prefs.singClick.toggle()
                }
                .help(tr("Sing with the metronome: a one-bar count-in, and its tempo sets the bars"))
            }
            .padding(.top, 6)
            .padding(.trailing, -8)

            HStack(spacing: 22) {
                Button { model.toggle() } label: {
                    ZStack {
                        Circle().fill(model.recording || model.countIn != nil ? Theme.off : Theme.text)
                        if let n = model.countIn {
                            Text("\(n)")
                                .font(.system(size: 30, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color(nsColor: Theme.windowBG))
                        } else {
                            Image(systemName: model.recording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Color(nsColor: Theme.windowBG))
                        }
                    }
                    .frame(width: 72, height: 72)
                    .shadow(color: model.recording ? Theme.off.opacity(0.45) : .clear, radius: 12)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(tr("Sing (Space)"))

                VStack(alignment: .leading, spacing: 4) {
                    Text(status).font(.system(size: 18, weight: .light))
                    Text(model.recording ? liveNote : tr("Hum or sing a few bars; chords appear as you go."))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                if !model.slots.isEmpty && !model.recording {
                    Button { model.play() } label: {
                        Image(systemName: model.playing == nil ? "play.fill" : "stop.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text)
                            .frame(width: 34, height: 30)
                            .background(Theme.line.opacity(0.6), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(tr("Play the chords"))

                    TextChoice(title: tr("Clear"), selected: false, size: 12) { model.clear() }
                }
            }
            .padding(.top, 18)

            MelodyStrip(notes: model.notes, trace: model.trace, now: model.elapsed, grid: model.grid, bounds: model.bounds,
                        shift: model.shift, beatsPerBar: prefs.beatsPerBar, tuning: model.tuning, recording: model.recording)
                .frame(minHeight: 84, maxHeight: 140)
                .padding(.top, 18)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(model.slots.indices, id: \.self) { i in
                            SlotCard(slot: model.slots[i], index: i, active: model.playing == i
                                     || (model.recording && i == model.slots.count - 1))
                                .id(i)
                        }
                    }
                    .padding(.vertical, 14)
                }
                .onChange(of: model.slots.count) { n in
                    if n > 0 { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(n - 1, anchor: .trailing) } }
                }
            }
            Spacer(minLength: 0)
            if !model.slots.isEmpty && !model.recording {
                TakeBar()
                    .padding(.bottom, 16)
            }
        }
        .padding(.horizontal, 28)
        .onDisappear { model.stop(); model.stopPlayback() }
    }

    private var status: String {
        if model.countIn != nil { return tr("Get ready…") }
        if model.recording { return tr("Listening — sing a melody") }
        return model.notes.isEmpty ? tr("Press and sing") : tr("Done")
    }

    private var liveNote: String {
        let r = tuner.reading
        guard r.hasSignal else { return "–" }
        return prefs.notation.name(midi: Int(r.midi.rounded())) + "   " + centsText((r.midi - r.midi.rounded()) * 100)
    }
}

/// The key, with the likeliest others to pick from when the found one sounds off.
private struct KeyMenu: View {
    @ObservedObject var model = SingModel.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        Dropdown {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                if model.keyChoice != nil {
                    Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(Theme.dim)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                DropdownItem(title: tr("Found from your singing"), detail: model.foundKey.map { name(model.shifted($0)) },
                             selected: model.keyChoice == nil) { model.chooseKey(nil) }
                DropdownHeader(title: tr("Other keys"))
                ForEach(Array(model.keyOptions.enumerated()), id: \.offset) { _, k in
                    DropdownItem(title: name(model.shifted(k)), selected: k.same(model.keyChoice)) { model.chooseKey(k) }
                }
            }
            .frame(minWidth: 250)
        }
        .disabled(model.keyOptions.isEmpty)
        .help(tr("Pick another key if this one sounds off"))
    }

    private var title: String {
        guard let k = model.shiftedKey else { return tr("Key: —") }
        let text = trf("Key: %@", name(k))
        return model.keyChoice == nil ? text + String(format: "  ·  %d%%", Int(k.confidence * 100)) : text
    }

    private func name(_ k: SongKey) -> String {
        prefs.notation.name(pc: k.root) + " " + (k.minor ? tr("minor") : tr("major"))
    }
}

/// How often the chord changes, and which chords may be used.
private struct ChordMenu: View {
    @ObservedObject var prefs = Prefs.shared
    private static let styles = [("Simple", "I · IV · V · vi"), ("Full", "every chord in the key"),
                                 ("Rich", "with 7ths, 9ths and 6ths")]

    var body: some View {
        Dropdown {
            Text(tr(prefs.singChordEvery == 2 ? "Every half bar" : "Every bar") + " · "
                 + tr(Self.styles[min(max(prefs.singChords, 0), 2)].0))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.text)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                DropdownHeader(title: tr("Chord changes"))
                DropdownItem(title: tr("Every bar"), selected: prefs.singChordEvery != 2) { prefs.singChordEvery = 1 }
                DropdownItem(title: tr("Every half bar"), selected: prefs.singChordEvery == 2) { prefs.singChordEvery = 2 }
                DropdownHeader(title: tr("Chords"))
                ForEach(Self.styles.indices, id: \.self) { i in
                    DropdownItem(title: tr(Self.styles[i].0), detail: tr(Self.styles[i].1), selected: prefs.singChords == i) {
                        prefs.singChords = i
                    }
                }
            }
            .frame(minWidth: 290)
        }
        .help(tr("How often the chord changes, and which chords to use"))
    }
}

/// After a take: tempo, pickup, transposition and capo, and the ways to take the chords further.
private struct TakeBar: View {
    @ObservedObject var model = SingModel.shared
    @ObservedObject var prefs = Prefs.shared
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                label("Tempo")
                step("minus") { model.nudgeTempo(-1) }
                Dropdown(chevron: false) {
                    Text("\(Int((model.tempo ?? prefs.bpm).rounded())) BPM")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.text)
                        .frame(width: 54)
                } content: {
                    // A beat finder's usual slip is half or double the tempo: one click fixes it.
                    let bpm = (model.tempo ?? prefs.bpm).rounded()
                    VStack(alignment: .leading, spacing: 0) {
                        if !prefs.singClick {
                            DropdownItem(title: tr("Found from your singing"), selected: !model.tempoIsSet) { model.setTempo(nil) }
                        }
                        DropdownItem(title: tr("Half time"), detail: "\(Int((bpm / 2).rounded())) BPM", selected: false) { model.setTempo(bpm / 2) }
                        DropdownItem(title: tr("Double time"), detail: "\(Int(bpm * 2)) BPM", selected: false) { model.setTempo(bpm * 2) }
                    }
                    .frame(minWidth: 230)
                }
                .help(prefs.singClick ? "" : tr("Found from your singing; the bars follow you where you slow down or rush"))
                step("plus") { model.nudgeTempo(1) }
                divider
                label("Pickup")
                step("chevron.left") { model.nudgeShift(-1) }
                Text(model.shift == 0 ? tr("none") : trf("%d beat", model.shift))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .frame(width: 52)
                step("chevron.right") { model.nudgeShift(1) }
                    .help(tr("For songs that start before the first bar: move bar 1 to the first strong beat"))
                divider
                label("Transpose")
                step("minus") { model.setTranspose(model.transpose - 1) }
                Text(model.transpose == 0 ? "0" : String(format: "%+d", model.transpose))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .frame(width: 28)
                step("plus") { model.setTranspose(model.transpose + 1) }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if let capo = model.capoSuggestion {
                    Text(trf("Guitar: capo %d, then play %@", capo.capo, capo.shapes.prefix(6).joined(separator: " ")))
                        .font(.system(size: 11)).foregroundStyle(Theme.dim)
                        .lineLimit(1)
                } else if model.transpose != 0 && prefs.singPlayVoice {
                    Text(tr("Your recorded voice sits out while the chords are transposed."))
                        .font(.system(size: 11)).foregroundStyle(Theme.ghost)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                action("repeat", tr("Loop it")) { model.sendToProgressions() }
                    .help(tr("Loop these chords in Progressions with a rhythm and drums"))
                action(copied ? "checkmark" : "doc.on.doc", tr("Copy")) {
                    model.copyChart()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
                .help(tr("Copy the chord chart"))
                action("square.and.arrow.down", "MIDI") { exportMIDI() }
                    .help(tr("Save melody and chords as a MIDI file; its tempo follows your singing"))
            }
        }
        .padding(12)
        .background(Theme.line.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(width: 1, height: 14).padding(.horizontal, 6)
    }

    private func label(_ s: String) -> some View {
        Text(tr(s)).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.dim)
    }

    private func exportMIDI() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.midi]
        let key = model.shiftedKey.map { prefs.notation.name(pc: $0.root) + ($0.minor ? "m" : "") } ?? "Song"
        panel.nameFieldStringValue = "Chorden – \(key).mid"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? model.midiData().write(to: url)
    }

    private func step(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(Circle().strokeBorder(Theme.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.dim)
    }

    private func action(_ icon: String, _ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Theme.line.opacity(0.6), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Piano-roll of the sung melody: notes as bars, the live pitch as a line, chord changes as columns on
/// the beat the singer kept (bar lines stronger than half bars), and the beats as small ticks.
private struct MelodyStrip: View {
    let notes: [SungNote]
    let trace: [(t: Double, m: Double)]
    let now: Double
    let grid: BeatGrid
    let bounds: [Double]
    let shift: Int
    let beatsPerBar: Int
    /// The singer's own tuning; the pitch line is drawn against it, so it sits on the note bars.
    let tuning: Double
    let recording: Bool
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        Canvas { ctx, size in
            let end = max(now, notes.last?.end ?? 0, recording ? 0 : (bounds.last ?? 0), 4)
            // Follow the singer: the last ~16 s while recording, the whole take afterwards.
            let window = recording ? min(end, 16) : end
            let t0 = end - window
            let pitches = notes.map { Double($0.midi) } + trace.suffix(200).map { $0.m - tuning }
            let lo = (pitches.min() ?? 57) - 2, hi = max((pitches.max() ?? 69) + 2, lo + 10)
            let x = { (t: Double) in CGFloat((t - t0) / window) * size.width }
            let y = { (m: Double) in size.height - CGFloat((m - lo) / (hi - lo)) * size.height }

            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 12), with: .color(Theme.line.opacity(0.22)))
            for b in grid.beats where b >= t0 && b <= end {
                ctx.fill(Path(CGRect(x: x(b) - 0.5, y: size.height - 5, width: 1, height: 3)), with: .color(Theme.ghost.opacity(0.6)))
            }
            let perBar = Double(max(1, beatsPerBar))
            for t in bounds where t >= t0 && t <= end {
                let p = grid.position(t) - Double(shift)
                let downbeat = abs(p - (p / perBar).rounded() * perBar) < 0.05
                ctx.fill(Path(CGRect(x: x(t), y: 0, width: 1, height: size.height)),
                         with: .color(Theme.line.opacity(downbeat ? 1 : 0.45)))
            }
            for n in notes where n.end >= t0 {
                let r = CGRect(x: x(max(n.start, t0)), y: y(Double(n.midi)) - 5, width: max(3, x(n.end) - x(max(n.start, t0))), height: 10)
                ctx.fill(Path(roundedRect: r, cornerRadius: 5), with: .color(Theme.text.opacity(0.85)))
                if r.width > 22 {
                    ctx.draw(Text(prefs.notation.name(pc: n.midi)).font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color(nsColor: Theme.windowBG)), at: CGPoint(x: r.midX, y: r.midY))
                }
            }
            var path = Path()
            var last: Double?
            for p in trace where p.t >= t0 {
                let pt = CGPoint(x: x(p.t), y: y(p.m - tuning))
                if let l = last, p.t - l < 0.12 { path.addLine(to: pt) } else { path.move(to: pt) }
                last = p.t
            }
            ctx.stroke(path, with: .color(Theme.good.opacity(0.8)), lineWidth: 1.4)
            if recording {
                ctx.fill(Path(CGRect(x: x(now) - 0.5, y: 0, width: 1.5, height: size.height)), with: .color(Theme.off.opacity(0.7)))
            }
        }
    }
}

private struct SlotCard: View {
    let slot: ChordSlot
    let index: Int
    let active: Bool
    @ObservedObject var model = SingModel.shared
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var app = AppState.shared

    var body: some View {
        let c = model.shifted(slot.chord)
        VStack(spacing: 6) {
            Text(model.pickup ? (index == 0 ? tr("pickup") : "\(index)") : "\(index + 1)")
                .font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.ghost)
            Text(ChordsView.name(c.root, c.quality, prefs.notation))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(slot.held ? Theme.ghost : Theme.text)
            Text(c.numeral).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.dim)
            if !slot.held && slot.options.count > 1 {
                HStack(spacing: 2) {
                    ForEach(slot.options.indices.filter { $0 != slot.chosen }, id: \.self) { o in
                        let alt = model.shifted(slot.options[o])
                        Button { model.choose(o, in: index) } label: {
                            Text(ChordsView.name(alt.root, alt.quality, prefs.notation))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Theme.dim)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.line.opacity(0.6), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(tr("Use this chord instead"))
                    }
                }
            }
        }
        .frame(minWidth: 92)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(active ? Theme.good.opacity(0.12) : Theme.line.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(active ? Theme.good.opacity(0.6) : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // The chord's shapes in the library, for the chosen instrument.
            prefs.chordRoot = c.root
            prefs.chordQuality = c.quality
            app.tab = .chords
        }
        .onTapGesture {
            ChordsView.play(root: c.root, quality: Chords.quality(c.quality), instrument: prefs.instrument,
                            tuning: prefs.tuning, a4: prefs.a4)
        }
        .help(tr("Click to play · double-click to open in the library"))
    }
}
