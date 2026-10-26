import SwiftUI

/// The circle of fifths around the progression's key: major keys outside, their relative minors inside.
/// The key's six main chords are shaded, its tonic filled, and the chords the progression uses are dotted.
/// Click a chord to hear it; then add it to the progression, or move the progression to that key.
struct CircleOfFifthsView: View {
    @ObservedObject var player = ProgressionPlayer.shared
    @ObservedObject var prefs = Prefs.shared
    @State private var picked: Segment?
    @State private var hover: Segment?

    /// A place on the circle: 0 is C (and A minor) at the top, each step clockwise a fifth higher.
    struct Segment: Hashable {
        let index: Int
        let minor: Bool
        var pc: Int { (index * 7 + (minor ? 9 : 0)) % 12 }
        var quality: String { minor ? "m" : "" }
    }

    private let size: CGFloat = 320
    private let outerR: CGFloat = 132, midR: CGFloat = 92, innerR: CGFloat = 56

    var body: some View {
        if let p = player.progression {
            VStack(spacing: 12) {
                circle(p)
                footer(p)
            }
            .padding(14)
            .frame(width: size + 28)
        }
    }

    // MARK: The circle

    private func circle(_ p: Progression) -> some View {
        // The major key whose six chords these are (a minor key shares its relative major's).
        let home = Self.index(of: p.minor ? p.key + 3 : p.key)
        let near = Set([home - 1, home, home + 1].map { ($0 + 12) % 12 })
        let used = Set(p.steps.indices.map { i -> Segment in
            let root = p.root(i)
            let minor = Chords.quality(p.steps[i].quality).intervals.contains(3)
            return Segment(index: Self.index(of: minor ? root + 3 : root), minor: minor)
        })
        let tonic = Segment(index: home, minor: p.minor)
        return ZStack {
            ForEach(0..<12, id: \.self) { i in
                ForEach([false, true], id: \.self) { minor in
                    let seg = Segment(index: i, minor: minor)
                    let shape = Sector(index: i, r0: minor ? innerR : midR, r1: minor ? midR : outerR)
                    shape
                        .fill(fill(seg, tonic: tonic, near: near.contains(i)))
                        .overlay(shape.stroke(picked == seg ? Theme.good : Theme.bg, lineWidth: picked == seg ? 2 : 1))
                        .contentShape(shape)
                        .onHover { hover = $0 ? seg : (hover == seg ? nil : hover) }
                        .onTapGesture { pick(seg) }
                    label(seg, tonic: tonic, used: used.contains(seg))
                }
                // Sharps or flats in the key, just outside the ring.
                Text(Self.signature(i))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.ghost)
                    .position(point(i, outerR + 14))
            }
            VStack(spacing: 2) {
                Text(spelled(tonic)).font(.system(size: 22, weight: .semibold))
                Text(p.minor ? tr("minor") : tr("major")).font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .help(tr("Click a chord to hear it"))
    }

    private func label(_ seg: Segment, tonic: Segment, used: Bool) -> some View {
        let name = spelled(seg) + seg.quality
        let r = seg.minor ? (innerR + midR) / 2 : (midR + outerR) / 2
        return VStack(spacing: 2) {
            Text(name)
                .font(.system(size: seg.minor ? 11 : 13, weight: seg == tonic ? .bold : .semibold))
                .foregroundStyle(seg == tonic ? Color(nsColor: Theme.windowBG) : Theme.text)
            // A dot under the chords the progression already plays.
            Circle().fill(seg == tonic ? Color(nsColor: Theme.windowBG) : Theme.good)
                .frame(width: 4, height: 4)
                .opacity(used ? 1 : 0)
        }
        .position(point(seg.index, r))
        .allowsHitTesting(false)
    }

    private func fill(_ seg: Segment, tonic: Segment, near: Bool) -> Color {
        if seg == tonic { return Theme.text }
        let base = near ? Theme.good.opacity(0.22) : Theme.line.opacity(0.35)
        return hover == seg ? (near ? Theme.good.opacity(0.36) : Theme.line.opacity(0.8)) : base
    }

    // MARK: The picked chord

    private func footer(_ p: Progression) -> some View {
        HStack(spacing: 10) {
            if let seg = picked {
                VStack(alignment: .leading, spacing: 1) {
                    Text(spelled(seg) + seg.quality).font(.system(size: 18, weight: .semibold))
                    Text(Progressions.numeral(offset: seg.pc - p.key, quality: seg.quality, minor: p.minor))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.dim)
                }
                Spacer()
                if p.steps.count < Progressions.lengths.upperBound {
                    capsule("plus", tr("Add")) { player.appendChord(root: seg.pc, quality: seg.quality) }
                        .help(tr("Add this chord to the end of the progression"))
                }
                // Moving keeps the mode, so only keys of the same kind (major or minor) are offered.
                if seg.minor == p.minor && seg.pc != p.key {
                    capsule("arrow.left.arrow.right", trf("Move to %@", spelled(seg) + seg.quality)) {
                        player.setKey(seg.pc)
                    }
                    .help(tr("Play the same progression in this key"))
                }
            } else {
                Text(tr("Shaded: the key's main chords. Dots: chords in the progression."))
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        }
        .frame(height: 36)
    }

    private func capsule(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Theme.line.opacity(0.6), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ seg: Segment) {
        picked = seg
        ChordsView.play(root: seg.pc, quality: Chords.quality(seg.quality), instrument: prefs.instrument,
                        tuning: prefs.tuning, a4: prefs.a4)
    }

    /// Keys are spelled as on the circle: sharps on the right, flats on the left (B♭, E♭), F♯ at the bottom.
    private func spelled(_ seg: Segment) -> String {
        Notation(accidental: (7...11).contains(seg.index) ? .flat : .sharp, naming: prefs.notation.naming).name(pc: seg.pc)
    }

    // MARK: Geometry

    /// Place of a pitch class on the circle (C 0, G 1, D 2 …): seven fifths make one semitone.
    static func index(of pc: Int) -> Int { ((pc % 12 + 12) % 12) * 7 % 12 }

    static func signature(_ i: Int) -> String {
        switch i {
        case 0: return ""
        case 6: return "6♯ 6♭"
        case 1...5: return "\(i)♯"
        default: return "\(12 - i)♭"
        }
    }

    private func point(_ index: Int, _ r: CGFloat) -> CGPoint {
        let a = (Double(index) * 30 - 90) * .pi / 180
        return CGPoint(x: size / 2 + r * CGFloat(cos(a)), y: size / 2 + r * CGFloat(sin(a)))
    }
}

/// One twelfth of a ring, centred on its place on the circle.
private struct Sector: Shape {
    let index: Int
    let r0: CGFloat
    let r1: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let mid = Double(index) * 30 - 90
        let a0 = Angle.degrees(mid - 15), a1 = Angle.degrees(mid + 15)
        var p = Path()
        p.addArc(center: c, radius: r1, startAngle: a0, endAngle: a1, clockwise: false)
        p.addArc(center: c, radius: r0, startAngle: a1, endAngle: a0, clockwise: true)
        p.closeSubpath()
        return p
    }
}
