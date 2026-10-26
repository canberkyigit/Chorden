import Foundation

/// How the twelve notes are tuned against each other in the chromatic tuner (and on the piano): equal temperament,
/// or one of the historical tunings early-music players, organists and string players tune to.
/// Every table is computed from its definition (a chain of fifths, or just ratios), never typed in.
enum Temperament: String, CaseIterable {
    case equal, just, pythagorean, meantone, werckmeister, vallotti

    var name: String {
        switch self {
        case .equal: "Equal temperament"
        case .just: "Just intonation"
        case .pythagorean: "Pythagorean"
        case .meantone: "Meantone (¼ comma)"
        case .werckmeister: "Werckmeister III"
        case .vallotti: "Vallotti"
        }
    }

    var detail: String {
        switch self {
        case .equal: "every semitone 100 ¢"
        case .just: "pure thirds and fifths in one key"
        case .pythagorean: "pure fifths"
        case .meantone: "pure major thirds"
        case .werckmeister: "well-tempered, 1691"
        case .vallotti: "well-tempered, 18th c."
        }
    }

    /// One Pythagorean comma: twelve pure fifths overshoot seven octaves by this much.
    static let comma = 1200 * log2(pow(1.5, 12) / pow(2, 7))
    static let pureFifth = 1200 * log2(1.5)

    /// Cents to add to each pitch class (0 = C) when the temperament is built on `key`. A stays at 0, so the
    /// A4 reference keeps its meaning.
    func offsets(key: Int) -> [Double] {
        let k = ((key % 12) + 12) % 12
        var out: [Double]
        switch self {
        case .equal:
            return Array(repeating: 0, count: 12)
        case .just:
            // 5-limit ratios above the key's tonic.
            let ratios: [(Double, Double)] = [(1, 1), (16, 15), (9, 8), (6, 5), (5, 4), (4, 3), (45, 32), (3, 2), (8, 5),
                                              (5, 3), (16, 9), (15, 8)]
            out = Array(repeating: 0, count: 12)
            for (i, r) in ratios.enumerated() { out[(k + i) % 12] = 1200 * log2(r.0 / r.1) - 100 * Double(i) }
        case .pythagorean:
            // E♭ up eleven pure fifths to G♯; the wolf falls between G♯ and E♭.
            out = Self.chain(from: k + 3, fifths: Array(repeating: Self.pureFifth, count: 11))
        case .meantone:
            // Fifths narrowed by a quarter of the syntonic comma, so four of them make a pure major third.
            let fifth = 1200 * log2(pow(5, 0.25))
            out = Self.chain(from: k + 3, fifths: Array(repeating: fifth, count: 11))
        case .werckmeister:
            // C–G, G–D, D–A and B–F♯ narrowed by ¼ comma; every other fifth pure.
            let t = Self.pureFifth - Self.comma / 4, p = Self.pureFifth
            out = Self.chain(from: k, fifths: [t, t, t, p, p, t, p, p, p, p, p])
        case .vallotti:
            // F–C–G–D–A–E–B narrowed by ⅙ comma; B–F♯–C♯–G♯–D♯–A♯ pure.
            let t = Self.pureFifth - Self.comma / 6, p = Self.pureFifth
            out = Self.chain(from: k + 5, fifths: [t, t, t, t, t, t, p, p, p, p, p])
        }
        let a = out[9]
        return out.map { $0 - a }
    }

    /// Walks a chain of fifths from `start`, returning each pitch class's distance from its equal-tempered place.
    private static func chain(from start: Int, fifths: [Double]) -> [Double] {
        var out = Array(repeating: 0.0, count: 12)
        var pc = ((start % 12) + 12) % 12, cents = 0.0
        out[pc] = 0
        for f in fifths {
            pc = (pc + 7) % 12
            cents += f - 700
            out[pc] = cents
        }
        // Distances are relative to the chain's start; centre them so the numbers stay small.
        let mean = out.reduce(0, +) / 12
        return out.map { $0 - mean }
    }
}
