import AVFoundation
import SwiftUI

// What the user keeps: saved progressions (with their loop settings) and Sing & Find takes (notes, every
// choice made on them, and the voice). Stored as one small JSON file in ~/Library/Application Support/Chorden,
// with each take's voice next to it as lossless audio (Takes/<id>.caf).

struct SavedProgression: Codable, Identifiable, Equatable {
    var id = UUID()
    /// nil: named after the key and mood.
    var name: String?
    var date = Date()
    var progression: Progression
    var bpm: Double
    var pattern: String
    var drums: String
    var beats: Int
    var swing: Bool
    /// Backing band styles; nil in progressions saved before there was a band (they play Auto).
    var bass: String?
    var keys: String?

    func sameSettings(_ p: Prefs) -> Bool {
        bpm == p.progressionBPM && pattern == p.progressionPattern && drums == p.progressionDrums
            && beats == p.progressionBeats && swing == p.progressionSwing
            && (bass ?? "auto") == p.progressionBass && (keys ?? "auto") == p.progressionKeys
    }
}

struct SavedTake: Codable, Identifiable {
    var id = UUID()
    var name: String?
    var date = Date()
    /// Notes as segmented, before the singer's tuning is taken into account.
    var notes: [SungNote]
    var length: Double
    var clicked: Bool
    var tempo: Double?
    var tempoSet: Bool
    var estimate: Double?
    /// The beats as followed through the singing, so the bars come back exactly as they were.
    var beats: [Double]
    var shift: Int
    var keyChoice: SongKey?
    /// The key found, for the name.
    var key: SongKey?
    var transpose: Int
    /// Chords picked by hand, by slot.
    var picks: [Int: ChordSlot.Option]
    var beatsPerBar: Int
    var chordEvery: Int
    var chordStyle: Int
    /// Sample rate of the voice file (nil: no voice).
    var voiceRate: Double?
}

final class Library: ObservableObject {
    /// Where everything is kept. Tests point it elsewhere before first use of `shared`.
    nonisolated(unsafe) static var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Chorden", isDirectory: true)
    static let shared = Library(directory: directory)

    @Published private(set) var progressions: [SavedProgression] = []
    @Published private(set) var takes: [SavedTake] = []

    let directory: URL
    private var file: URL { directory.appendingPathComponent("library.json") }
    private var audio: URL { directory.appendingPathComponent("Takes", isDirectory: true) }

    private struct Stored: Codable {
        var version = 1
        var progressions: [Lossy<SavedProgression>]
        var takes: [Lossy<SavedTake>]
    }

    /// One unreadable record is skipped instead of losing the whole file.
    private struct Lossy<T: Codable>: Codable {
        let value: T?
        init(_ v: T) { value = v }
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
        func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
    }

    init(directory: URL) {
        self.directory = directory
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let s = try? decoder.decode(Stored.self, from: data) else {
            // Keep a damaged file aside rather than overwriting it with an empty library.
            let aside = directory.appendingPathComponent("library-damaged-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: file, to: aside)
            return
        }
        progressions = s.progressions.compactMap(\.value)
        takes = s.takes.compactMap(\.value)
    }

    private func write() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let s = Stored(progressions: progressions.map(Lossy.init), takes: takes.map(Lossy.init))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(s).write(to: file, options: .atomic)
        } catch {
            NSLog("Chorden: could not save the library: \(error)")
        }
    }

    // MARK: Progressions

    /// The saved one with these chords, if any.
    func saved(_ p: Progression) -> SavedProgression? { progressions.first { $0.progression == p } }

    /// Saves the progression with the current loop settings; saving the same chords again updates them.
    @discardableResult
    func save(_ p: Progression, prefs: Prefs = .shared) -> SavedProgression {
        var s = saved(p) ?? SavedProgression(progression: p, bpm: 0, pattern: "", drums: "", beats: 4, swing: false)
        s.bpm = prefs.progressionBPM
        s.pattern = prefs.progressionPattern
        s.drums = prefs.progressionDrums
        s.beats = prefs.progressionBeats
        s.swing = prefs.progressionSwing
        s.bass = prefs.progressionBass
        s.keys = prefs.progressionKeys
        progressions.removeAll { $0.id == s.id }
        progressions.insert(s, at: 0)
        write()
        return s
    }

    func rename(progression id: UUID, to name: String) {
        guard let i = progressions.firstIndex(where: { $0.id == id }) else { return }
        progressions[i].name = Self.clean(name)
        write()
    }

    func delete(progression id: UUID) {
        progressions.removeAll { $0.id == id }
        write()
    }

    // MARK: Takes

    /// Saves a take (replacing the one with the same id) and its voice. Keeps a name given earlier.
    func save(_ take: SavedTake, voice: SampleNote?) {
        var t = take
        if let old = takes.first(where: { $0.id == t.id }) { t.name = old.name }
        t.voiceRate = nil
        if let v = voice, !v.data.isEmpty, writeAudio(v, to: audioURL(t.id)) { t.voiceRate = v.rate }
        if t.voiceRate == nil { try? FileManager.default.removeItem(at: audioURL(t.id)) }
        takes.removeAll { $0.id == t.id }
        takes.insert(t, at: 0)
        write()
    }

    func rename(take id: UUID, to name: String) {
        guard let i = takes.firstIndex(where: { $0.id == id }) else { return }
        takes[i].name = Self.clean(name)
        write()
    }

    func delete(take id: UUID) {
        takes.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: audioURL(id))
        write()
    }

    /// The take's voice (nil if it had none, or the file is gone).
    func voice(of take: SavedTake) -> SampleNote? {
        guard take.voiceRate != nil, let f = try? AVAudioFile(forReading: audioURL(take.id)),
              let buffer = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)),
              (try? f.read(into: buffer)) != nil, let ch = buffer.floatChannelData else { return nil }
        let data = Array(UnsafeBufferPointer(start: ch[0], count: Int(buffer.frameLength)))
        return data.isEmpty ? nil : SampleNote(midi: 0, data: data, rate: f.processingFormat.sampleRate, level: 1)
    }

    func audioURL(_ id: UUID) -> URL { audio.appendingPathComponent(id.uuidString + ".caf") }

    /// Apple Lossless in CAF: exact, and about half the size of plain PCM.
    private func writeAudio(_ v: SampleNote, to url: URL) -> Bool {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: v.rate,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitDepthHintKey: 16]
        guard let format = AVAudioFormat(standardFormatWithSampleRate: v.rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(v.data.count)) else { return false }
        buffer.frameLength = AVAudioFrameCount(v.data.count)
        v.data.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: v.data.count) }
        do {
            try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
            let tmp = audio.appendingPathComponent(".\(UUID().uuidString).caf")
            do {
                // Scoped so the file is closed (and finished) before it's moved into place.
                let f = try AVAudioFile(forWriting: tmp, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
                try f.write(from: buffer)
            }
            _ = try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: tmp, to: url)
            return true
        } catch {
            NSLog("Chorden: could not save the take's audio: \(error)")
            return false
        }
    }

    private static func clean(_ name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? nil : n
    }
}

// MARK: - Loading

extension ProgressionPlayer {
    /// Replaces the progression and its loop settings; a playing loop starts again from the top.
    func load(_ s: SavedProgression) {
        let was = playing
        stop()
        let prefs = Prefs.shared
        prefs.progressionBPM = min(220, max(40, s.bpm))
        if StrumPattern(rawValue: s.pattern) != nil { prefs.progressionPattern = s.pattern }
        if DrumPattern(rawValue: s.drums) != nil { prefs.progressionDrums = s.drums }
        if [2, 4, 8].contains(s.beats) { prefs.progressionBeats = s.beats }
        prefs.progressionSwing = s.swing
        prefs.progressionBass = BassStyle(rawValue: s.bass ?? "") == nil ? "auto" : s.bass!
        prefs.progressionKeys = KeysStyle(rawValue: s.keys ?? "") == nil ? "auto" : s.keys!
        progression = s.progression
        prefs.progressionLength = min(max(s.progression.steps.count, Progressions.lengths.lowerBound), Progressions.lengths.upperBound)
        if was { start() }
    }
}

// MARK: - Names

extension SavedProgression {
    func title(_ prefs: Prefs) -> String {
        name ?? prefs.notation.name(pc: progression.key) + " " + (progression.minor ? tr("minor") : tr("major"))
            + " · " + tr(progression.mood)
    }

    func chords(_ prefs: Prefs) -> String {
        let p = progression
        let names = p.steps.indices.prefix(6).map { ChordsView.name(p.root($0), p.steps[$0].quality, prefs.notation) }
        return names.joined(separator: " ") + (p.steps.count > 6 ? " …" : "")
    }
}

extension SavedTake {
    func title(_ prefs: Prefs) -> String {
        if let name { return name }
        let k = (keyChoice ?? key).map { k -> String in
            let root = ((k.root + transpose) % 12 + 12) % 12
            return prefs.notation.name(pc: root) + " " + (k.minor ? tr("minor") : tr("major"))
        }
        return [k, tempo.map { "\(Int($0.rounded())) BPM" }].compactMap { $0 }.joined(separator: " · ")
    }

    var when: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Prefs.shared.language == .tr ? "tr_TR" : "en_US")
        f.setLocalizedDateFormatFromTemplate("dMMM HH:mm")
        return f.string(from: date)
    }
}

// MARK: - UI

/// A saved item in a dropdown: click to open it; on hover, rename (inline) and delete (click twice).
struct LibraryRow: View {
    let title: String
    var detail: String = ""
    let selected: Bool
    let open: () -> Void
    let rename: (String) -> Void
    let delete: () -> Void
    @State private var hover = false
    @State private var editing = false
    @State private var armed = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.good)
                .opacity(selected ? 1 : 0)
                .frame(width: 10)
            if editing {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($focused)
                    .onSubmit(commit)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.line.opacity(0.6), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .frame(maxWidth: .infinity)
                icon("checkmark", Theme.text, help: tr("Save"), action: commit)
            } else {
                Text(title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 14)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .fixedSize()
                HStack(spacing: 0) {
                    icon("pencil", Theme.dim, help: tr("Rename")) {
                        text = title
                        editing = true
                        DispatchQueue.main.async { focused = true }
                    }
                    icon(armed ? "trash.fill" : "trash", armed ? Theme.off : Theme.dim,
                         help: armed ? tr("Click again to delete") : tr("Delete")) {
                        if armed { delete() } else { armed = true }
                    }
                }
                .opacity(hover ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 28)
        .background(hover && !editing ? Theme.line.opacity(0.75) : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onHover { h in
            hover = h
            if !h { armed = false }
        }
        .onTapGesture {
            guard !editing else { return }
            open()
            Dropdowns.shared.closeAll()
        }
    }

    private func commit() {
        rename(text)
        editing = false
    }

    private func icon(_ name: String, _ color: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The saved progressions, in the Progressions header.
struct SavedProgressionsMenu: View {
    @ObservedObject var library = Library.shared
    @ObservedObject var player = ProgressionPlayer.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        if !library.progressions.isEmpty {
            Dropdown {
                Text(tr("My progressions")).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text)
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(library.progressions) { s in
                        LibraryRow(title: s.title(prefs), detail: s.chords(prefs), selected: s.progression == player.progression) {
                            player.load(s)
                        } rename: { library.rename(progression: s.id, to: $0) } delete: {
                            library.delete(progression: s.id)
                            Dropdowns.shared.closeAll()
                        }
                    }
                }
                .frame(minWidth: 340, maxWidth: 420)
            }
            .help(tr("Open a saved progression"))
        }
    }
}

/// The saved takes, in the Sing & Find header.
struct SavedTakesMenu: View {
    @ObservedObject var library = Library.shared
    @ObservedObject var model = SingModel.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        if !library.takes.isEmpty {
            Dropdown {
                Text(tr("My takes")).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text)
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(library.takes) { t in
                        LibraryRow(title: t.title(prefs), detail: t.when, selected: model.takeID == t.id) {
                            model.open(t)
                        } rename: { library.rename(take: t.id, to: $0) } delete: {
                            if model.takeID == t.id { model.forgetSaved() }
                            library.delete(take: t.id)
                            Dropdowns.shared.closeAll()
                        }
                    }
                }
                .frame(minWidth: 320, maxWidth: 420)
            }
            .help(tr("Open a saved take"))
        }
    }
}
