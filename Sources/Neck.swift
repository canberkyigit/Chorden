import SwiftUI

/// One dot on the neck.
struct NeckMark: Hashable {
    let string: Int
    /// Semitones from the nut; fractional for koma-inflected makam degrees on fretless instruments.
    let position: Double
    let label: String
    let root: Bool
    /// Microtonal pitch shown at the nearest fret of a fretted (12-TET) instrument.
    let approx: Bool
    let midi: Double
}

enum NeckMarks {
    /// Every occurrence of `tones` (offsets above `root` in semitones, possibly fractional) on every string.
    static func build(tuning: Tuning, frets: Int, fretless: Bool, root: Int,
                      tones: [(offset: Double, label: String)]) -> [NeckMark] {
        var out: [NeckMark] = []
        for (s, open) in tuning.notes.enumerated() {
            for t in tones {
                var p = (Double(root) + t.offset - Double(open)).truncatingRemainder(dividingBy: 12)
                if p < -0.001 { p += 12 }
                while p <= Double(frets) + 0.001 {
                    let microtonal = abs(p - p.rounded()) > 0.05
                    let pos = fretless ? p : p.rounded()
                    if pos <= Double(frets) {
                        out.append(NeckMark(string: s, position: pos, label: t.label, root: abs(t.offset) < 0.001,
                                            approx: microtonal && !fretless, midi: Double(open) + p))
                    }
                    p += 12
                }
            }
        }
        return out
    }
}

struct NeckView: View {
    let instrument: Instrument
    let tuning: Tuning
    let marks: [NeckMark]
    /// Frets outside this range are dimmed (scale position boxes).
    var focus: ClosedRange<Int>? = nil
    /// The dot sounding right now (scale playback).
    var active: NeckMark? = nil
    /// Strings drawn with a × at the nut (chord finder).
    var muted: Set<Int> = []
    /// Makes the whole neck a tap target: (string, fret) of the nearest position, 0 = open.
    var onTap: ((Int, Int) -> Void)? = nil
    /// Space between strings; the chord finder uses roomier rows as tap targets.
    var rowH: CGFloat = 26
    @ObservedObject var prefs = Prefs.shared
    @State private var hover: (string: Int, fret: Int)?

    private var fretted: Bool { instrument.frets > 0 }
    private var count: Int { fretted ? min(instrument.frets, 15) : 12 }
    private let openW: CGFloat = 34

    var body: some View {
        let n = tuning.notes.count
        GeometryReader { geo in
            // Room on the right so dots at the last position aren't clipped.
            let xs = fretXs(width: geo.size.width - openW - 14)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let top: CGFloat = 8
                    let height = CGFloat(n - 1) * rowH
                    if let f = focus {
                        let x0 = f.lowerBound == 0 ? 0 : openW + xs[max(0, f.lowerBound - 1)]
                        let x1 = openW + xs[min(count, f.upperBound)]
                        ctx.fill(Path(roundedRect: CGRect(x: x0, y: top - 12, width: x1 - x0, height: height + 24), cornerRadius: 8),
                                 with: .color(Theme.line.opacity(0.35)))
                    }
                    // Frets (or faint semitone guides on fretless instruments).
                    for i in 0...count {
                        let x = openW + xs[i]
                        let w: CGFloat = i == 0 ? 3 : 1
                        ctx.fill(Path(CGRect(x: x - w / 2, y: top, width: w, height: height)),
                                 with: .color(i == 0 ? Theme.text : (fretted ? Theme.faint : Theme.line.opacity(0.6))))
                    }
                    // Strings: highest pitch on top, as in tab.
                    for row in 0..<n {
                        let y = top + CGFloat(row) * rowH
                        ctx.fill(Path(CGRect(x: openW, y: y - 0.5, width: size.width - openW, height: 1)),
                                 with: .color(Theme.faint))
                    }
                    for i in [3, 5, 7, 9, 12, 15] where i <= count {
                        let x = openW + (xs[i - 1] + xs[i]) / 2
                        ctx.draw(Text("\(i)").font(.system(size: 9, weight: .medium)).foregroundColor(Theme.ghost),
                                 at: CGPoint(x: x, y: top + height + 16))
                    }
                    for s in muted where s < n {
                        ctx.draw(Text("×").font(.system(size: 13)).foregroundColor(Theme.ghost),
                                 at: CGPoint(x: openW / 2, y: top + CGFloat(n - 1 - s) * rowH))
                    }
                    if let h = hover, !marks.contains(where: { $0.string == h.string && Int($0.position.rounded()) == h.fret }) {
                        let c = CGPoint(x: x(Double(h.fret), xs), y: top + CGFloat(n - 1 - h.string) * rowH)
                        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20)),
                                   with: .color(Theme.dim.opacity(0.6)), lineWidth: 1)
                    }
                }
                ForEach(marks, id: \.self) { m in
                    let row = n - 1 - m.string
                    let dim = focus.map { !$0.contains(Int(m.position.rounded())) } ?? false
                    let lit = active.map { $0.string == m.string && abs($0.midi - m.midi) < 0.001 } ?? false
                    NeckDot(text: m.label, root: m.root, open: m.position == 0, approx: m.approx, lit: lit)
                        // The colour changes on the beat; only the size eases.
                        .transaction { $0.animation = nil }
                        .scaleEffect(lit ? 1.3 : 1)
                        .animation(.spring(response: 0.18, dampingFraction: 0.6), value: lit)
                        .position(x: x(m.position, xs), y: 8 + CGFloat(row) * rowH)
                        .opacity(dim && !lit ? 0.22 : 1)
                        .zIndex(lit ? 1 : 0)
                        .onTapGesture { Synth.shared.pluck(Music.frequency(midi: m.midi, a4: prefs.a4)) }
                        .help(m.approx ? tr("Microtonal: nearest fret shown") : "")
                        .allowsHitTesting(onTap == nil)
                }
                if let onTap {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { e in
                            let p = spot(e.location, xs, n)
                            onTap(p.string, p.fret)
                        })
                        .onContinuousHover { phase in
                            if case .active(let loc) = phase { hover = spot(loc, xs, n) } else { hover = nil }
                        }
                }
            }
        }
        .frame(height: CGFloat(n - 1) * rowH + 40)
    }

    /// The string and fret under a point: frets between their wires, fretless stops at the nearest semitone.
    private func spot(_ p: CGPoint, _ xs: [CGFloat], _ n: Int) -> (string: Int, fret: Int) {
        let row = min(n - 1, max(0, Int(((p.y - 8) / rowH).rounded())))
        var fret = 0
        if p.x >= openW {
            let dx = p.x - openW
            if fretted {
                fret = min(count, max(1, (xs.firstIndex { $0 > dx } ?? count)))
            } else {
                fret = (1...count).min { abs(xs[$0] - dx) < abs(xs[$1] - dx) } ?? 1
            }
        }
        return (n - 1 - row, fret)
    }

    /// Fretted: between the fret wires. Fretless: exactly where the finger stops the string.
    private func x(_ p: Double, _ xs: [CGFloat]) -> CGFloat {
        if p <= 0.001 { return openW / 2 }
        if fretted {
            let f = Int(p.rounded())
            return openW + (xs[f - 1] + xs[f]) / 2
        }
        let i = min(count - 1, Int(p))
        return openW + xs[i] + (xs[i + 1] - xs[i]) * CGFloat(p - Double(i))
    }

    /// Fret positions from the nut, spaced like a real neck (each fret 2^(-1/12) narrower).
    private func fretXs(width: CGFloat) -> [CGFloat] {
        let ratio = fretted ? pow(2, -1.0 / 12) : 1
        var widths: [CGFloat] = [], w: CGFloat = 1
        for _ in 0..<count { widths.append(w); w *= ratio }
        let total = widths.reduce(0, +)
        var xs: [CGFloat] = [0], acc: CGFloat = 0
        for w in widths { acc += w / total * width; xs.append(acc) }
        return xs
    }
}

private struct NeckDot: View {
    let text: String
    let root: Bool
    let open: Bool
    var approx = false
    var lit = false

    var body: some View {
        Text(text)
            .font(.system(size: text.count > 2 ? 7.5 : 9, weight: .bold))
            .foregroundStyle(lit || root ? Color(nsColor: Theme.windowBG) : Theme.text)
            .frame(width: 22, height: 22)
            .background(Circle().fill(lit ? Theme.good : (root ? Theme.text : (open || approx ? Theme.bg : Theme.line))))
            .shadow(color: lit ? Theme.good.opacity(0.7) : .clear, radius: 6)
            .overlay(Circle().strokeBorder(open && !root ? Theme.dim : (approx ? Theme.warn : .clear),
                                           style: StrokeStyle(lineWidth: 1, dash: approx ? [2, 2] : [])))
            .contentShape(Circle())
    }
}
