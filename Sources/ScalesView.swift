import SwiftUI

struct ScalesView: View {
    @ObservedObject var prefs = Prefs.shared
    @State private var degrees = false
    /// The scale family being browsed (defaults to the selected scale's).
    @State private var group: String?
    /// Plays the scale on the audio clock and says which note is being heard.
    @ObservedObject private var player = ScalePlayer.shared

    var body: some View {
        let instrument = prefs.instrument
        let tuning = prefs.tuning
        let scale = Scales.scale(prefs.scaleID)
        let root = prefs.scaleRoot
        let fretted = instrument.frets > 0
        let frets = fretted ? min(instrument.frets, 15) : 12
        let boxes = fretted ? positions(scale, root: root, tuning: tuning) : []
        let position = prefs.scalePosition <= boxes.count ? prefs.scalePosition : 0
        let microtonal = scale.degrees.contains { abs($0 - $0.rounded()) > 0.01 }
        let sounding = player.current

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                InstrumentPicker(allowModes: false)
                Spacer()
                Button {
                    if player.playing {
                        player.stop()
                    } else if instrument.isKeyboard {
                        playKeys(scale, root: root)
                    } else {
                        play(scale, root: root, marks: marks(scale, root: root, tuning: tuning, frets: frets, fretted: fretted),
                             box: position > 0 ? boxes[position - 1] : nil)
                    }
                } label: {
                    let playing = player.playing
                    HStack(spacing: 6) {
                        Image(systemName: playing ? "stop.fill" : "play.fill").font(.system(size: 10))
                        Text(playing ? tr("Stop") : tr("Play")).font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(Theme.line.opacity(0.6), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)

            HStack(spacing: 0) {
                ForEach(0..<12, id: \.self) { pc in
                    TextChoice(title: prefs.notation.name(pc: pc), selected: root == pc, size: 13) { prefs.scaleRoot = pc }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 14)

            // Families on one line, the chosen family's scales below: stays compact as the list grows.
            let browsing = group ?? scale.group
            FlowLayout(spacing: 2, lineSpacing: 2) {
                ForEach(Scales.groups, id: \.self) { g in
                    TextChoice(title: tr(g), selected: browsing == g, size: 11) { group = g }
                }
            }
            .padding(.top, 12)
            .padding(.leading, -8)
            FlowLayout(spacing: 2, lineSpacing: 2) {
                ForEach(Scales.all.filter { $0.group == browsing }) { s in
                    TextChoice(title: tr(s.name), selected: scale.id == s.id, size: 12) {
                        stop()
                        prefs.scaleID = s.id
                        prefs.scalePosition = 0
                        // A makam starts on its usual karar; the user can move it afterwards.
                        if let k = s.karar { prefs.scaleRoot = k }
                    }
                }
            }
            .padding(.top, 6)
            .padding(.leading, -8)

            Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 16)

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(prefs.notation.name(pc: root) + " " + tr(scale.name))
                    .font(.system(size: 26, weight: .semibold))
                Text(scale.steps + (scale.isMakam ? " " + tr("koma") : ""))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.dim)
                Spacer()
                HStack(spacing: 8) {
                    ForEach(scale.degrees.indices, id: \.self) { i in
                        Text(Scales.degreeLabel(scale, i, root: root, prefs.notation))
                            .font(.system(size: 13, weight: sounding?.degree == i ? .bold : .medium))
                            .foregroundStyle(sounding?.degree == i ? Theme.good : Theme.text)
                    }
                }
            }

            HStack(spacing: 2) {
                if !boxes.isEmpty {
                    TextChoice(title: tr("Whole neck"), selected: position == 0, size: 11) { prefs.scalePosition = 0 }
                    ForEach(boxes.indices, id: \.self) { i in
                        TextChoice(title: "\(i + 1)", selected: position == i + 1, size: 11) { prefs.scalePosition = i + 1 }
                    }
                } else if scale.isMakam {
                    Text(tr("Koma degrees drawn at their exact place"))
                        .font(.system(size: 11)).foregroundStyle(Theme.dim).padding(.leading, 8)
                }
                Spacer()
                TextChoice(title: tr("Notes"), selected: !degrees, size: 11) { degrees = false }
                TextChoice(title: tr("Degrees"), selected: degrees, size: 11) { degrees = true }
            }
            .padding(.top, 12)
            .padding(.horizontal, -8)

            if microtonal && fretted {
                Text(tr("Dashed dots are microtones between frets: bend or slide slightly to reach them."))
                    .font(.system(size: 11)).foregroundStyle(Theme.ghost)
                    .padding(.top, 6)
            }

            if instrument.isKeyboard {
                if microtonal {
                    Text(tr("A piano can't play these microtones: dashed keys are the nearest note. ▶ plays the true pitches."))
                        .font(.system(size: 11)).foregroundStyle(Theme.ghost)
                        .padding(.top, 6)
                }
                KeyboardView(low: 48, high: 84, marks: keyMarks(scale, root: root), active: sounding.map { [Int($0.midi.rounded())] } ?? [],
                             height: 130) { m in Synth.shared.pluck(Music.frequency(midi: Double(m), a4: prefs.a4)) }
                    .padding(.vertical, 24)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    NeckView(instrument: instrument, tuning: tuning,
                             marks: marks(scale, root: root, tuning: tuning, frets: frets, fretted: fretted),
                             focus: position > 0 ? boxes[position - 1] : nil, active: sounding?.mark)
                        .padding(.vertical, 24)
                }
            }
        }
        .padding(.horizontal, 28)
        .onChange(of: prefs.scaleRoot) { _ in stop() }
        .onChange(of: prefs.scalePosition) { _ in stop() }
        .onChange(of: prefs.instrumentID) { _ in stop() }
        .onDisappear { stop() }
    }

    private func marks(_ scale: Scale, root: Int, tuning: Tuning, frets: Int, fretted: Bool) -> [NeckMark] {
        NeckMarks.build(tuning: tuning, frets: frets, fretless: !fretted, root: root,
                        tones: scale.degrees.enumerated().map { i, d in
                            (d, degrees ? degreeLabel(d, index: i, makam: scale.isMakam)
                                        : Scales.degreeLabel(scale, i, root: root, prefs.notation))
                        })
    }

    /// Scale tones on the keys from C3 to C6; koma degrees sit on their nearest key, marked as approximate.
    private func keyMarks(_ scale: Scale, root: Int) -> [Int: KeyMark] {
        var out: [Int: KeyMark] = [:]
        // Each degree sits on its nearest key (a half-flat rounds up: E½♭ shows on E).
        for (i, d) in scale.degrees.enumerated() {
            let key = Int(d.rounded(.toNearestOrAwayFromZero))
            let mark = KeyMark(label: degrees ? degreeLabel(d, index: i, makam: scale.isMakam)
                                              : Scales.degreeLabel(scale, i, root: root, prefs.notation),
                               root: i == 0, approx: abs(d - d.rounded()) > 0.05)
            for octave in -1...4 {
                let m = root + key + 12 * octave + 36
                if (48...84).contains(m) && out[m] == nil { out[m] = mark }
            }
        }
        return out
    }

    /// One octave up and back down from the root nearest middle C, lighting each key as it's heard.
    private func playKeys(_ scale: Scale, root: Int) {
        let base = Double(60 + root - (root > 6 ? 12 : 0))
        let up = scale.degrees.indices.map { ScaleNote(midi: base + scale.degrees[$0], degree: $0) }
            + [ScaleNote(midi: base + 12, degree: 0)]
        player.play(up + up.dropLast().reversed())
    }

    private func degreeLabel(_ d: Double, index: Int, makam: Bool) -> String {
        if makam { return "\(index + 1)" }
        return ["1", "♭2", "2", "♭3", "3", "4", "♭5", "5", "♭6", "6", "♭7", "7"][Int(d.rounded()) % 12]
    }

    /// Position boxes: a hand-sized window starting at each scale tone on the lowest string.
    private func positions(_ scale: Scale, root: Int, tuning: Tuning) -> [ClosedRange<Int>] {
        guard let low = tuning.notes.min(), let s = tuning.notes.firstIndex(of: low) else { return [] }
        let open = tuning.notes[s]
        let starts = scale.degrees.map { d -> Int in
            let p = (Double(root) + d - Double(open)).truncatingRemainder(dividingBy: 12)
            return Int((p < 0 ? p + 12 : p).rounded()) % 12
        }
        return Array(Set(starts)).sorted().map { f in max(0, f - (f == 0 ? 0 : 1))...(f + 4) }
    }

    /// Plays the scale and lights each note on the neck as it sounds. In a position box it runs through
    /// every note of the box, low to high and back, like a practice run; otherwise one octave up and
    /// down from the lowest root, on the frets closest to the nut. Makam degrees play their koma.
    private func play(_ scale: Scale, root: Int, marks: [NeckMark], box: ClosedRange<Int>?) {
        let degreeOf = { (m: NeckMark) -> Int in
            let off = ((m.midi - Double(root)).truncatingRemainder(dividingBy: 12) + 12).truncatingRemainder(dividingBy: 12)
            return scale.degrees.indices.min { abs(scale.degrees[$0] - off) < abs(scale.degrees[$1] - off) } ?? 0
        }
        var run: [NeckMark] = []
        if let box {
            // One dot per pitch inside the box, taking the lower string where two overlap.
            var seen = Set<Int>()
            for m in marks.filter({ box.contains(Int($0.position.rounded())) }).sorted(by: { ($0.midi, $0.string) < ($1.midi, $1.string) })
            where seen.insert(Int((m.midi * 100).rounded())).inserted { run.append(m) }
        } else {
            let lowest = marks.filter(\.root).min { $0.midi < $1.midi }?.midi ?? 48
            for d in scale.degrees + [12] {
                let target = lowest + d
                if let m = marks.filter({ abs($0.midi - target) < 0.01 }).min(by: { ($0.position, -$0.string) < ($1.position, -$1.string) }) {
                    run.append(m)
                }
            }
        }
        guard !run.isEmpty else { return }
        let sequence = run + run.dropLast().reversed()
        player.play(sequence.map { ScaleNote(midi: $0.midi, degree: degreeOf($0), mark: $0) })
    }

    private func stop() { player.stop() }
}
