import AVFoundation
import os

/// One recorded note at its file's sample rate, with its exact pitch.
final class SampleNote {
    let midi: Double
    let data: [Float]
    let rate: Double
    /// Instrument-wide playback level, so every instrument sits at the same loudness as the others.
    let level: Float
    /// Recorded softly (a second velocity layer).
    let soft: Bool
    init(midi: Double, data: [Float], rate: Double, level: Float, soft: Bool = false) {
        self.midi = midi
        self.data = data
        self.rate = rate
        self.level = level
        self.soft = soft
    }
}

/// Recorded instruments (Resources/Samples), decoded lazily the first time an instrument plays.
final class SampleLibrary {
    static let shared = SampleLibrary()

    private let lock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private var sets: [String: [SampleNote]] = [:]
    nonisolated(unsafe) private var loading: Set<String> = []
    private let queue = DispatchQueue(label: "tonic.samples", qos: .userInitiated)
    /// Measured so a strummed chord lands near −19 dB, like the modeled instruments.
    private let levels: [String: Float] = ["steel": 0.19, "nylon": 1.17, "electric": 0.28, "bass": 0.31, "violin": 0.32,
                                           "viola": 0.39, "cello": 0.27, "contrabass": 0.36, "banjo": 0.35, "piano": 0.24,
                                           "baglama": 0.37, "ukulele": 0.32]

    private lazy var tuning: [String: [String: Double]] = {
        guard let url = Bundle.main.url(forResource: "tuning", withExtension: "json", subdirectory: "Samples"),
              let data = try? Data(contentsOf: url),
              let t = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Double]] else { return [:] }
        return t
    }()

    /// Notes of a set if it's ready; otherwise starts loading it and returns nil (the model sound plays meanwhile).
    func notes(_ id: String) -> [SampleNote]? {
        if let hit = lock.withLockUnchecked({ sets[id] }) { return hit }
        let start = lock.withLockUnchecked { loading.insert(id).inserted }
        if start { queue.async { self.load(id) } }
        return nil
    }

    /// Decodes a set up front (when an instrument is chosen), so its first note already sounds real.
    func preload(_ id: String?) {
        guard let id else { return }
        _ = notes(id)
    }

    private func load(_ id: String) {
        guard let dir = Bundle.main.url(forResource: id, withExtension: nil, subdirectory: "Samples"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let corrections = tuning[id] ?? [:]
        var notes: [SampleNote] = []
        for url in files where url.pathExtension == "m4a" {
            let name = url.deletingPathExtension().lastPathComponent
            guard let midi = Int(name.filter(\.isNumber)),
                  let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil else { continue }
            let data = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
            // The recording's real pitch: nominal note minus the measured correction.
            let actual = Double(midi) - (corrections[name] ?? 0) / 100
            notes.append(SampleNote(midi: actual, data: data, rate: file.processingFormat.sampleRate,
                                    level: levels[id] ?? 0.25, soft: name.hasSuffix("s")))
        }
        notes.sort { $0.midi < $1.midi }
        lock.withLockUnchecked {
            sets[id] = notes
            loading.remove(id)
        }
    }
}

/// Plays a recorded note at any pitch: the nearest recording, resampled with cubic interpolation.
struct SampleVoice {
    private let note: SampleNote
    private let step: Double
    private var pos = 0.0
    var delay: Int
    private let gain: Float
    private var lp: Float = 0
    private let lpCoef: Float
    /// Samples the note may sound before it's let go (bowed notes, scale runs); nil = ring out.
    private var hold: Int?
    private var releasing = false
    private var releaseCountdown = 0
    private var env: Float = 1
    private let releaseStep: Float
    let string: Int?
    let panL: Float, panR: Float
    var finished: Bool { Int(pos) >= note.data.count - 3 || env < 0.0005 }

    /// A recording to play exactly as captured (the user's voice): no tone filter.
    private let raw: Bool

    init(notes: [SampleNote], midi: Double, sampleRate: Double, delay: Int, velocity: Double, hold: Double?,
         string: Int?, pan: Double, release: Double = 0.06, raw: Bool = false) {
        self.raw = raw
        // With a soft layer, gentle notes use the softly played recording: a real change of tone, not just volume.
        let layered = notes.contains { $0.soft }
        let pool = layered ? notes.filter { $0.soft == (velocity < 0.62) } : notes
        note = pool.min { abs($0.midi - midi) < abs($1.midi - midi) }!
        step = pow(2, (midi - note.midi) / 12) * note.rate / sampleRate
        self.delay = delay
        gain = Float(layered ? 0.65 + 0.35 * velocity : 0.3 + 0.7 * velocity) * note.level
        // Softer notes are darker, as with a real pick or bow.
        let cutoff = 2500 + 9000 * velocity
        lpCoef = Float(1 - exp(-2 * Double.pi * cutoff / sampleRate))
        self.hold = hold.map { Int($0 * sampleRate) }
        self.string = string
        let p = max(-1, min(1, pan))
        panL = Float(sqrt(0.5 - p / 2))
        panR = Float(sqrt(0.5 + p / 2))
        releaseStep = Float(exp(-1 / (release * sampleRate)))
    }

    mutating func release() { releasing = true }

    mutating func releaseAt(_ samples: Int) {
        if samples <= 0 { releasing = true } else { releaseCountdown = samples }
    }

    var started: Bool { delay == 0 }

    mutating func next() -> Float {
        if delay > 0 { delay -= 1; return 0 }
        let d = note.data
        let i = Int(pos)
        guard i + 2 < d.count else { return 0 }
        let t = Float(pos - Double(i))
        let y0 = i > 0 ? d[i - 1] : d[i], y1 = d[i], y2 = d[i + 1], y3 = d[i + 2]
        // Catmull-Rom: clean pitch shifts without the dullness of linear interpolation.
        let s = y1 + 0.5 * t * (y2 - y0 + t * (2 * y0 - 5 * y1 + 4 * y2 - y3 + t * (3 * (y1 - y2) + y3 - y0)))
        pos += step
        if let h = hold {
            if h <= 0 { releasing = true } else { hold = h - 1 }
        }
        if releaseCountdown > 0 {
            releaseCountdown -= 1
            if releaseCountdown == 0 { releasing = true }
        }
        if releasing { env *= releaseStep }
        if raw { return s * gain * env }
        lp += lpCoef * (s - lp)
        return lp * gain * env
    }
}
