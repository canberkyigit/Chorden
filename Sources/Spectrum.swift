import Accelerate

/// Magnitude spectrum of a Hann-windowed, 2× zero-padded frame, with sub-bin peak refinement.
/// Shared by the all-strings tuner (several known pitches at once) and chord recognition.
final class Spectrum {
    let size: Int
    private let fftSize: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var buffer: [Float]
    private var real: [Float]
    private var imag: [Float]
    private(set) var mags: [Float]
    private(set) var binHz = 1.0

    init(size: Int) {
        self.size = size
        fftSize = size * 2
        log2n = vDSP_Length(fftSize.trailingZeroBitCount)
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        buffer = [Float](repeating: 0, count: fftSize)
        real = [Float](repeating: 0, count: fftSize / 2)
        imag = [Float](repeating: 0, count: fftSize / 2)
        mags = [Float](repeating: 0, count: fftSize / 2)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    func compute(_ samples: UnsafePointer<Float>, sampleRate: Double) {
        binHz = sampleRate / Double(fftSize)
        buffer.withUnsafeMutableBufferPointer { b in
            vDSP_vmul(samples, 1, window, 1, b.baseAddress!, 1, vDSP_Length(size))
            vDSP_vclr(b.baseAddress! + size, 1, vDSP_Length(fftSize - size))
        }
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                buffer.withUnsafeBufferPointer { b in
                    b.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                im[0] = 0 // packed Nyquist
                mags.withUnsafeMutableBufferPointer { m in
                    vDSP_zvabs(&split, 1, m.baseAddress!, 1, vDSP_Length(fftSize / 2))
                }
            }
        }
    }

    func bin(_ hz: Double) -> Int { Int((hz / binHz).rounded()) }

    /// Median magnitude between two frequencies: the noise floor peaks are judged against.
    func floor(from lo: Double, to hi: Double) -> Float {
        let a = max(1, bin(lo)), b = min(mags.count - 1, bin(hi))
        guard b > a else { return 0 }
        var slice = Array(mags[a...b])
        let mid = slice.count / 2
        slice.withUnsafeMutableBufferPointer { s in
            // Partial selection is plenty for a median.
            vDSP_vsort(s.baseAddress!, vDSP_Length(s.count), 1)
        }
        return slice[mid]
    }

    /// Strongest local maximum within ±`cents` of `hz`, refined with Gaussian (log-parabolic) interpolation,
    /// which is near-exact for a Hann window.
    func peak(near hz: Double, cents: Double) -> (hz: Double, mag: Float)? {
        let r = pow(2, cents / 1200)
        let lo = max(2, Int((hz / r / binHz).rounded(.down)))
        let hi = min(mags.count - 3, Int((hz * r / binHz).rounded(.up)))
        guard hi > lo else { return nil }
        var best = -1
        var bestMag: Float = 0
        for k in lo...hi where mags[k] > bestMag && mags[k] >= mags[k - 1] && mags[k] >= mags[k + 1] {
            best = k
            bestMag = mags[k]
        }
        guard best > 0 else { return nil }
        let a = log(Double(max(mags[best - 1], 1e-12)))
        let b = log(Double(max(mags[best], 1e-12)))
        let c = log(Double(max(mags[best + 1], 1e-12)))
        let d = a - 2 * b + c
        let p = d != 0 ? max(-0.5, min(0.5, 0.5 * (a - c) / d)) : 0
        return ((Double(best) + p) * binHz, bestMag)
    }

    /// Local maxima above `threshold` between two frequencies.
    func peaks(from lo: Double, to hi: Double, threshold: Float) -> [(hz: Double, mag: Float)] {
        let a = max(2, bin(lo)), b = min(mags.count - 3, bin(hi))
        guard b > a else { return [] }
        var out: [(Double, Float)] = []
        for k in a...b where mags[k] > threshold && mags[k] > mags[k - 1] && mags[k] >= mags[k + 1] {
            let y0 = log(Double(max(mags[k - 1], 1e-12))), y1 = log(Double(mags[k])), y2 = log(Double(max(mags[k + 1], 1e-12)))
            let d = y0 - 2 * y1 + y2
            let p = d != 0 ? max(-0.5, min(0.5, 0.5 * (y0 - y2) / d)) : 0
            out.append(((Double(k) + p) * binHz, mags[k]))
        }
        return out
    }
}

struct DetectedChord: Equatable {
    let root: Int
    let quality: String
    /// Bass pitch class when it isn't the root (slash chord), else nil.
    let bass: Int?
}

/// Chord recognition: a chromagram from spectral peaks, matched against harmonic-aware templates.
enum ChordRecognizer {
    static let qualities = ["", "m", "7", "maj7", "m7", "sus2", "sus4", "dim", "aug", "5", "m7♭5", "6", "m6", "add9", "dim7"]
    /// Richer chords must win clearly, or every major triad would read as add9 or 6.
    private static let penalty: [String: Double] = [
        "": 0, "m": 0, "5": 0.02, "7": 0.012, "maj7": 0.014, "m7": 0.012, "sus2": 0.02, "sus4": 0.02,
        "dim": 0.02, "aug": 0.025, "m7♭5": 0.02, "6": 0.025, "m6": 0.025, "add9": 0.025, "dim7": 0.025,
    ]

    private static let templates: [(root: Int, quality: String, vec: [Double])] = {
        var out: [(Int, String, [Double])] = []
        for q in qualities {
            let iv = Chords.quality(q).intervals.map { $0 % 12 }
            for root in 0..<12 {
                var v = [Double](repeating: 0, count: 12)
                for t in iv {
                    // Harmonics 1–4 of each chord tone: octaves land on the tone, the 3rd on its fifth.
                    v[(root + t) % 12] += 1 + 0.6 + 0.216
                    v[(root + t + 7) % 12] += 0.36
                }
                let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
                out.append((root, q, v.map { $0 / norm }))
            }
        }
        return out
    }()

    static func recognize(_ spectrum: Spectrum, a4: Double) -> (chord: DetectedChord, score: Double)? {
        let floor = spectrum.floor(from: 60, to: 2000)
        let peaks = spectrum.peaks(from: 60, to: 2000, threshold: max(floor * 5, 1e-6))
        guard peaks.count >= 2 else { return nil }
        var chroma = [Double](repeating: 0, count: 12)
        var bass: (hz: Double, mag: Float)?
        let lowMax = peaks.filter { $0.hz < 330 }.map(\.mag).max() ?? 0
        for p in peaks {
            let midi = 69 + 12 * log2(p.hz / a4)
            let dev = abs(midi - midi.rounded())
            guard dev < 0.4 else { continue }
            let pc = ((Int(midi.rounded()) % 12) + 12) % 12
            chroma[pc] += sqrt(Double(p.mag)) * (1 - dev)
            if p.hz < 330, p.mag > lowMax * 0.3, bass == nil || p.hz < bass!.hz { bass = p }
        }
        let norm = sqrt(chroma.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return nil }
        chroma = chroma.map { $0 / norm }
        // Need at least two clearly present pitch classes for a chord.
        guard chroma.filter({ $0 > 0.25 }).count >= 2 else { return nil }

        let bassNote = bass.map { ((Int((69 + 12 * log2($0.hz / a4)).rounded()) % 12) + 12) % 12 }
        var best: (Int, String, Double) = (0, "", -1)
        for t in templates {
            var dot = 0.0
            for i in 0..<12 { dot += chroma[i] * t.vec[i] }
            // Same notes, different names (Dsus4 = Gsus2): the one rooted on the bass wins.
            let score = dot - (penalty[t.quality] ?? 0) + (t.root == bassNote ? 0.012 : 0)
            if score > best.2 { best = (t.root, t.quality, score) }
        }
        var bassPC: Int? = nil
        if let pc = bassNote {
            let tones = Chords.quality(best.1).intervals.map { (best.0 + $0) % 12 }
            if pc != best.0 && tones.contains(pc) { bassPC = pc }
        }
        return (DetectedChord(root: best.0, quality: best.1, bass: bassPC), best.2)
    }
}
