import SwiftUI

struct ProgressionsView: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var player = ProgressionPlayer.shared
    @ObservedObject var app = AppState.shared
    @ObservedObject var library = Library.shared

    var body: some View {
        let instrument = prefs.instrument
        let tuning = prefs.tuning
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                InstrumentPicker(allowModes: false, onlyRecorded: true)
                Spacer()
                SavedProgressionsMenu()
                    .padding(.trailing, -8)
            }
            .padding(.top, 6)

            // Wraps on narrow windows instead of widening the page.
            FlowLayout(spacing: 2, lineSpacing: 2) {
                TextChoice(title: tr("Any mood"), selected: prefs.progressionMood.isEmpty, size: 12) {
                    prefs.progressionMood = ""
                    player.generate()
                }
                ForEach(Progressions.moods, id: \.self) { m in
                    TextChoice(title: tr(m), selected: prefs.progressionMood == m, size: 12) {
                        prefs.progressionMood = m
                        player.generate()
                    }
                }
            }
            .padding(.top, 14)
            .padding(.leading, -8)

            if let p = player.progression {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(prefs.notation.name(pc: p.key) + " " + (p.minor ? tr("minor") : tr("major")))
                        .font(.system(size: 30, weight: .semibold))
                    Text(p.steps.map { Progressions.numeral(offset: $0.offset, quality: $0.quality, minor: p.minor) }.joined(separator: " – "))
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(tr(p.mood)).font(.system(size: 12)).foregroundStyle(Theme.ghost)
                    Spacer()
                    Button { player.toggle() } label: {
                        Image(systemName: player.playing ? "stop.fill" : "play.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(nsColor: Theme.windowBG))
                            .frame(width: 44, height: 34)
                            .background(player.playing ? Theme.good : Theme.text, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(tr("Play / stop the loop (Space)"))
                    Dropdown(chevron: false) {
                        // Narrow windows keep just the icon.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) {
                                Image(systemName: "circle.circle").font(.system(size: 12))
                                Text(tr("Circle of fifths")).font(.system(size: 12, weight: .medium)).fixedSize()
                            }
                            .padding(.horizontal, 12)
                            Image(systemName: "circle.circle").font(.system(size: 12)).frame(width: 34)
                        }
                        .foregroundStyle(Theme.text)
                        .frame(height: 34)
                        .background(Theme.line.opacity(0.6), in: Capsule())
                    } content: { CircleOfFifthsView() }
                    .padding(.horizontal, -8)
                    .help(tr("The key's chords and its neighbours on the circle of fifths"))
                    saveButton(p)
                    Button { player.generate() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "dice").font(.system(size: 12))
                            Text(tr("New")).font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Theme.line.opacity(0.6), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(tr("New progression"))
                }
                .padding(.top, 22)

                // Up to six cards in a row, then two rows; everything shrinks together to fit the space.
                GeometryReader { geo in
                    let count = p.steps.count
                    let perRow = count <= 6 ? count : Int((Double(count) / 2).rounded(.up))
                    let rows = Int((Double(count) / Double(perRow)).rounded(.up))
                    let cardWidth = instrument.isKeyboard ? 190 : CGFloat(tuning.notes.count - 1) * 18 + 44 + 16 + 28
                    let cardHeight: CGFloat = instrument.isKeyboard ? 240 : 255
                    let canAdd = count < Progressions.lengths.upperBound
                    let lastRow = count - (rows - 1) * perRow
                    let naturalW = max(CGFloat(perRow) * cardWidth + CGFloat(perRow - 1) * 16,
                                       CGFloat(lastRow) * cardWidth + CGFloat(lastRow - 1) * 16 + (canAdd ? 16 + 44 : 0))
                    let naturalH = CGFloat(rows) * cardHeight + CGFloat(rows - 1) * 16
                    let scale = min(1, geo.size.width / naturalW, (geo.size.height - 24) / naturalH)
                    VStack(spacing: 16) {
                        ForEach(0..<rows, id: \.self) { r in
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(Array(r * perRow..<min(count, (r + 1) * perRow)), id: \.self) { i in
                                    card(p, i, instrument: instrument, tuning: tuning).frame(width: cardWidth)
                                }
                                if r == rows - 1 && canAdd {
                                    AddChordTile { player.appendChord() }.frame(width: 44, height: cardHeight)
                                }
                            }
                        }
                    }
                    .frame(width: naturalW)
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: geo.size.width, alignment: .top)
                    .padding(.top, 20)
                }
            }

            LoopControls()
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 28)
        // Leaving the tab stops the loop.
        .onDisappear { player.stop() }
        .onAppear {
            // Instruments without real recordings aren't offered here; fall back to the acoustic guitar.
            if Timbre.of(prefs.instrumentID).samples == nil { prefs.instrumentID = "guitar6" }
            if player.progression == nil { player.generate() }
        }
    }
}

extension ProgressionsView {
    /// Keeps the progression with its tempo and rhythm; filled once it's kept as it is now.
    func saveButton(_ p: Progression) -> some View {
        let kept = library.saved(p).map { $0.sameSettings(prefs) } ?? false
        return Button { library.save(p) } label: {
            Image(systemName: kept ? "bookmark.fill" : "bookmark")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .frame(width: 34, height: 34)
                .background(Theme.line.opacity(0.6), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(kept ? tr("Saved") : tr("Save this progression with its tempo and rhythm"))
    }

    @ViewBuilder
    func card(_ p: Progression, _ i: Int, instrument: Instrument, tuning: Tuning) -> some View {
        let root = p.root(i)
        let q = Chords.quality(p.steps[i].quality)
        ProgressionCard(index: i, name: ChordsView.name(root, q.id, prefs.notation),
                        numeral: Progressions.numeral(offset: p.steps[i].offset, quality: q.id, minor: p.minor),
                        canRemove: p.steps.count > Progressions.lengths.lowerBound,
                        voicing: ChordsView.voicings(root: root, quality: q, instrument: instrument, tuning: tuning).first,
                        tuning: tuning, root: root, quality: q, keyboard: instrument.isKeyboard,
                        active: player.chord == i,
                        beats: player.beatsPerChord, beat: player.chord == i ? player.beat : nil) {
            ChordsView.play(root: root, quality: q, instrument: instrument, tuning: tuning, a4: prefs.a4)
        } open: {
            prefs.chordRoot = root
            prefs.chordQuality = q.id
            app.tab = .chords
        } remove: {
            player.removeChord(at: i)
        }
    }
}

/// Tempo, chord length, strumming pattern, drums, swing and loop.
private struct LoopControls: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var player = ProgressionPlayer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                label("Number of chords")
                HStack(spacing: 8) {
                    let count = player.progression?.steps.count ?? prefs.progressionLength
                    step("minus") { player.removeChord(at: count - 1) }
                        .opacity(count > Progressions.lengths.lowerBound ? 1 : 0.35)
                    Text(trf("%d chords", count))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .frame(width: 64)
                    step("plus") { player.appendChord() }
                        .opacity(count < Progressions.lengths.upperBound ? 1 : 0.35)
                }
            }
            GridRow {
                label("Tempo")
                HStack(spacing: 8) {
                    step("minus") { prefs.progressionBPM = max(40, prefs.progressionBPM - 1) }
                    Text("\(Int(prefs.progressionBPM)) BPM")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .frame(width: 64)
                    step("plus") { prefs.progressionBPM = min(220, prefs.progressionBPM + 1) }
                    Slider(value: $prefs.progressionBPM, in: 40...220)
                        .tint(Theme.dim)
                        .frame(width: 150)
                        .onChange(of: prefs.progressionBPM) { v in if v != v.rounded() { prefs.progressionBPM = v.rounded() } }
                }
            }
            GridRow {
                label("Chord length")
                HStack(spacing: 2) {
                    ForEach([(2, "½ bar"), (4, "1 bar"), (8, "2 bars")], id: \.0) { b in
                        TextChoice(title: tr(b.1), selected: prefs.progressionBeats == b.0, size: 11) {
                            prefs.progressionBeats = b.0
                            player.restart()
                        }
                    }
                }
            }
        }
        // Rhythm, drums and the band as quiet menus, so the chord cards keep their room.
        let auto = player.autoStyles
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                menuLabel("Rhythm").frame(width: 110, alignment: .trailing)
                menu(StrumPattern.allCases.map { ($0.rawValue, $0.name, nil) }, selected: prefs.progressionPattern) {
                    prefs.progressionPattern = $0
                }
                menuLabel("Drums").padding(.leading, 10)
                menu(DrumPattern.allCases.map { ($0.rawValue, $0.name, nil) }, selected: prefs.progressionDrums) {
                    prefs.progressionDrums = $0
                }
                HStack(spacing: 2) {
                    Spacer(minLength: 10)
                    TextChoice(title: tr("Swing"), selected: prefs.progressionSwing, size: 11) { prefs.progressionSwing.toggle() }
                    TextChoice(title: tr("Loop"), selected: prefs.progressionLoop, size: 11) { prefs.progressionLoop.toggle() }
                }
            }
            GridRow {
                menuLabel("Bass").gridColumnAlignment(.trailing)
                menu(BassStyle.allCases.map { ($0.rawValue, $0.name, $0 == .auto ? tr(auto.bass.name) : nil) },
                     selected: prefs.progressionBass) {
                    prefs.progressionBass = $0
                    player.preloadBand()
                }
                menuLabel("Keys").padding(.leading, 10)
                menu(KeysStyle.allCases.map { ($0.rawValue, $0.name, $0 == .auto ? tr(auto.keys.name) : nil) },
                     selected: prefs.progressionKeys) {
                    prefs.progressionKeys = $0
                    player.preloadBand()
                }
            }
        }
        .padding(.top, 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.line.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func menuLabel(_ s: String) -> some View {
        Text(tr(s)).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.dim)
    }

    /// A quiet dropdown of named choices; `detail` shows greyed beside an item (what Auto is playing).
    private func menu(_ items: [(id: String, name: String, detail: String?)], selected: String,
                      pick: @escaping (String) -> Void) -> some View {
        Dropdown {
            Text(tr(items.first { $0.id == selected }?.name ?? items.first?.name ?? ""))
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items, id: \.id) { item in
                    DropdownItem(title: tr(item.name), detail: item.detail, selected: selected == item.id) { pick(item.id) }
                }
            }
            .frame(minWidth: 200)
        }
    }

    private func label(_ s: String) -> some View {
        Text(tr(s)).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.dim).gridColumnAlignment(.trailing)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(tr(title)).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.dim)
                .frame(width: 110, alignment: .trailing)
            FlowLayout(spacing: 2, lineSpacing: 2) { content() }
        }
    }

    private func step(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(Circle().strokeBorder(Theme.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.dim)
    }
}

private struct ProgressionCard: View {
    let index: Int
    let name: String
    let numeral: String
    let canRemove: Bool
    let voicing: Chords.Voicing?
    let tuning: Tuning
    let root: Int
    let quality: ChordQuality
    var keyboard = false
    let active: Bool
    let beats: Int
    let beat: Int?
    let play: () -> Void
    let open: () -> Void
    let remove: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(spacing: 6) {
            // A quiet dropdown on the name: pick another chord for this card.
            Dropdown(chevron: false) {
                Text(name).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.text)
                    .overlay(alignment: .trailing) {
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.ghost).offset(x: 14).opacity(hover ? 1 : 0)
                    }
            } content: { ChordPalette(index: index) }
            .padding(.vertical, -4)
            .help(tr("Change chord"))
            Text(numeral).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.dim)
            if keyboard {
                let notes = PianoVoicing.playable(root: root, quality: quality)
                KeyboardView(low: 53, high: 77,
                             marks: Dictionary(uniqueKeysWithValues: notes.dropFirst().map { m in
                                 (m, KeyMark(label: "", root: (m - root) % 12 == 0)) }),
                             height: 104)
                    .frame(height: 150, alignment: .center)
            } else if let v = voicing {
                ChordDiagram(voicing: v, tuning: tuning, root: root, quality: quality, label: .fingers, interactive: false)
            }
            // The beat inside this chord while the loop plays.
            HStack(spacing: 5) {
                ForEach(0..<beats, id: \.self) { i in
                    Circle()
                        .fill(beat == i ? Theme.good : Theme.line)
                        .frame(width: 6, height: 6)
                }
            }
            .opacity(active ? 1 : 0.4)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(active ? Theme.good.opacity(0.12) : (hover ? Theme.line.opacity(0.45) : Theme.line.opacity(0.22))))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(active ? Theme.good.opacity(0.6) : .clear, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if hover && canRemove {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Theme.line))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(7)
                .help(tr("Remove chord"))
            }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2, perform: open)
        .onTapGesture(perform: play)
        .help(tr("Click to play · double-click to open in the library"))
        .animation(.easeOut(duration: 0.12), value: active)
    }
}

/// The slim "+" slot after the last card: adds a chord that fits.
private struct AddChordTile: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                .foregroundStyle(hover ? Theme.dim : Theme.ghost)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.line.opacity(hover ? 0.45 : 0.16)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(tr("Add a chord"))
    }
}

/// Chords for one card: the key's own seven (with numerals), or any root and quality.
/// Root and quality chips keep the panel open so choices can be auditioned.
private struct ChordPalette: View {
    let index: Int
    @ObservedObject var player = ProgressionPlayer.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        if let p = player.progression, p.steps.indices.contains(index) {
            let step = p.steps[index]
            let root = p.root(index)
            VStack(alignment: .leading, spacing: 0) {
                DropdownHeader(title: prefs.notation.name(pc: p.key) + " " + (p.minor ? tr("minor") : tr("major")))
                ForEach(Progressions.diatonic(minor: p.minor), id: \.offset) { c in
                    let r = (p.key + c.offset) % 12
                    DropdownItem(title: ChordsView.name(r, c.quality, prefs.notation),
                                 detail: Progressions.numeral(offset: c.offset, quality: c.quality, minor: p.minor),
                                 selected: step.offset == c.offset && step.quality == c.quality) { pick(r, c.quality) }
                }
                DropdownHeader(title: tr("Reharmonize"))
                ForEach(Progressions.reharmonizations(of: p, at: index), id: \.self) { c in
                    let r = (p.key + c.offset) % 12
                    DropdownItem(title: ChordsView.name(r, c.quality, prefs.notation), detail: why(c, p), selected: false) {
                        pick(r, c.quality)
                    }
                }
                DropdownHeader(title: tr("Any chord"))
                Grid(horizontalSpacing: 0, verticalSpacing: 2) {
                    ForEach(0..<2, id: \.self) { row in
                        GridRow {
                            ForEach(0..<6, id: \.self) { col in
                                let pc = row * 6 + col
                                TextChoice(title: prefs.notation.name(pc: pc), selected: root == pc, size: 11) { pick(pc, step.quality) }
                            }
                        }
                    }
                }
                .padding(.leading, 18)
                FlowLayout(spacing: 2, lineSpacing: 2) {
                    ForEach(Chords.qualities) { q in
                        TextChoice(title: q.symbol, selected: step.quality == q.id, size: 11) { pick(root, q.id) }
                            .help(tr(q.name))
                    }
                }
                .frame(width: 236, alignment: .leading)
                .padding(.leading, 18)
                .padding(.top, 6)
                .padding(.bottom, 6)
            }
            .frame(width: 290, alignment: .leading)
        }
    }

    /// Why a reharmonization works, in a few words.
    private func why(_ c: Reharm, _ p: Progression) -> String {
        let n = prefs.notation
        let next = (index + 1) % p.steps.count
        let nextName = ChordsView.name(p.root(next), p.steps[next].quality, n)
        switch c.why {
        case .colour: return tr("adds colour")
        case .relative: return tr("two notes in common")
        case .leadsTo: return trf("leads to %@", nextName)
        case .slidesTo: return trf("slides into %@", nextName)
        case .tritone: return tr("tritone substitute")
        case .passing: return trf("passes into %@", nextName)
        case .borrowed: return trf("from %@", n.name(pc: p.key) + " " + (p.minor ? tr("major") : tr("minor")))
        }
    }

    private func pick(_ root: Int, _ quality: String) {
        player.setChord(index, root: root, quality: quality)
        // Stopped: let the choice be heard. Playing: the loop plays it.
        if !player.playing {
            ChordsView.play(root: root, quality: Chords.quality(quality), instrument: prefs.instrument,
                            tuning: prefs.tuning, a4: prefs.a4)
        }
    }
}
