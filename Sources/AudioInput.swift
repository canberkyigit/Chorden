import AVFoundation
import CoreAudio
import os

struct InputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let channels: Int
}

/// Microphone / interface capture. A sink node hands us every render cycle (~10 ms), which keeps
/// the tuner responsive; an installTap on macOS delivers 100 ms chunks at best.
final class AudioInput {
    static let capacity = 1 << 17

    private var engine: AVAudioEngine?
    private let lock = OSAllocatedUnfairLock()
    /// One ring per input channel (capped at 8), written on the render thread.
    nonisolated(unsafe) private var rings: [[Float]] = []
    nonisolated(unsafe) private var writeIndex = 0
    /// Frames written since start (never wraps), so a reader can pick up exactly where it left off.
    nonisolated(unsafe) private(set) var totalWritten = 0
    private(set) var sampleRate: Double = 48000
    private(set) var channelCount = 1

    var isRunning: Bool { engine?.isRunning ?? false }

    func start(deviceUID: String?) throws {
        stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let uid = deviceUID, let dev = Self.devices().first(where: { $0.uid == uid }), let unit = input.audioUnit {
            var id = dev.id
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Chorden", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio input available."])
        }
        sampleRate = format.sampleRate
        channelCount = min(Int(format.channelCount), 8)
        lock.withLockUnchecked {
            rings = Array(repeating: [Float](repeating: 0, count: Self.capacity), count: channelCount)
            writeIndex = 0
            totalWritten = 0
        }

        let channels = channelCount
        let sink = AVAudioSinkNode { [unowned self] _, frameCount, abl in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: abl))
            let frames = Int(frameCount)
            self.lock.withLockUnchecked {
                let start = self.writeIndex
                for c in 0..<min(channels, buffers.count) {
                    guard let data = buffers[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    self.rings[c].withUnsafeMutableBufferPointer { ring in
                        var w = start
                        for i in 0..<frames {
                            ring[w] = data[i]
                            w = (w + 1) & (Self.capacity - 1)
                        }
                    }
                }
                self.writeIndex = (start + frames) & (Self.capacity - 1)
                self.totalWritten += frames
            }
            return noErr
        }
        engine.attach(sink)
        engine.connect(input, to: sink, format: format)
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    func stop() {
        engine?.stop()
        engine = nil
    }

    /// Everything written since `position` (up to the ring's size), advancing `position`. For recording a take.
    func read(from position: inout Int, channel: Int) -> [Float] {
        lock.withLockUnchecked {
            guard channel < rings.count else { return [] }
            let available = min(totalWritten - position, Self.capacity)
            guard available > 0 else { return [] }
            var out = [Float](repeating: 0, count: available)
            rings[channel].withUnsafeBufferPointer { ring in
                var r = (writeIndex - available) & (Self.capacity - 1)
                for i in 0..<available {
                    out[i] = ring[r]
                    r = (r + 1) & (Self.capacity - 1)
                }
            }
            position = totalWritten
            return out
        }
    }

    /// Every channel's frames since `position`, advancing it once for all of them.
    func readAll(from position: inout Int) -> [[Float]] {
        var start = position
        var out: [[Float]] = []
        for c in 0..<channelCount {
            start = position
            out.append(read(from: &start, channel: c))
        }
        position = start
        return out
    }

    /// Copies the newest `count` frames of `channel` into `out`.
    func latest(_ count: Int, channel: Int, into out: inout [Float]) {
        lock.withLockUnchecked {
            guard channel < rings.count else { return }
            rings[channel].withUnsafeBufferPointer { ring in
                var r = (writeIndex - count) & (Self.capacity - 1)
                for i in 0..<count {
                    out[i] = ring[r]
                    r = (r + 1) & (Self.capacity - 1)
                }
            }
        }
    }

    #if SNAPSHOT
    func feed(_ samples: [Float], sampleRate: Double) {
        self.sampleRate = sampleRate
        channelCount = 1
        lock.withLockUnchecked {
            if rings.isEmpty { rings = [[Float](repeating: 0, count: Self.capacity)] }
            for v in samples {
                rings[0][writeIndex] = v
                writeIndex = (writeIndex + 1) & (Self.capacity - 1)
                totalWritten += 1
            }
        }
    }
    #endif

    // MARK: - Devices

    static func devices() -> [InputDevice] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
        else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids.compactMap { id in
            let channels = inputChannels(id)
            guard channels > 0, let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return InputDevice(id: id, uid: uid, name: name, channels: channels)
        }
    }

    static func defaultDeviceUID() -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr
        else { return nil }
        return string(id, kAudioDevicePropertyDeviceUID)
    }

    private static func inputChannels(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioDevicePropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr,
              let s = value?.takeRetainedValue() else { return nil }
        return s as String
    }
}
