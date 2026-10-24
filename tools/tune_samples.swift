// Measures each rendered sample's real pitch and writes tuning.json: cents to add so it plays exactly in tune.
// Usage: cp tools/tune_samples.swift <tmp>/main.swift && swiftc -O <tmp>/main.swift Sources/PitchDetector.swift -o tune && ./tune <samples dir>
import AVFoundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let detector = PitchDetector(size: 8192)
var table: [String: [String: Double]] = [:]
for set in try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() where !set.hasPrefix(".") && !set.hasSuffix(".json") {
    var entries: [String: Double] = [:]
    for name in try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(set).path) where name.hasSuffix(".m4a") {
        let base = String(name.dropLast(4))
        let midi = Int(base.filter(\.isNumber))!
        let file = try AVAudioFile(forReading: root.appendingPathComponent(set).appendingPathComponent(name))
        let rate = file.processingFormat.sampleRate
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        let x = Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
        let expected = 440 * pow(2, (Double(midi) - 69) / 12)
        // Median over windows from 0.2 s to 1.6 s: steady part of the note, vibrato averages out.
        var cents: [Double] = []
        var start = Int(rate * 0.2)
        while start + 8192 < min(x.count, Int(rate * 1.6)) {
            let seg = Array(x[start..<start + 8192])
            if let r = seg.withUnsafeBufferPointer({ detector.detect($0.baseAddress!, sampleRate: rate, minFrequency: 25, maxFrequency: 4200) }),
               r.clarity > 0.85 {
                var c = 1200 * log2(r.frequency / expected)
                c -= 1200 * (c / 1200).rounded()
                cents.append(c)
            }
            start += 2048
        }
        guard cents.count >= 3 else { continue }
        let median = cents.sorted()[cents.count / 2]
        // Only trust small, consistent offsets; anything wild is a detection problem, not tuning.
        if abs(median) < 30 { entries[base] = -(median * 10).rounded() / 10 }
    }
    table[set] = entries
}
let data = try JSONSerialization.data(withJSONObject: table, options: [.sortedKeys, .prettyPrinted])
try data.write(to: root.appendingPathComponent("tuning.json"))
for (k, v) in table.sorted(by: { $0.key < $1.key }) {
    print(k, v.count, "notes corrected, largest", v.values.map(abs).max() ?? 0, "cents")
}
