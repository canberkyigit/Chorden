import SwiftUI

final class MetronomeModel: ObservableObject {
    static let shared = MetronomeModel()
    @Published private(set) var running = false
    private var taps: [Date] = []
    private let prefs = Prefs.shared

    func toggle() {
        running.toggle()
        sync()
    }

    func start() {
        guard !running else { return }
        running = true
        sync()
    }

    func stop() {
        guard running else { return }
        running = false
        sync()
    }

    func sync() {
        Synth.shared.setMetronome(.init(running: running, bpm: prefs.bpm, beats: prefs.beatsPerBar,
                                        subdivision: prefs.subdivision, sound: prefs.metronomeSound))
    }

    func nudge(_ delta: Double) {
        prefs.bpm = min(300, max(30, (prefs.bpm + delta).rounded()))
        sync()
    }

    /// Tap tempo: the average of the last few intervals; a pause of 2 s starts over.
    func tap() {
        let now = Date()
        if let last = taps.last, now.timeIntervalSince(last) > 2 { taps = [] }
        taps.append(now)
        taps = Array(taps.suffix(5))
        guard taps.count >= 2 else { return }
        let intervals = zip(taps, taps.dropFirst()).map { $1.timeIntervalSince($0) }
        prefs.bpm = min(300, max(30, (60 / (intervals.reduce(0, +) / Double(intervals.count))).rounded()))
        sync()
    }
}

struct MetronomeView: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var model = MetronomeModel.shared
    @State private var dragStart: Double?

    private let signatures: [(String, Int)] = [("2/4", 2), ("3/4", 3), ("4/4", 4), ("5/4", 5), ("6/8", 6), ("7/8", 7)]
    private let subdivisions = [1, 2, 3, 4]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            HStack(spacing: 28) {
                stepButton("minus") { model.nudge(-1) }
                VStack(spacing: 0) {
                    Text("\(Int(prefs.bpm))")
                        .font(.system(size: 120, weight: .thin).monospacedDigit())
                        .gesture(DragGesture(minimumDistance: 2)
                            .onChanged { v in
                                let start = dragStart ?? prefs.bpm
                                dragStart = start
                                prefs.bpm = min(300, max(30, (start - v.translation.height / 3).rounded()))
                                model.sync()
                            }
                            .onEnded { _ in dragStart = nil })
                        .help(tr("Drag up or down, or use ↑ ↓"))
                    Text("BPM · " + tr(marking(prefs.bpm)))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
                stepButton("plus") { model.nudge(1) }
            }

            TimelineView(.animation(paused: !model.running)) { _ in
                let beat = Synth.shared.beat
                HStack(spacing: 14) {
                    ForEach(0..<prefs.beatsPerBar, id: \.self) { i in
                        let lit = model.running && beat?.index == i
                            && Date().timeIntervalSince(beat!.at) < 60 / prefs.bpm * 0.9
                        Circle()
                            .fill(lit ? (i == 0 ? Theme.good : Theme.text) : Theme.line)
                            .frame(width: i == 0 ? 16 : 12, height: i == 0 ? 16 : 12)
                            .shadow(color: lit && i == 0 ? Theme.good.opacity(0.6) : .clear, radius: 6)
                    }
                }
                .frame(height: 20)
            }
            .padding(.top, 34)

            HStack(spacing: 18) {
                Button { model.toggle() } label: {
                    Image(systemName: model.running ? "stop.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(nsColor: Theme.windowBG))
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(model.running ? Theme.good : Theme.text))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(tr("Start / stop (Space)"))
                Button { model.tap() } label: {
                    Text(tr("Tap"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 64, height: 64)
                        .background(Circle().strokeBorder(Theme.line, lineWidth: 1.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(tr("Tap the tempo (T)"))
            }
            .padding(.top, 34)

            Spacer(minLength: 20)

            HStack(spacing: 2) {
                ForEach(signatures, id: \.0) { s in
                    TextChoice(title: s.0, selected: prefs.beatsPerBar == s.1, size: 12) {
                        prefs.beatsPerBar = s.1
                        model.sync()
                    }
                }
                Spacer()
                Dropdown {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.wave.2").font(.system(size: 11))
                        Text(tr(prefs.metronomeSound.name)).font(.system(size: 12))
                    }
                    .foregroundStyle(Theme.text)
                } content: {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(MetronomeSound.allCases, id: \.self) { s in
                            DropdownItem(title: tr(s.name), detail: tr(s.detail), selected: prefs.metronomeSound == s) {
                                prefs.metronomeSound = s
                                model.sync()
                                // While stopped, let the choice be heard.
                                if !model.running { Synth.shared.previewClick(s) }
                            }
                        }
                    }
                    .frame(minWidth: 280)
                }
                .help(tr("Click sound"))
                Spacer()
                ForEach(subdivisions, id: \.self) { s in
                    let selected = prefs.subdivision == s
                    Button {
                        prefs.subdivision = s
                        model.sync()
                    } label: {
                        NoteGlyph(subdivision: s, color: selected ? Theme.text : Theme.dim)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selected ? Theme.line.opacity(0.7) : .clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(tr(["", "Quarter notes", "Eighth notes", "Triplets", "Sixteenth notes"][s]))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        // Leaving the tab stops the click.
        .onDisappear { model.stop() }
    }

    private func marking(_ bpm: Double) -> String {
        switch bpm {
        case ..<60: return "Largo"
        case ..<76: return "Adagio"
        case ..<108: return "Andante"
        case ..<120: return "Moderato"
        case ..<168: return "Allegro"
        default: return "Presto"
        }
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 36, height: 36)
                .background(Circle().strokeBorder(Theme.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// A subdivision drawn as notation: a quarter note, two beamed eighths, a beamed eighth-note triplet
/// with its "3", or two sixteenths under a double beam.
struct NoteGlyph: View {
    let subdivision: Int
    let color: Color

    private var notes: Int { subdivision == 3 ? 3 : subdivision == 1 ? 1 : 2 }
    private let spacing: CGFloat = 6.5

    var body: some View {
        Canvas { ctx, size in
            let headY = size.height - 2.4
            let top: CGFloat = subdivision == 3 ? 6.5 : 1.5
            var stems: [CGFloat] = []
            for i in 0..<notes {
                let x = 3 + CGFloat(i) * spacing
                // An oval notehead, tilted as engraved.
                let head = Path(ellipseIn: CGRect(x: -2.75, y: -1.95, width: 5.5, height: 3.9))
                    .applying(CGAffineTransform(rotationAngle: -.pi / 9))
                    .applying(CGAffineTransform(translationX: x, y: headY))
                ctx.fill(head, with: .color(color))
                let stemX = x + 2.15
                stems.append(stemX)
                ctx.fill(Path(CGRect(x: stemX - 0.55, y: top, width: 1.1, height: headY - top - 0.4)), with: .color(color))
            }
            if let first = stems.first, let last = stems.last, notes > 1 {
                for b in 0..<(subdivision == 4 ? 2 : 1) {
                    let y = top + CGFloat(b) * 3.1
                    ctx.fill(Path(CGRect(x: first - 0.55, y: y, width: last - first + 1.1, height: 1.9)), with: .color(color))
                }
                if subdivision == 3 {
                    ctx.draw(Text("3").font(.system(size: 7, weight: .semibold)).foregroundColor(color),
                             at: CGPoint(x: (first + last) / 2, y: 2.6))
                }
            }
        }
        .frame(width: 5.2 + CGFloat(notes - 1) * spacing + 1, height: 17)
    }
}
