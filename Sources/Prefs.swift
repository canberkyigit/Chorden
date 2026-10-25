import Foundation

enum DisplayMode: String, CaseIterable { case needle, strobe, trace }
enum ChordView: String, CaseIterable { case shapes, neck }
enum DotLabel: String, CaseIterable { case fingers, notes, intervals }
/// What the tuner tunes to: an instrument's strings, any semitone, or the degrees of a makam.
enum TargetMode: String { case instrument, chromatic, makam }
/// Single-string tuning, all strings at once, or the intonation check.
enum TunerFunction: String, CaseIterable { case single, all, intonation }
enum Language: String, CaseIterable { case en, tr }
enum ChordsMode: String, CaseIterable { case library, progressions }
enum AppearanceMode: String, CaseIterable { case system, light, dark }

/// User settings, persisted to UserDefaults as they change.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var language: Language { didSet { d.set(language.rawValue, forKey: "language") } }
    @Published var appearance: AppearanceMode { didSet { d.set(appearance.rawValue, forKey: "appearance") } }

    // MARK: Tuner
    @Published var instrumentID: String { didSet { d.set(instrumentID, forKey: "instrument") } }
    /// Selected tuning per instrument, so switching instruments keeps each one's tuning.
    @Published var tuningIDs: [String: String] { didSet { d.set(tuningIDs, forKey: "tunings") } }
    @Published var targetMode: TargetMode { didSet { d.set(targetMode.rawValue, forKey: "targetMode") } }
    @Published var tunerFunction: TunerFunction { didSet { d.set(tunerFunction.rawValue, forKey: "tunerFunction") } }
    @Published var makamID: String { didSet { d.set(makamID, forKey: "makam") } }
    /// Karar (tonic) pitch class for the makam tuner.
    @Published var makamRoot: Int { didSet { d.set(makamRoot, forKey: "makamRoot") } }
    @Published var a4: Double { didSet { d.set(a4, forKey: "a4") } }
    /// ± cents that count as "in tune".
    @Published var tolerance: Double { didSet { d.set(tolerance, forKey: "tolerance") } }
    @Published var notation: Notation {
        didSet {
            d.set(notation.accidental.rawValue, forKey: "accidental")
            d.set(notation.naming.rawValue, forKey: "naming")
        }
    }
    @Published var display: DisplayMode { didSet { d.set(display.rawValue, forKey: "display") } }
    /// nil = system default input.
    @Published var inputUID: String? { didSet { d.set(inputUID, forKey: "inputUID") } }
    /// 0 = loudest channel, 1… = a fixed interface input.
    @Published var inputChannel: Int { didSet { d.set(inputChannel, forKey: "inputChannel") } }
    /// Signals quieter than this (dBFS) are ignored.
    @Published var gate: Double { didSet { d.set(gate, forKey: "gate") } }
    /// User-made tunings per instrument id.
    @Published var customTunings: [String: [Tuning]] {
        didSet { d.set(try? JSONEncoder().encode(customTunings), forKey: "customTunings") }
    }
    @Published var favoriteTunings: Set<String> { didSet { d.set(Array(favoriteTunings), forKey: "favoriteTunings") } }

    // MARK: Chords
    @Published var chordRoot: Int { didSet { d.set(chordRoot, forKey: "chordRoot") } }
    @Published var chordQuality: String { didSet { d.set(chordQuality, forKey: "chordQuality") } }
    @Published var chordView: ChordView { didSet { d.set(chordView.rawValue, forKey: "chordView") } }
    @Published var dotLabel: DotLabel { didSet { d.set(dotLabel.rawValue, forKey: "dotLabel") } }
    @Published var chordsMode: ChordsMode { didSet { d.set(chordsMode.rawValue, forKey: "chordsMode") } }
    /// "root|quality" keys.
    @Published var favoriteChords: [String] { didSet { d.set(favoriteChords, forKey: "favoriteChords") } }
    @Published var progressionLength: Int { didSet { d.set(progressionLength, forKey: "progressionLength") } }
    @Published var progressionMood: String { didSet { d.set(progressionMood, forKey: "progressionMood") } }
    @Published var progressionBPM: Double { didSet { d.set(progressionBPM, forKey: "progressionBPM") } }
    /// Beats each chord lasts: 2 (half bar), 4 (one bar) or 8 (two bars).
    @Published var progressionBeats: Int { didSet { d.set(progressionBeats, forKey: "progressionBeats") } }
    @Published var progressionPattern: String { didSet { d.set(progressionPattern, forKey: "progressionPattern") } }
    @Published var progressionDrums: String { didSet { d.set(progressionDrums, forKey: "progressionDrums") } }
    @Published var progressionLoop: Bool { didSet { d.set(progressionLoop, forKey: "progressionLoop") } }
    @Published var progressionSwing: Bool { didSet { d.set(progressionSwing, forKey: "progressionSwing") } }
    /// Backing band styles (BassStyle / KeysStyle raw values); "auto" follows the drums and rhythm.
    @Published var progressionBass: String { didSet { d.set(progressionBass, forKey: "progressionBass") } }
    @Published var progressionKeys: String { didSet { d.set(progressionKeys, forKey: "progressionKeys") } }

    // MARK: Scales
    @Published var scaleID: String { didSet { d.set(scaleID, forKey: "scale") } }
    @Published var scaleRoot: Int { didSet { d.set(scaleRoot, forKey: "scaleRoot") } }
    /// 0 = whole neck, n = the n-th position box.
    @Published var scalePosition: Int { didSet { d.set(scalePosition, forKey: "scalePosition") } }

    // MARK: Metronome
    @Published var bpm: Double { didSet { d.set(bpm, forKey: "bpm") } }
    @Published var beatsPerBar: Int { didSet { d.set(beatsPerBar, forKey: "beatsPerBar") } }
    @Published var subdivision: Int { didSet { d.set(subdivision, forKey: "subdivision") } }
    /// Sing tab: one chord per bar (1) or per half bar (2), and whether the metronome clicks along.
    @Published var singChordEvery: Int { didSet { d.set(singChordEvery, forKey: "singChordEvery") } }
    @Published var singClick: Bool { didSet { d.set(singClick, forKey: "singClick") } }
    /// Play the recorded voice along with the chords.
    @Published var singPlayVoice: Bool { didSet { d.set(singPlayVoice, forKey: "singPlayVoice") } }
    /// Play the sung melody on the current instrument.
    @Published var singPlayMelody: Bool { didSet { d.set(singPlayMelody, forKey: "singPlayMelody") } }
    /// Which chords Sing & Find may use: 0 the four everyday ones, 1 the whole key, 2 also 7ths, 9ths and 6ths.
    @Published var singChords: Int { didSet { d.set(singChords, forKey: "singChords") } }
    @Published var pluckSound: PluckSound { didSet { d.set(pluckSound.rawValue, forKey: "pluckSound") } }
    @Published var metronomeSound: MetronomeSound { didSet { d.set(metronomeSound.rawValue, forKey: "metronomeSound") } }

    private init() {
        let systemTurkish = Locale.preferredLanguages.first?.hasPrefix("tr") ?? false
        language = Language(rawValue: d.string(forKey: "language") ?? "") ?? (systemTurkish ? .tr : .en)
        appearance = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        instrumentID = d.string(forKey: "instrument") ?? "guitar6"
        tuningIDs = d.dictionary(forKey: "tunings") as? [String: String] ?? [:]
        // Older builds stored a "chromatic" flag.
        targetMode = TargetMode(rawValue: d.string(forKey: "targetMode") ?? "")
            ?? (d.bool(forKey: "chromatic") ? .chromatic : .instrument)
        tunerFunction = TunerFunction(rawValue: d.string(forKey: "tunerFunction") ?? "") ?? .single
        makamID = d.string(forKey: "makam") ?? "rast"
        makamRoot = d.object(forKey: "makamRoot") as? Int ?? 7
        a4 = d.object(forKey: "a4") as? Double ?? 440
        tolerance = d.object(forKey: "tolerance") as? Double ?? 2
        notation = Notation(accidental: Accidental(rawValue: d.string(forKey: "accidental") ?? "") ?? .sharp,
                            naming: NoteNaming(rawValue: d.string(forKey: "naming") ?? "") ?? .letters)
        display = DisplayMode(rawValue: d.string(forKey: "display") ?? "") ?? .needle
        inputUID = d.string(forKey: "inputUID")
        inputChannel = d.integer(forKey: "inputChannel")
        gate = d.object(forKey: "gate") as? Double ?? -60
        customTunings = (d.data(forKey: "customTunings")).flatMap { try? JSONDecoder().decode([String: [Tuning]].self, from: $0) } ?? [:]
        favoriteTunings = Set(d.stringArray(forKey: "favoriteTunings") ?? [])

        chordRoot = d.integer(forKey: "chordRoot")
        chordQuality = d.string(forKey: "chordQuality") ?? ""
        chordView = ChordView(rawValue: d.string(forKey: "chordView") ?? "") ?? .shapes
        dotLabel = DotLabel(rawValue: d.string(forKey: "dotLabel") ?? "") ?? .fingers
        chordsMode = ChordsMode(rawValue: d.string(forKey: "chordsMode") ?? "") ?? .library
        favoriteChords = d.stringArray(forKey: "favoriteChords") ?? []
        progressionLength = d.object(forKey: "progressionLength") as? Int ?? 4
        progressionMood = d.string(forKey: "progressionMood") ?? ""
        progressionBPM = d.object(forKey: "progressionBPM") as? Double ?? 90
        progressionBeats = d.object(forKey: "progressionBeats") as? Int ?? 4
        progressionPattern = d.string(forKey: "progressionPattern") ?? "downUp"
        progressionDrums = d.string(forKey: "progressionDrums") ?? "off"
        progressionLoop = d.object(forKey: "progressionLoop") as? Bool ?? true
        progressionSwing = d.bool(forKey: "progressionSwing")
        progressionBass = d.string(forKey: "progressionBass") ?? "auto"
        progressionKeys = d.string(forKey: "progressionKeys") ?? "auto"

        scaleID = d.string(forKey: "scale") ?? "major"
        scaleRoot = d.integer(forKey: "scaleRoot")
        scalePosition = d.integer(forKey: "scalePosition")

        bpm = d.object(forKey: "bpm") as? Double ?? 100
        beatsPerBar = d.object(forKey: "beatsPerBar") as? Int ?? 4
        subdivision = d.object(forKey: "subdivision") as? Int ?? 1
        singChordEvery = d.object(forKey: "singChordEvery") as? Int ?? 1
        singClick = d.bool(forKey: "singClick")
        singPlayVoice = d.object(forKey: "singPlayVoice") as? Bool ?? true
        singPlayMelody = d.bool(forKey: "singPlayMelody")
        singChords = d.object(forKey: "singChords") as? Int ?? (d.bool(forKey: "singRich") ? 2 : 1)
        pluckSound = PluckSound(rawValue: d.string(forKey: "pluckSound") ?? "") ?? .auto
        metronomeSound = MetronomeSound(rawValue: d.string(forKey: "metronomeSound") ?? "") ?? .classic
    }

    var chromatic: Bool { targetMode == .chromatic }
    var instrument: Instrument { Catalog.instrument(instrumentID) }

    /// Built-in tunings plus the user's own (listed first).
    func tunings(for instrument: Instrument) -> [Tuning] { (customTunings[instrument.id] ?? []) + instrument.tunings }

    var tuning: Tuning {
        let inst = instrument
        return tunings(for: inst).first { $0.id == tuningIDs[inst.id] } ?? inst.tunings[0]
    }

    func select(tuning: Tuning, of instrument: Instrument) {
        instrumentID = instrument.id
        tuningIDs[instrument.id] = tuning.id
        targetMode = .instrument
    }

    func isCustom(_ t: Tuning) -> Bool { t.id.hasPrefix("custom.") }

    func saveCustom(_ t: Tuning, for instrument: Instrument) {
        var list = customTunings[instrument.id] ?? []
        if let i = list.firstIndex(where: { $0.id == t.id }) { list[i] = t } else { list.insert(t, at: 0) }
        customTunings[instrument.id] = list
        select(tuning: t, of: instrument)
    }

    func deleteCustom(_ t: Tuning, for instrument: Instrument) {
        customTunings[instrument.id]?.removeAll { $0.id == t.id }
        favoriteTunings.remove(t.id)
        if tuningIDs[instrument.id] == t.id { tuningIDs[instrument.id] = instrument.tunings[0].id }
    }

    func toggleFavorite(_ t: Tuning) {
        if favoriteTunings.contains(t.id) { favoriteTunings.remove(t.id) } else { favoriteTunings.insert(t.id) }
    }

    var chordKey: String { "\(chordRoot)|\(chordQuality)" }

    func toggleFavoriteChord() {
        if let i = favoriteChords.firstIndex(of: chordKey) { favoriteChords.remove(at: i) } else { favoriteChords.append(chordKey) }
    }
}
