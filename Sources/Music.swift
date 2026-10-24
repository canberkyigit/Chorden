import Foundation

/// Pitch math and note naming. Notes are MIDI numbers (A4 = 69, C4 = 60).
enum Music {
    static func frequency(midi: Double, a4: Double) -> Double { a4 * pow(2, (midi - 69) / 12) }
    static func midi(frequency: Double, a4: Double) -> Double { 69 + 12 * log2(frequency / a4) }

    /// Parses "E2", "C#3", "Bb1", "F♯4" into a MIDI number. Used to keep the tuning catalog readable.
    static func parse(_ s: String) -> Int {
        let letters: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        var chars = Array(s)
        var pc = letters[chars.removeFirst()]!
        if let c = chars.first, "#♯b♭".contains(c) {
            pc += (c == "#" || c == "♯") ? 1 : -1
            chars.removeFirst()
        }
        let octave = Int(String(chars))!
        return (octave + 1) * 12 + pc
    }
}

enum Accidental: String, CaseIterable { case sharp, flat }
enum NoteNaming: String, CaseIterable { case letters, solfege }

struct Notation: Equatable {
    var accidental: Accidental = .sharp
    var naming: NoteNaming = .letters

    private static let letterSharp = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    private static let letterFlat = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
    private static let solfegeSharp = ["Do", "Do♯", "Re", "Re♯", "Mi", "Fa", "Fa♯", "Sol", "Sol♯", "La", "La♯", "Si"]
    private static let solfegeFlat = ["Do", "Re♭", "Re", "Mi♭", "Mi", "Fa", "Sol♭", "Sol", "La♭", "La", "Si♭", "Si"]

    func name(pc: Int) -> String {
        let i = ((pc % 12) + 12) % 12
        switch (naming, accidental) {
        case (.letters, .sharp): return Self.letterSharp[i]
        case (.letters, .flat): return Self.letterFlat[i]
        case (.solfege, .sharp): return Self.solfegeSharp[i]
        case (.solfege, .flat): return Self.solfegeFlat[i]
        }
    }

    /// Splits a name into its base ("C", "Sol") and accidental ("♯", "♭", "") for typesetting.
    func parts(pc: Int) -> (base: String, accidental: String) {
        let n = name(pc: pc)
        if let last = n.last, last == "♯" || last == "♭" { return (String(n.dropLast()), String(last)) }
        return (n, "")
    }

    func name(midi: Int) -> String { name(pc: midi) + String(midi / 12 - 1) }
    static func octave(_ midi: Int) -> Int { midi / 12 - 1 }
}
