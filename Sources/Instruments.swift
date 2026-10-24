import Foundation

struct Tuning: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    /// MIDI notes in the order the strings are drawn, left to right (thickest / top string first).
    let notes: [Int]
}

struct Instrument: Identifiable {
    let id: String
    let name: String
    let group: String
    let tunings: [Tuning]
    /// Frets shown on the neck; 0 for fretless instruments.
    let frets: Int
    /// Chord shapes make sense here (fretted, equal-tempered).
    let hasChords: Bool
    /// Strings are ordered by pitch, so the lowest sounding string should carry the chord's root.
    /// False for re-entrant instruments (ukulele, banjo).
    let pitchOrdered: Bool
    /// Fret stretch a hand can cover in one shape (3 = four frets).
    let span: Int
    /// Strings that are only ever played open in chords (banjo's short 5th string).
    let drones: Set<Int>

    var stringCount: Int { tunings[0].notes.count }
    /// Piano: keys instead of strings (keyboard views, no string targets).
    var isKeyboard: Bool { group == "Keyboard" }

    func tuning(_ id: String?) -> Tuning { tunings.first { $0.id == id } ?? tunings[0] }
}

enum Catalog {
    static let groups = ["Guitar", "Bass", "Keyboard", "Bowed", "Folk", "Turkish & Middle Eastern"]

    static func instrument(_ id: String?) -> Instrument { all.first { $0.id == id } ?? all[0] }

    private static func t(_ id: String, _ name: String, _ notes: String) -> Tuning {
        Tuning(id: id, name: name, notes: notes.split(separator: " ").map { Music.parse(String($0)) })
    }

    private static func inst(_ id: String, _ name: String, _ group: String, frets: Int = 22, chords: Bool = true,
                             pitchOrdered: Bool = true, span: Int = 3, drones: Set<Int> = [],
                             _ tunings: [(String, String)]) -> Instrument {
        Instrument(id: id, name: name, group: group,
                   tunings: tunings.enumerated().map { i, tn in t("\(id).\(i)", tn.0, tn.1) },
                   frets: frets, hasChords: chords, pitchOrdered: pitchOrdered, span: span, drones: drones)
    }

    static let all: [Instrument] = [
        inst("guitar6", "Guitar", "Guitar", [
            ("Standard", "E2 A2 D3 G3 B3 E4"),
            ("Half Step Down (E♭)", "Eb2 Ab2 Db3 Gb3 Bb3 Eb4"),
            ("Whole Step Down (D)", "D2 G2 C3 F3 A3 D4"),
            ("C♯ Standard", "C#2 F#2 B2 E3 G#3 C#4"),
            ("C Standard", "C2 F2 Bb2 Eb3 G3 C4"),
            ("B Standard", "B1 E2 A2 D3 F#3 B3"),
            ("A Standard", "A1 D2 G2 C3 E3 A3"),
            ("Drop D", "D2 A2 D3 G3 B3 E4"),
            ("Drop C♯", "C#2 G#2 C#3 F#3 A#3 D#4"),
            ("Drop C", "C2 G2 C3 F3 A3 D4"),
            ("Drop B", "B1 F#2 B2 E3 G#3 C#4"),
            ("Drop B♭", "Bb1 F2 Bb2 Eb3 G3 C4"),
            ("Drop A", "A1 E2 A2 D3 F#3 B3"),
            ("Double Drop D", "D2 A2 D3 G3 B3 D4"),
            ("DADGAD", "D2 A2 D3 G3 A3 D4"),
            ("Open D", "D2 A2 D3 F#3 A3 D4"),
            ("Open D Minor", "D2 A2 D3 F3 A3 D4"),
            ("Open E", "E2 B2 E3 G#3 B3 E4"),
            ("Open G", "D2 G2 D3 G3 B3 D4"),
            ("Open G Minor", "D2 G2 D3 G3 Bb3 D4"),
            ("Open A", "E2 A2 E3 A3 C#4 E4"),
            ("Open C", "C2 G2 C3 G3 C4 E4"),
            ("Open C6", "C2 A2 C3 G3 C4 E4"),
            ("All Fourths", "E2 A2 D3 G3 C4 F4"),
            ("New Standard", "C2 G2 D3 A3 E4 G4"),
            ("Nashville", "E3 A3 D4 G4 B3 E4"),
        ]),
        inst("guitar7", "7-String Guitar", "Guitar", frets: 24, [
            ("Standard", "B1 E2 A2 D3 G3 B3 E4"),
            ("Half Step Down", "Bb1 Eb2 Ab2 Db3 Gb3 Bb3 Eb4"),
            ("A Standard", "A1 D2 G2 C3 F3 A3 D4"),
            ("Drop A", "A1 E2 A2 D3 G3 B3 E4"),
            ("Drop A♭", "Ab1 Eb2 Ab2 Db3 Gb3 Bb3 Eb4"),
            ("Drop G", "G1 D2 G2 C3 F3 A3 D4"),
        ]),
        inst("guitar8", "8-String Guitar", "Guitar", frets: 24, [
            ("Standard", "F#1 B1 E2 A2 D3 G3 B3 E4"),
            ("Half Step Down", "F1 Bb1 Eb2 Ab2 Db3 Gb3 Bb3 Eb4"),
            ("E Standard", "E1 A1 D2 G2 C3 F3 A3 D4"),
            ("Drop E", "E1 B1 E2 A2 D3 G3 B3 E4"),
            ("Drop D", "D1 A1 D2 G2 C3 F3 A3 D4"),
        ]),
        inst("bass4", "Bass", "Bass", frets: 21, [
            ("Standard", "E1 A1 D2 G2"),
            ("Half Step Down", "Eb1 Ab1 Db2 Gb2"),
            ("D Standard", "D1 G1 C2 F2"),
            ("Drop D", "D1 A1 D2 G2"),
            ("Drop C♯", "C#1 G#1 C#2 F#2"),
            ("Drop C", "C1 G1 C2 F2"),
            ("B Standard (BEAD)", "B0 E1 A1 D2"),
            ("Tenor (ADGC)", "A1 D2 G2 C3"),
            ("Fifths (CGDA)", "C1 G1 D2 A2"),
        ]),
        inst("bass5", "5-String Bass", "Bass", frets: 24, [
            ("Standard", "B0 E1 A1 D2 G2"),
            ("High C", "E1 A1 D2 G2 C3"),
            ("Half Step Down", "Bb0 Eb1 Ab1 Db2 Gb2"),
            ("A Standard", "A0 D1 G1 C2 F2"),
            ("Drop A", "A0 E1 A1 D2 G2"),
        ]),
        inst("bass6", "6-String Bass", "Bass", frets: 24, [
            ("Standard", "B0 E1 A1 D2 G2 C3"),
            ("Half Step Down", "Bb0 Eb1 Ab1 Db2 Gb2 B2"),
            ("Drop A", "A0 E1 A1 D2 G2 C3"),
        ]),
        inst("piano", "Piano", "Keyboard", frets: 0, [("Equal temperament", "")]),
        inst("violin", "Violin", "Bowed", frets: 0, chords: false, [
            ("Standard", "G3 D4 A4 E5"),
            ("Cross A (AEAE)", "A3 E4 A4 E5"),
            ("Cross G (GDGD)", "G3 D4 G4 D5"),
            ("Dead Man's (DDAD)", "D3 D4 A4 D5"),
            ("Calico (AEAC♯)", "A3 E4 A4 C#5"),
        ]),
        inst("viola", "Viola", "Bowed", frets: 0, chords: false, [
            ("Standard", "C3 G3 D4 A4"),
        ]),
        inst("cello", "Cello", "Bowed", frets: 0, chords: false, [
            ("Standard", "C2 G2 D3 A3"),
            ("Bach Suite No. 5", "C2 G2 D3 G3"),
        ]),
        inst("doublebass", "Double Bass", "Bowed", frets: 0, chords: false, [
            ("Orchestral", "E1 A1 D2 G2"),
            ("Solo", "F#1 B1 E2 A2"),
            ("5-String", "B0 E1 A1 D2 G2"),
            ("Fifths", "C1 G1 D2 A2"),
        ]),
        inst("ukulele", "Ukulele", "Folk", frets: 18, pitchOrdered: false, [
            ("Standard (High G)", "G4 C4 E4 A4"),
            ("Low G", "G3 C4 E4 A4"),
            ("D Tuning", "A4 D4 F#4 B4"),
        ]),
        inst("baritoneuke", "Baritone Ukulele", "Folk", frets: 19, [
            ("Standard", "D3 G3 B3 E4"),
        ]),
        inst("mandolin", "Mandolin", "Folk", frets: 20, span: 4, [
            ("Standard", "G3 D4 A4 E5"),
            ("Cross (AEAE)", "A3 E4 A4 E5"),
            ("Open G (GDGD)", "G3 D4 G4 D5"),
        ]),
        inst("banjo5", "Banjo", "Folk", frets: 22, pitchOrdered: false, drones: [0], [
            ("Open G", "G4 D3 G3 B3 D4"),
            ("Double C", "G4 C3 G3 C4 D4"),
            ("Drop C", "G4 C3 G3 B3 D4"),
            ("Open D", "F#4 D3 F#3 A3 D4"),
            ("Sawmill (G Modal)", "G4 D3 G3 C4 D4"),
        ]),
        inst("tenorbanjo", "Tenor Banjo", "Folk", frets: 19, span: 4, [
            ("Standard", "C3 G3 D4 A4"),
            ("Irish", "G2 D3 A3 E4"),
        ]),
        inst("bouzouki", "Irish Bouzouki", "Folk", frets: 24, span: 4, [
            ("GDAD", "G2 D3 A3 D4"),
            ("GDAE", "G2 D3 A3 E4"),
            ("ADAD", "A2 D3 A3 D4"),
        ]),
        inst("cavaquinho", "Cavaquinho", "Folk", frets: 17, [
            ("Standard (DGBD)", "D4 G4 B4 D5"),
        ]),
        inst("balalaika", "Balalaika", "Folk", frets: 24, pitchOrdered: false, [
            ("Prima (EEA)", "E4 E4 A4"),
        ]),
        // Bağlama tunings are written top (üst) → middle (orta) → bottom (alt), relative to an A bottom course.
        inst("baglama", "Bağlama", "Turkish & Middle Eastern", frets: 0, chords: false, [
            ("Bozuk (Kara) Düzen", "G3 D3 A3"),
            ("Bağlama Düzeni", "E3 D3 A3"),
            ("Misket", "F#3 D3 A3"),
            ("Müstezat", "F3 D3 A3"),
            ("Abdal", "G3 A3 A3"),
            ("Kayseri", "A3 E3 A3"),
            ("Rast", "G3 C4 A3"),
        ]),
        inst("oud", "Oud", "Turkish & Middle Eastern", frets: 0, chords: false, [
            ("Turkish", "C#2 F#2 B2 E3 A3 D4"),
            ("Arabic", "C2 F2 A2 D3 G3 C4"),
        ]),
        inst("bouzoukigreek", "Greek Bouzouki", "Turkish & Middle Eastern", frets: 26, span: 4, [
            ("Tetrachordo (CFAD)", "C3 F3 A3 D4"),
            ("Trichordo (DAD)", "D3 A3 D4"),
        ]),
    ]
}
