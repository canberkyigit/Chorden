import Accelerate

/// McLeod Pitch Method (NSDF + key-maximum picking), the algorithm behind Tartini.
/// Autocorrelation runs through a real FFT, so even a 16k window costs well under a millisecond.
final class PitchDetector {
    let size: Int
    private let fftSize: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var signal: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var acf: [Float]
    private var nsdf: [Float]

    struct Result { let frequency: Double; let clarity: Double }

    init(size: Int) {
        self.size = size
        var n = 1
        while n < size * 2 { n <<= 1 }
        fftSize = n
        log2n = vDSP_Length(n.trailingZeroBitCount)
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        signal = [Float](repeating: 0, count: n)
        real = [Float](repeating: 0, count: n / 2)
        imag = [Float](repeating: 0, count: n / 2)
        acf = [Float](repeating: 0, count: n)
        nsdf = [Float](repeating: 0, count: size)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// `samples` must hold `size` frames. Returns nil when no periodic signal is found in range.
    func detect(_ samples: UnsafePointer<Float>, sampleRate: Double, minFrequency: Double,
                maxFrequency: Double) -> Result? {
        let n = size
        // Copy, remove DC, zero-pad to 2N so the circular correlation equals the linear one.
        signal.withUnsafeMutableBufferPointer { s in
            var mean: Float = 0
            vDSP_meanv(samples, 1, &mean, vDSP_Length(n))
            var negMean = -mean
            vDSP_vsadd(samples, 1, &negMean, s.baseAddress!, 1, vDSP_Length(n))
            vDSP_vclr(s.baseAddress! + n, 1, vDSP_Length(fftSize - n))
        }

        var energy: Float = 0
        vDSP_svesq(signal, 1, &energy, vDSP_Length(n))
        guard energy > 1e-9 else { return nil }

        // r = IFFT(|FFT(x)|²)
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                signal.withUnsafeBufferPointer { s in
                    s.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                // Packed format: DC in realp[0], Nyquist in imagp[0].
                let dc = re[0] * re[0], nyq = im[0] * im[0]
                vDSP_zvmags(&split, 1, re.baseAddress!, 1, vDSP_Length(fftSize / 2))
                vDSP_vclr(im.baseAddress!, 1, vDSP_Length(fftSize / 2))
                re[0] = dc
                im[0] = nyq
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Inverse))
                acf.withUnsafeMutableBufferPointer { a in
                    a.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) {
                        vDSP_ztoc(&split, 1, $0, 2, vDSP_Length(fftSize / 2))
                    }
                }
            }
        }
        guard acf[0] > 0 else { return nil }
        // FFT scaling is irrelevant once r(0) is pinned to the true energy.
        var scale = energy / acf[0]
        acf.withUnsafeMutableBufferPointer { a in
            vDSP_vsmul(a.baseAddress!, 1, &scale, a.baseAddress!, 1, vDSP_Length(n))
        }

        // NSDF n(τ) = 2r(τ) / m(τ), with m(τ) = Σ x_j² + x_{j+τ}² updated incrementally.
        let maxLag = min(n / 2, Int(sampleRate / minFrequency) + 2)
        let minLag = max(2, Int(sampleRate / maxFrequency) - 1)
        guard maxLag > minLag + 2 else { return nil }
        var m = 2 * Double(energy)
        signal.withUnsafeBufferPointer { x in
            nsdf[0] = 1
            for tau in 1..<maxLag {
                let a = Double(x[tau - 1]), b = Double(x[n - tau])
                m -= a * a + b * b
                nsdf[tau] = m > 1e-12 ? Float(2 * Double(acf[tau]) / m) : 0
            }
        }

        // Key maxima: the highest point of each positive lobe after the first negative zero crossing.
        var peaks: [(Int, Float)] = []
        var tau = 1
        while tau < maxLag && nsdf[tau] > 0 { tau += 1 }
        var best: (Int, Float)? = nil
        while tau < maxLag - 1 {
            if nsdf[tau] > 0 {
                if best == nil || nsdf[tau] > best!.1 { best = (tau, nsdf[tau]) }
            } else if let b = best {
                peaks.append(b)
                best = nil
            }
            tau += 1
        }
        if let b = best { peaks.append(b) }
        let inRange = peaks.filter { $0.0 >= minLag }
        guard let highest = inRange.map(\.1).max(), highest > 0.3 else { return nil }
        let threshold = highest * 0.9
        guard let pick = inRange.first(where: { $0.1 >= threshold }) else { return nil }

        // Parabolic interpolation for sub-sample lag (worth ~0.1 cent at guitar pitches).
        let i = pick.0
        let y0 = Double(nsdf[i - 1]), y1 = Double(nsdf[i]), y2 = Double(i + 1 < maxLag ? nsdf[i + 1] : nsdf[i])
        let denom = y0 - 2 * y1 + y2
        var shift = 0.0, peak = y1
        if abs(denom) > 1e-12 {
            shift = max(-0.5, min(0.5, 0.5 * (y0 - y2) / denom))
            peak = y1 - 0.25 * (y0 - y2) * shift
        }
        let lag = Double(i) + shift
        let f = sampleRate / lag
        guard f >= minFrequency * 0.98, f <= maxFrequency * 1.02 else { return nil }
        return Result(frequency: f, clarity: min(1, peak))
    }
}
