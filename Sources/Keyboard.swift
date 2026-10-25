import SwiftUI

/// A key marked on the keyboard.
struct KeyMark: Equatable {
    let label: String
    let root: Bool
    /// Microtonal degree shown on the nearest key (makams on a tempered piano).
    var approx = false
}

/// A piano keyboard drawn to scale, with labelled marks and an optional key lit while it sounds.
struct KeyboardView: View {
    /// MIDI range; starts and ends are widened to white keys.
    let low: Int
    let high: Int
    var marks: [Int: KeyMark] = [:]
    var active: Set<Int> = []
    var height: CGFloat = 110
    var onTap: ((Int) -> Void)? = nil

    private static let blackPCs: Set<Int> = [1, 3, 6, 8, 10]
    private func isBlack(_ m: Int) -> Bool { Self.blackPCs.contains(((m % 12) + 12) % 12) }

    var body: some View {
        let start = isBlack(low) ? low - 1 : low
        let end = isBlack(high) ? high + 1 : high
        let whites = (start...end).filter { !isBlack($0) }
        GeometryReader { geo in
            let w = geo.size.width / CGFloat(whites.count)
            let blackW = w * 0.62, blackH = height * 0.62
            ZStack(alignment: .topLeading) {
                ForEach(Array(whites.enumerated()), id: \.element) { i, m in
                    key(m, black: false, width: w - 1.5, keyHeight: height)
                        .offset(x: CGFloat(i) * w)
                }
                ForEach((start...end).filter { isBlack($0) }, id: \.self) { m in
                    let left = whites.firstIndex(of: m - 1) ?? 0
                    key(m, black: true, width: blackW, keyHeight: blackH)
                        .offset(x: CGFloat(left + 1) * w - blackW / 2 - 0.75)
                }
            }
        }
        .frame(height: height)
    }

    // Key colours barely change with the appearance, so the marks use fixed inks that read on them:
    // dark chips on white keys, light chips on black keys, the root in the strongest ink. A key that
    // is playing turns green and its chip white.
    private static let ink = Color(nsColor: NSColor(hex: 0x1C1D21))
    private static let softInk = Color(nsColor: NSColor(hex: 0x62636C))
    private static let paper = Color.white
    private static let softPaper = Color(nsColor: NSColor(hex: 0xB9BAC2))
    private static let litText = Color(nsColor: NSColor(hex: 0x0E6B3A))

    private func chip(_ width: CGFloat, _ black: Bool) -> CGFloat { min(20, black ? max(width - 3, 15) : width - 3) }

    @ViewBuilder
    private func key(_ m: Int, black: Bool, width: CGFloat, keyHeight: CGFloat) -> some View {
        let mark = marks[m]
        let lit = active.contains(m)
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: black ? 3 : 5, style: .continuous)
                .fill(lit ? Theme.good.opacity(black ? 0.95 : 0.8)
                          : (black ? Color(nsColor: .dynamic(light: 0x26272C, dark: 0x0B0B0D))
                                   : Color(nsColor: .dynamic(light: 0xFFFFFF, dark: 0xD9D9DE))))
                .overlay(RoundedRectangle(cornerRadius: black ? 3 : 5, style: .continuous)
                    .strokeBorder(Color.black.opacity(black ? 0 : 0.25), lineWidth: 0.75))
            if let mark {
                let fill = lit ? Self.paper : black ? (mark.root ? Self.paper : Self.softPaper) : (mark.root ? Self.ink : Self.softInk)
                let text = lit ? Self.litText : black ? Self.ink : Self.paper
                Text(mark.label)
                    .font(.system(size: mark.label.count > 2 ? 7 : (width > 22 ? 9 : 7.5), weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(text)
                    // Narrow black keys may carry a chip a little wider than the key.
                    .frame(width: chip(width, black), height: chip(width, black))
                    .background(Circle().fill(fill))
                    .overlay(Circle().strokeBorder(mark.approx ? Theme.warn : .clear,
                                                   style: StrokeStyle(lineWidth: 1.25, dash: [2, 2])))
                    .padding(.bottom, 6)
            }
        }
        .frame(width: width, height: keyHeight)
        .contentShape(Rectangle())
        .onTapGesture { onTap?(m) }
        .allowsHitTesting(onTap != nil)
    }
}

enum PianoVoicing {
    /// Chord tones above the root in close position (extensions kept above the octave).
    static func close(_ quality: ChordQuality) -> [Int] {
        var seen = Set<Int>()
        return quality.intervals.filter { seen.insert($0 % 12).inserted }
    }

    /// Root position and every inversion, starting near C4, plus an open two-hand voicing for 4+ notes.
    static func all(root: Int, quality: ChordQuality) -> [(name: String, notes: [Int])] {
        let tones = close(quality)
        let base = 60 + root - (root > 6 ? 12 : 0)
        var out: [(String, [Int])] = []
        let names = ["Root position", "1st inversion", "2nd inversion", "3rd inversion", "4th inversion"]
        for k in 0..<min(tones.count, 4) {
            let rotated = tones[k...] + tones[..<k].map { $0 + 12 }
            let shift = rotated.first! >= 12 ? -12 : 0
            out.append((names[k], rotated.map { base + $0 + shift }))
        }
        if tones.count >= 4 {
            // Left hand root + fifth (or seventh), right hand the colour tones an octave up.
            let left = [base - 12, base - 12 + (tones.contains(7) ? 7 : tones[2])]
            let right = tones.filter { $0 != 0 && $0 != 7 }.map { base + $0 }
            out.append(("Open voicing", left + right))
        }
        return out
    }

    /// What the progression player and chord buttons play: left-hand root, right hand in close position.
    static func playable(root: Int, quality: ChordQuality) -> [Int] {
        let tones = close(quality)
        let bass = 36 + root + (root < 4 ? 12 : 0)
        let base = 60 + root - (root > 6 ? 12 : 0)
        return [bass] + tones.map { base + $0 }
    }
}

/// The chord page for piano: the chord's voicings on keyboards, and the chord tones across three octaves.
struct PianoChordsView: View {
    let root: Int
    let quality: ChordQuality
    let label: DotLabel
    @ObservedObject var prefs = Prefs.shared
    /// The voicing sounding now (name and keys), so only the pressed keyboard lights.
    @State private var sounding: String?
    @State private var token = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(PianoVoicing.all(root: root, quality: quality), id: \.name) { v in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr(v.name)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim)
                        KeyboardView(low: 36, high: 84, marks: marks(v.notes),
                                     active: sounding == id(v) ? Set(v.notes) : [], height: 86)
                            .contentShape(Rectangle())
                            .onTapGesture { play(v) }
                    }
                }
            }
            .padding(.vertical, 20)
        }
    }

    private func id(_ v: (name: String, notes: [Int])) -> String { v.name + "\(v.notes)" }

    private func marks(_ notes: [Int]) -> [Int: KeyMark] {
        var out: [Int: KeyMark] = [:]
        for n in notes {
            let pc = ((n - root) % 12 + 12) % 12
            let iv = quality.intervals.first { $0 % 12 == pc } ?? 0
            out[n] = KeyMark(label: label == .intervals ? quality.label(iv) : prefs.notation.name(pc: n), root: pc == 0)
        }
        return out
    }

    private func play(_ v: (name: String, notes: [Int])) {
        Synth.shared.strum(v.notes.map { Synth.Note(frequency: Music.frequency(midi: Double($0), a4: prefs.a4)) })
        sounding = id(v)
        token += 1
        let t = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if token == t { sounding = nil } }
    }
}
