import SwiftUI

// MARK: - Instrument & tuning menus (shared by tuner, popover and chords)

struct InstrumentPicker: View {
    @ObservedObject var prefs = Prefs.shared
    /// The tuner offers Chromatic and Makam modes; the chord page doesn't.
    var allowModes = true
    /// Progressions: only instruments that play real recordings.
    var onlyRecorded = false
    var size: CGFloat = 13

    private var mode: TargetMode { allowModes ? prefs.targetMode : .instrument }

    var body: some View {
        HStack(spacing: 0) {
            Dropdown {
                Text(mode == .chromatic ? tr("Chromatic") : mode == .makam ? tr("Makam") : tr(prefs.instrument.name))
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(Theme.text)
            } content: { instruments }

            switch mode {
            case .instrument where prefs.instrument.isKeyboard:
                EmptyView()
            case .instrument:
                Dropdown {
                    Text(tr(prefs.tuning.name)).font(.system(size: size)).foregroundStyle(Theme.text)
                } content: { tunings }
                Dropdown(chevron: false) {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: size - 2))
                        .foregroundStyle(Theme.ghost)
                } content: { TuningEditor(instrument: prefs.instrument, tuning: prefs.tuning) }
                .help(tr("Custom tuning"))
            case .makam:
                Dropdown {
                    Text(Scales.scale(prefs.makamID).name).font(.system(size: size)).foregroundStyle(Theme.text)
                } content: { makams }
                Dropdown {
                    Text(trf("Karar %@", prefs.notation.name(pc: prefs.makamRoot)))
                        .font(.system(size: size)).foregroundStyle(Theme.dim)
                } content: { karar }
            case .chromatic:
                EmptyView()
            }
        }
        .padding(.leading, -8)
    }

    var instruments: some View {
        VStack(alignment: .leading, spacing: 0) {
            if allowModes {
                DropdownItem(title: tr("Chromatic"), detail: tr("any note"), selected: mode == .chromatic) {
                    prefs.targetMode = .chromatic
                }
                DropdownItem(title: tr("Makam"), detail: tr("53-koma degrees"), selected: mode == .makam) {
                    prefs.targetMode = .makam
                }
                Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 8)
            }
            HStack(alignment: .top, spacing: 6) {
                column(["Guitar", "Bass", "Bowed"])
                column(["Keyboard", "Folk", "Turkish & Middle Eastern"])
            }
        }
    }

    private func column(_ groups: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups.filter { g in Catalog.all.contains { $0.group == g && available($0) } }, id: \.self) { group in
                DropdownHeader(title: tr(group))
                ForEach(Catalog.all.filter { $0.group == group && available($0) }) { inst in
                    DropdownItem(title: tr(inst.name), selected: mode == .instrument && prefs.instrumentID == inst.id) {
                        prefs.instrumentID = inst.id
                        prefs.targetMode = .instrument
                    }
                }
            }
        }
        .frame(width: 210)
    }

    private func available(_ inst: Instrument) -> Bool { !onlyRecorded || Timbre.of(inst.id).samples != nil }

    /// Favorites and the user's own tunings first; long built-in lists split into Standard / Drop / Open / Other.
    var tunings: some View {
        let inst = prefs.instrument
        let all = inst.tunings
        let mine = prefs.customTunings[inst.id] ?? []
        let favorites = prefs.tunings(for: inst).filter { prefs.favoriteTunings.contains($0.id) }
        return VStack(alignment: .leading, spacing: 0) {
            if !favorites.isEmpty || !mine.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    if !favorites.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            DropdownHeader(title: tr("Favorites"))
                            ForEach(favorites) { tuningItem($0) }
                        }
                        .frame(minWidth: 280)
                    }
                    if !mine.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            DropdownHeader(title: tr("My Tunings"))
                            ForEach(mine) { tuningItem($0) }
                        }
                        .frame(minWidth: 280)
                    }
                }
                Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 8)
            }
            if all.count > 10 {
                HStack(alignment: .top, spacing: 6) {
                    tuningColumn(all, ["Standard", "Drop"])
                    tuningColumn(all, ["Open", "Other"])
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(all) { tuningItem($0) }
                }
                .frame(minWidth: 280)
            }
        }
    }

    private func tuningColumn(_ all: [Tuning], _ sections: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections, id: \.self) { section in
                DropdownHeader(title: tr(section))
                ForEach(all.filter { Self.section($0) == section }) { tuningItem($0) }
            }
        }
        .frame(minWidth: 280)
    }

    private func tuningItem(_ t: Tuning) -> some View {
        DropdownItem(title: tr(t.name), detail: t.notes.map { prefs.notation.name(pc: $0) }.joined(separator: " "),
                     selected: prefs.tuning.id == t.id,
                     starred: { prefs.favoriteTunings.contains(t.id) }, onStar: { prefs.toggleFavorite(t) }) {
            prefs.select(tuning: t, of: prefs.instrument)
        }
    }

    private static func section(_ t: Tuning) -> String {
        let n = t.name
        if n.hasPrefix("Drop") || n.hasPrefix("Double Drop") { return "Drop" }
        if n.hasPrefix("Open") || n == "DADGAD" { return "Open" }
        if n.contains("Standard") || n.contains("Step Down") { return "Standard" }
        return "Other"
    }

    private var makams: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Scales.makams) { m in
                DropdownItem(title: m.name, detail: m.steps, selected: prefs.makamID == m.id) {
                    prefs.makamID = m.id
                    if let k = m.karar { prefs.makamRoot = k }
                }
            }
        }
        .frame(minWidth: 250)
    }

    private var karar: some View {
        VStack(alignment: .leading, spacing: 0) {
            DropdownHeader(title: tr("Karar"))
            ForEach(0..<12, id: \.self) { pc in
                DropdownItem(title: prefs.notation.name(pc: pc), selected: prefs.makamRoot == pc) { prefs.makamRoot = pc }
            }
        }
        .frame(width: 120)
    }
}

/// Edit the current tuning string by string, then save it as one of "My Tunings".
struct TuningEditor: View {
    let instrument: Instrument
    @ObservedObject var prefs = Prefs.shared
    @State private var notes: [Int]
    @State private var name: String
    private let editing: Tuning?

    init(instrument: Instrument, tuning: Tuning) {
        self.instrument = instrument
        let custom = tuning.id.hasPrefix("custom.")
        editing = custom ? tuning : nil
        _notes = State(initialValue: tuning.notes)
        _name = State(initialValue: custom ? tuning.name : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing == nil ? tr("New tuning") : tr("Edit tuning"))
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 6) {
                ForEach(notes.indices, id: \.self) { i in
                    VStack(spacing: 2) {
                        step("chevron.up") { notes[i] = min(notes[i] + 1, 96) }
                        Text(prefs.notation.name(midi: notes[i]))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .frame(width: 38, height: 22)
                            .background(Theme.line.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                        step("chevron.down") { notes[i] = max(notes[i] - 1, 12) }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField(tr("Name"), text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.line.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    .frame(width: 150)
                    .onSubmit(save)
                TextChoice(title: tr("Save"), selected: true, size: 11, action: save)
                if let t = editing {
                    TextChoice(title: tr("Delete"), selected: false, size: 11) {
                        prefs.deleteCustom(t, for: instrument)
                        Dropdowns.shared.closeAll()
                    }
                }
            }
        }
        .padding(10)
    }

    private func save() {
        let fallback = notes.map { prefs.notation.name(pc: $0) }.joined()
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? fallback : name
        prefs.saveCustom(Tuning(id: editing?.id ?? "custom.\(UUID().uuidString)", name: title, notes: notes), for: instrument)
        Dropdowns.shared.closeAll()
    }

    private func step(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.dim)
                .frame(width: 38, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Big note

struct NoteDisplay: View {
    let midi: Int?
    let color: Color
    var size: CGFloat
    /// Replaces the plain ♯/♭ (makam degrees: ♭¹, ♯⁴ …).
    var accidental: String? = nil
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        let parts = midi.map { prefs.notation.parts(pc: $0) }
        // Accidental and octave hang off the letter as overlays, so the letter itself stays centred.
        Text(parts?.base ?? "–")
            .font(.system(size: size, weight: .thin))
            .overlay(alignment: .topTrailing) {
                Text(accidental ?? parts?.accidental ?? "")
                    .font(.system(size: size * 0.36, weight: .light))
                    .fixedSize()
                    .alignmentGuide(.trailing) { $0[.leading] - size * 0.04 }
                    .offset(y: size * 0.12)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(midi.map { String(Notation.octave($0)) } ?? "")
                    .font(.system(size: size * 0.24, weight: .regular))
                    .foregroundStyle(Theme.ghost)
                    .fixedSize()
                    .alignmentGuide(.trailing) { $0[.leading] - size * 0.05 }
                    .offset(y: -size * 0.2)
            }
            .foregroundStyle(color)
            .animation(.easeOut(duration: 0.15), value: color)
    }
}

// MARK: - Meters

struct NeedleMeter: View {
    let cents: Double
    let active: Bool
    let tolerance: Double
    var height: CGFloat = 70

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let half = w / 2 - 8
            let x = w / 2 + CGFloat(max(-50, min(50, cents))) / 50 * half
            let tint = Theme.tint(cents: cents, tolerance: tolerance, active: active)
            ZStack(alignment: .topLeading) {
                // In-tune zone.
                Rectangle()
                    .fill(Theme.good.opacity(active && abs(cents) <= tolerance ? 0.16 : 0.07))
                    .frame(width: max(2, CGFloat(tolerance) / 50 * half * 2), height: height * 0.62)
                    .position(x: w / 2, y: height * 0.36)
                ForEach(0...20, id: \.self) { i in
                    let c = i * 5 - 50
                    let major = c % 25 == 0
                    Rectangle()
                        .fill(c == 0 ? Theme.dim : (major ? Theme.faint : Theme.line))
                        .frame(width: c == 0 ? 1.5 : 1, height: major ? height * 0.42 : height * 0.22)
                        .position(x: w / 2 + CGFloat(c) / 50 * half, y: height * 0.36)
                }
                Capsule()
                    .fill(tint)
                    .frame(width: 4, height: height * 0.66)
                    .shadow(color: tint.opacity(active ? 0.5 : 0), radius: 6)
                    .position(x: x, y: height * 0.36)
                    .animation(.spring(response: 0.16, dampingFraction: 0.86), value: cents)
                HStack {
                    Text("−50"); Spacer(); Text("0"); Spacer(); Text("+50")
                }
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.ghost)
                .frame(width: half * 2 + 16)
                .position(x: w / 2, y: height * 0.9)
            }
        }
        .frame(height: height)
    }
}

/// Classic strobe: bands drift right when sharp, left when flat, and stand still in tune.
/// Each band runs at a higher harmonic, so the lower ones show fine deviations.
struct StrobeMeter: View {
    let cents: Double
    let active: Bool
    let tolerance: Double
    var height: CGFloat = 70

    private final class Phase { var value: [Double] = [0, 0, 0]; var last: Date? }
    @State private var phase = Phase()

    var body: some View {
        TimelineView(.animation(paused: !active)) { tl in
            Canvas { ctx, size in
                let now = tl.date
                let dt = phase.last.map { min(0.05, now.timeIntervalSince($0)) } ?? 0
                phase.last = now
                let locked = active && abs(cents) <= tolerance
                let tint = locked ? Theme.good : Theme.text
                let bands = 3
                let gap: CGFloat = 7
                let bandH = (size.height - gap * CGFloat(bands - 1)) / CGFloat(bands)
                ctx.clip(to: Path(CGRect(origin: .zero, size: size)))
                for b in 0..<bands {
                    let period = 28 / pow(2, CGFloat(b))
                    if active { phase.value[b] += max(-60, min(60, cents)) * 1.6 * pow(2, Double(b)) * dt }
                    let offset = CGFloat(phase.value[b].truncatingRemainder(dividingBy: Double(period)))
                    let y = CGFloat(b) * (bandH + gap)
                    var x = offset - period
                    let opacity = active ? 0.75 - Double(b) * 0.2 : 0.12
                    while x < size.width {
                        ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: period / 2, height: bandH),
                                      cornerRadius: min(2, period / 4)),
                                 with: .color(tint.opacity(opacity)))
                        x += period
                    }
                }
            }
        }
        .frame(height: height)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                     .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
    }
}

/// The last ~4 seconds of pitch: shows vibrato, drift and how a string settles.
struct TraceMeter: View {
    let trace: [Double?]
    let tolerance: Double
    var height: CGFloat = 70

    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2
            // ±30 ¢ fills the height: the interesting part of a settling string is the last few cents.
            let scale = size.height / 2 / 30
            let band = CGFloat(tolerance) * scale
            ctx.fill(Path(CGRect(x: 0, y: mid - band, width: size.width, height: band * 2)),
                     with: .color(Theme.good.opacity(0.08)))
            ctx.fill(Path(CGRect(x: 0, y: mid - 0.5, width: size.width, height: 1)), with: .color(Theme.line))
            let step = size.width / 199
            let start = 200 - trace.count
            var path = Path()
            var drawing = false
            for (i, v) in trace.enumerated() {
                guard let c = v else { drawing = false; continue }
                let p = CGPoint(x: CGFloat(start + i) * step, y: mid - CGFloat(max(-30, min(30, c))) * scale)
                if drawing { path.addLine(to: p) } else { path.move(to: p); drawing = true }
            }
            let last = trace.last.flatMap { $0 }
            let tint = Theme.tint(cents: last ?? 99, tolerance: tolerance, active: last != nil)
            ctx.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .frame(height: height)
    }
}

struct Meter: View {
    @ObservedObject var tuner = TunerModel.shared
    @ObservedObject var prefs = Prefs.shared
    var height: CGFloat
    var allowTrace = true

    var body: some View {
        let r = tuner.reading
        switch prefs.display == .trace && !allowTrace ? .needle : prefs.display {
        case .needle:
            NeedleMeter(cents: r.cents, active: r.hasSignal, tolerance: prefs.tolerance, height: height)
        case .strobe:
            StrobeMeter(cents: r.cents, active: r.hasSignal, tolerance: prefs.tolerance, height: height * 0.62)
                .frame(height: height)
        case .trace:
            TraceMeter(trace: tuner.trace, tolerance: prefs.tolerance, height: height)
        }
    }
}

// MARK: - Readouts

func centsText(_ c: Double) -> String {
    let v = abs(c) < 10 ? String(format: "%+.1f", c) : String(format: "%+.0f", c)
    return v.replacingOccurrences(of: "-", with: "−") + " ¢"
}

struct Readout: View {
    @ObservedObject var tuner = TunerModel.shared
    @ObservedObject var prefs = Prefs.shared
    var size: CGFloat = 13

    var body: some View {
        let r = tuner.reading
        HStack(spacing: 18) {
            Text(r.target == nil ? "– ¢" : centsText(r.cents))
                .frame(minWidth: 64, alignment: .trailing)
            if prefs.targetMode == .makam {
                Text(r.target == nil ? "– k" : String(format: "%+.1f k", r.cents / Scales.koma).replacingOccurrences(of: "-", with: "−"))
                    .frame(minWidth: 54)
                    .foregroundStyle(Theme.dim)
                    .help(tr("Deviation in komas (1 koma = 22.6 cents)"))
            }
            Text(r.target == nil ? "– Hz" : String(format: "%.2f Hz", r.frequency))
                .frame(minWidth: 84, alignment: .leading)
                .foregroundStyle(Theme.dim)
        }
        .font(.system(size: size, weight: .medium).monospacedDigit())
        .foregroundStyle(r.hasSignal ? Theme.text : Theme.ghost)
    }
}

/// One quiet line under the note: what to do next.
struct Hint: View {
    @ObservedObject var tuner = TunerModel.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        let r = tuner.reading
        Text(text(r))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(r.inTune ? Theme.good : Theme.dim)
            .animation(.easeOut(duration: 0.15), value: r.inTune)
    }

    private func text(_ r: Reading) -> String {
        guard tuner.status == .listening else { return " " }
        guard r.hasSignal, let target = r.target else {
            return prefs.targetMode == .instrument && !prefs.instrument.isKeyboard ? tr("Play a string") : tr("Play a note")
        }
        if r.inTune { return tr("In tune") }
        let heard = prefs.notation.name(midi: Int(r.midi.rounded()))
        let far = abs(r.cents) > 50 && Int(r.midi.rounded()) != target
        let dir = r.cents < 0 ? tr("Tune up") : tr("Tune down")
        return far ? dir + " · " + trf("hearing %@", heard) : dir
    }
}

// MARK: - Strings / makam degrees

struct StringsRow: View {
    @ObservedObject var tuner = TunerModel.shared
    @ObservedObject var prefs = Prefs.shared
    var size: CGFloat = 38

    private var items: [(label: String, help: String)] {
        if prefs.targetMode == .makam {
            return tuner.makamDegrees.indices.map { i in
                (Scales.degreeLabel(Scales.scale(prefs.makamID), i, root: prefs.makamRoot, prefs.notation), trf("Degree %d", i + 1))
            }
        }
        return prefs.tuning.notes.map { n in
            (prefs.notation.name(pc: n),
             "\(prefs.notation.name(midi: n)) · " + String(format: "%.2f Hz", Music.frequency(midi: Double(n), a4: prefs.a4)))
        }
    }

    var body: some View {
        let list = items
        let active = tuner.activeString
        HStack(spacing: size * 0.32) {
            ForEach(list.indices, id: \.self) { i in
                let isActive = active == i && (tuner.reading.hasSignal || tuner.lockedString == i)
                let tuned = tuner.tunedStrings.contains(i)
                let locked = tuner.lockedString == i
                Button { tuner.toggleLock(i) } label: {
                    ZStack {
                        Circle()
                            .fill(locked ? Theme.line : .clear)
                        Circle()
                            .strokeBorder(isActive ? (tuner.reading.inTune ? Theme.good : Theme.text) : Theme.line,
                                          lineWidth: isActive ? 1.5 : 1)
                        Text(list[i].label)
                            .font(.system(size: size * (list[i].label.count > 2 ? 0.27 : 0.34),
                                          weight: isActive ? .semibold : .regular))
                            .foregroundStyle(tuned ? Theme.good : (isActive ? Theme.text : Theme.dim))
                    }
                    .frame(width: size, height: size)
                    .overlay(alignment: .bottom) {
                        Circle().fill(Theme.good).frame(width: 4, height: 4)
                            .offset(y: 8).opacity(tuned ? 1 : 0)
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(list[i].help + " — " + (locked ? tr("click to unlock") : tr("click to lock")))
                .animation(.easeOut(duration: 0.12), value: isActive)
            }
        }
    }
}

/// Speaker toggle: plays the active string (or note) as a sustained reference tone.
struct ReferenceButton: View {
    @ObservedObject var tuner = TunerModel.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        Button { tuner.referenceOn.toggle() } label: {
            Image(systemName: tuner.referenceOn ? "speaker.wave.2.fill" : "speaker.wave.2")
                .font(.system(size: 13))
                .foregroundStyle(tuner.referenceOn ? Theme.text : Theme.dim)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tr("Reference tone (Space)"))
    }
}

struct StatusMessage: View {
    @ObservedObject var tuner = TunerModel.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        switch tuner.status {
        case .denied:
            VStack(spacing: 10) {
                Text(tr("Chorden needs microphone access to hear your instrument."))
                    .font(.system(size: 12)).foregroundStyle(Theme.dim)
                Button(tr("Open Privacy Settings")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
            }
        case .failed(let msg):
            VStack(spacing: 10) {
                Text(msg).font(.system(size: 12)).foregroundStyle(Theme.dim)
                Button(tr("Try Again")) { tuner.retry() }
            }
        default:
            EmptyView()
        }
    }
}

// MARK: - All strings at once

struct PolyView: View {
    @ObservedObject var tuner = TunerModel.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        let notes = prefs.tuning.notes
        let poly = tuner.poly
        let heard = poly.filter(\.fresh)
        let allGood = !poly.isEmpty && poly.allSatisfy { $0.fresh && abs($0.cents ?? 99) <= prefs.tolerance }
        VStack(spacing: 18) {
            Text(allGood ? tr("All strings in tune") : (heard.isEmpty ? tr("Strum all strings") : tr("Tune the strings that are off, then strum again")))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(allGood ? Theme.good : Theme.dim)
            HStack(alignment: .bottom, spacing: notes.count > 6 ? 14 : 22) {
                ForEach(notes.indices, id: \.self) { i in
                    PolyColumn(note: notes[i], string: i < poly.count ? poly[i] : PolyString(), tolerance: prefs.tolerance)
                }
            }
        }
    }
}

private struct PolyColumn: View {
    let note: Int
    let string: PolyString
    let tolerance: Double
    @ObservedObject var prefs = Prefs.shared
    private let h: CGFloat = 170

    var body: some View {
        let c = string.cents
        let tint = Theme.tint(cents: c ?? 99, tolerance: tolerance, active: c != nil && string.fresh)
        VStack(spacing: 8) {
            Text(c.map(centsText) ?? "–")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(c == nil ? Theme.ghost : tint)
                .frame(width: 56)
            ZStack {
                Capsule().fill(Theme.line.opacity(0.45)).frame(width: 4)
                Rectangle().fill(Theme.good.opacity(0.18))
                    .frame(width: 30, height: max(2, CGFloat(tolerance) / 50 * h / 2 * 2))
                Rectangle().fill(Theme.dim).frame(width: 18, height: 1)
                if let c {
                    Capsule()
                        .fill(tint)
                        .frame(width: 30, height: 5)
                        .shadow(color: tint.opacity(string.fresh ? 0.5 : 0), radius: 5)
                        // Sharp is up, flat is down.
                        .offset(y: -CGFloat(max(-50, min(50, c))) / 50 * h / 2)
                        .opacity(string.fresh ? 1 : 0.35)
                        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: c)
                }
            }
            .frame(width: 40, height: h)
            Text(prefs.notation.name(pc: note))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c != nil && string.fresh && abs(c!) <= tolerance ? Theme.good : Theme.text)
            Text(String(Notation.octave(note)))
                .font(.system(size: 10)).foregroundStyle(Theme.ghost)
        }
    }
}

// MARK: - Intonation check

/// Guided check per string: open string (or 12th-fret harmonic), then the fretted 12th fret.
/// The difference from a perfect octave tells which way to move the saddle.
final class IntonationModel: ObservableObject {
    enum Step { case open, fretted, done }
    @Published var string = 0
    @Published var step = Step.open
    @Published var progress = 0.0
    @Published var results: [Int: Double] = [:]
    @Published var live: Double?
    private var openMidi: Double?
    private var samples: [(t: Date, m: Double)] = []

    func select(_ s: Int) {
        string = s
        step = .open
        openMidi = nil
        samples = []
        progress = 0
        live = nil
    }

    func expected(_ strings: [Int]) -> Double {
        guard string < strings.count else { return 60 }
        return step == .open ? Double(strings[string]) : (openMidi ?? Double(strings[string])) + 12
    }

    func feed(_ r: Reading, strings: [Int]) {
        guard step != .done, string < strings.count else { return }
        let want = expected(strings)
        guard r.hasSignal, abs(r.midi - want) < 0.7 else {
            samples = []
            progress = 0
            live = r.hasSignal ? (r.midi - want) * 100 : nil
            return
        }
        live = (r.midi - want) * 100
        let now = Date()
        samples.append((now, r.midi))
        // Hold a steady note for ~0.8 s; the median of the settled part is the measurement.
        let span = now.timeIntervalSince(samples[0].t)
        progress = min(1, span / 0.8)
        guard span >= 0.8 else { return }
        let settled = samples.suffix(max(3, samples.count * 2 / 3)).map(\.m).sorted()
        let m = settled[settled.count / 2]
        samples = []
        progress = 0
        if step == .open {
            openMidi = m
            step = .fretted
        } else {
            results[string] = (m - openMidi! - 12) * 100
            step = .done
        }
    }
}

struct IntonationView: View {
    @ObservedObject var tuner = TunerModel.shared
    @ObservedObject var prefs = Prefs.shared
    @StateObject private var model = IntonationModel()

    var body: some View {
        let strings = prefs.tuning.notes
        let name = strings.indices.contains(model.string) ? prefs.notation.name(midi: strings[model.string]) : ""
        VStack(spacing: 16) {
            Text(stepTitle(name))
                .font(.system(size: 20, weight: .light))
            Text(stepDetail)
                .font(.system(size: 12)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            if model.step == .done, let r = model.results[model.string] {
                Text(centsText(r))
                    .font(.system(size: 44, weight: .thin).monospacedDigit())
                    .foregroundStyle(Theme.tint(cents: r, tolerance: 3, active: true))
                Text(advice(r)).font(.system(size: 13, weight: .medium))
                HStack(spacing: 4) {
                    TextChoice(title: tr("Measure again"), selected: false, size: 11) { model.select(model.string) }
                    if model.string + 1 < strings.count {
                        TextChoice(title: tr("Next string"), selected: true, size: 11) { model.select(model.string + 1) }
                    }
                }
            } else {
                NeedleMeter(cents: model.live ?? 0, active: model.live != nil, tolerance: 3, height: 64)
                    .frame(maxWidth: 480)
                    .padding(.horizontal, 40)
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.good)
                    .frame(width: 160)
                    .opacity(model.progress > 0 ? 1 : 0)
            }
            HStack(spacing: 16) {
                ForEach(strings.indices, id: \.self) { i in
                    Button { model.select(i) } label: {
                        VStack(spacing: 4) {
                            Text(prefs.notation.name(pc: strings[i]))
                                .font(.system(size: 13, weight: model.string == i ? .semibold : .regular))
                                .frame(width: 34, height: 34)
                                .background(Circle().strokeBorder(model.string == i ? Theme.text : Theme.line,
                                                                  lineWidth: model.string == i ? 1.5 : 1))
                            Text(model.results[i].map(centsText) ?? " ")
                                .font(.system(size: 9, weight: .medium).monospacedDigit())
                                .foregroundStyle(model.results[i].map { Theme.tint(cents: $0, tolerance: 3, active: true) } ?? Theme.ghost)
                        }
                        .foregroundStyle(Theme.text)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
        .onReceive(tuner.$reading) { model.feed($0, strings: strings) }
        .onAppear { tuner.intonationActive = true }
        .onDisappear { tuner.intonationActive = false }
        .onChange(of: prefs.tuning.id) { _ in model.results = [:]; model.select(0) }
    }

    private func stepTitle(_ name: String) -> String {
        switch model.step {
        case .open: return trf("Play the open %@ string", name)
        case .fretted: return trf("Now the 12th fret on %@", name)
        case .done: return trf("%@ string", name)
        }
    }

    private var stepDetail: String {
        switch model.step {
        case .open: return tr("Tune the string first. Let it ring steadily; Chorden measures it exactly.")
        case .fretted: return tr("Fret the 12th fret with normal pressure and let it ring.")
        case .done: return tr("Compared with a perfect octave of the open string.")
        }
    }

    private func advice(_ cents: Double) -> String {
        if abs(cents) <= 3 { return tr("Intonation is good") }
        return cents > 0 ? tr("Sharp: move the saddle back, away from the neck")
                         : tr("Flat: move the saddle forward, toward the neck")
    }
}

// MARK: - Screens

struct TunerView: View {
    @ObservedObject var tuner = TunerModel.shared
    @ObservedObject var prefs = Prefs.shared

    /// All-strings and intonation only make sense for an instrument (intonation: fretted ones).
    private var function: TunerFunction {
        guard prefs.targetMode == .instrument, !prefs.instrument.isKeyboard else { return .single }
        if prefs.tunerFunction == .intonation && prefs.instrument.frets == 0 { return .single }
        return prefs.tunerFunction
    }

    var body: some View {
        let r = tuner.reading
        VStack(spacing: 0) {
            HStack {
                InstrumentPicker()
                Spacer()
                if prefs.targetMode == .instrument && !prefs.instrument.isKeyboard {
                    HStack(spacing: 2) {
                        TextChoice(title: tr("One string"), selected: function == .single, size: 11) { prefs.tunerFunction = .single }
                        TextChoice(title: tr("All strings"), selected: function == .all, size: 11) { prefs.tunerFunction = .all }
                        if prefs.instrument.frets > 0 {
                            TextChoice(title: tr("Intonation"), selected: function == .intonation, size: 11) {
                                prefs.tunerFunction = .intonation
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 6)

            Spacer(minLength: 12)
            if tuner.status == .denied || tuner.status.isFailure {
                StatusMessage()
            } else {
                switch function {
                case .single:
                    let makam = makamSpelling(r)
                    NoteDisplay(midi: makam?.natural ?? r.target, color: noteColor(r), size: 128, accidental: makam?.accidental)
                    Hint().padding(.top, 2)
                    Meter(height: 76)
                        .frame(maxWidth: 560)
                        .padding(.horizontal, 40)
                        .padding(.top, 30)
                    Readout().padding(.top, 12)
                case .all:
                    PolyView()
                case .intonation:
                    IntonationView()
                }
            }
            Spacer(minLength: 16)

            if function == .single {
                HStack(spacing: 14) {
                    if prefs.targetMode != .chromatic { StringsRow() }
                    ReferenceButton()
                }
                .padding(.bottom, 22)
            }

            HStack(spacing: 2) {
                if function == .single {
                    ForEach(DisplayMode.allCases, id: \.self) { m in
                        TextChoice(title: tr(m.rawValue.capitalized), selected: prefs.display == m, size: 11) { prefs.display = m }
                    }
                }
                Spacer()
                Text(String(format: "A4 = %g Hz", prefs.a4))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.ghost)
                Circle()
                    .fill(tuner.status == .listening ? Theme.good : Theme.ghost)
                    .frame(width: 6, height: 6)
                    .opacity(tuner.status == .listening ? 0.35 + 0.65 * r.level : 1)
                    .padding(.leading, 6)
                    .help(tuner.status == .listening ? tr("Listening") : tr("Microphone off"))
            }
            .frame(height: 24)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .onAppear { tuner.polyActive = function == .all }
        .onDisappear { tuner.polyActive = false }
        .onChange(of: function) { tuner.polyActive = $0 == .all }
    }

    private func noteColor(_ r: Reading) -> Color {
        if !r.hasSignal { return r.target == nil ? Theme.ghost : Theme.dim.opacity(0.6) }
        return r.inTune ? Theme.good : Theme.text
    }
}

/// The menu bar popover: the same tuner, compact.
struct MiniTunerView: View {
    @ObservedObject var tuner = TunerModel.shared
    @ObservedObject var prefs = Prefs.shared
    var openApp: () -> Void

    var body: some View {
        let r = tuner.reading
        VStack(spacing: 0) {
            HStack {
                InstrumentPicker(size: 12)
                Spacer()
                Button(action: openApp) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tr("Open Chorden"))
            }
            if tuner.status == .denied || tuner.status.isFailure {
                StatusMessage().frame(height: 190)
            } else {
                let makam = makamSpelling(r)
                NoteDisplay(midi: makam?.natural ?? r.target,
                            color: r.hasSignal ? (r.inTune ? Theme.good : Theme.text) : Theme.dim.opacity(0.6),
                            size: 72, accidental: makam?.accidental)
                    .padding(.top, 10)
                Meter(height: 52, allowTrace: false)
                    .padding(.top, 8)
                Readout(size: 11).padding(.top, 6)
            }
            if prefs.targetMode != .chromatic {
                let count = prefs.targetMode == .makam ? tuner.makamDegrees.count : prefs.tuning.notes.count
                HStack(spacing: 8) {
                    // Fit 7- and 8-item rows into the popover's width.
                    StringsRow(size: count >= 8 ? 24 : count == 7 ? 26 : 30)
                    ReferenceButton()
                }
                .padding(.top, 14)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// The tuner's target spelled as its makam degree (B♭¹ …), or nil outside makam mode.
func makamSpelling(_ r: Reading) -> (natural: Int, accidental: String)? {
    let prefs = Prefs.shared
    guard prefs.targetMode == .makam, r.target != nil else { return nil }
    let scale = Scales.scale(prefs.makamID)
    guard let i = r.string else {
        let sp = Scales.makamSpelling(r.targetPitch)
        return (sp.natural, sp.accidental)
    }
    return Scales.degreeSpelling(scale, i, pitch: r.targetPitch, karar: prefs.makamRoot)
}

extension TunerStatus {
    var isFailure: Bool { if case .failed = self { return true } else { return false } }
}
