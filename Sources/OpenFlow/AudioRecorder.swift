import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// Captures microphone input and delivers it as 16 kHz mono Float32 samples,
/// the format Whisper models expect.
final class AudioRecorder {
    enum RecorderError: LocalizedError {
        case microphoneDenied
        case converterUnavailable
        case inputDeviceUnavailable
        case engineFailed(String)

        var errorDescription: String? {
            switch self {
            case .microphoneDenied:
                return "Microphone access is denied."
            case .converterUnavailable:
                return "Audio conversion to 16 kHz could not be prepared."
            case .inputDeviceUnavailable:
                return "No input device is available."
            case .engineFailed(let message):
                return "The audio engine could not start: \(message)"
            }
        }
    }

    static let sampleRate: Double = 16_000
    /// Hard stop so a stuck hotkey cannot grow the buffer without bound.
    static let maxDuration: TimeInterval = 300
    /// Anything shorter is almost certainly an accidental tap, and Whisper
    /// hallucinates on near-empty input.
    static let minDuration: TimeInterval = 0.35

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var isRunning = false

    /// Peak amplitude of the most recent buffer, for the level meter.
    private(set) var level: Float = 0

    var recordedDuration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Double(samples.count) / Self.sampleRate
    }

    static var hasMicrophoneAccess: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    /// Returns true when a missing selected device had to fall back to the system input.
    func start(deviceUID: String?) throws -> Bool {
        guard !isRunning else { return false }

        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecorderError.microphoneDenied
        }

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        level = 0

        let resolution = AudioDeviceManager.resolvedDeviceID(for: deviceUID)
        guard let deviceID = resolution.id else { throw RecorderError.inputDeviceUnavailable }

        let input = engine.inputNode
        guard let audioUnit = input.audioUnit else { throw RecorderError.inputDeviceUnavailable }
        var selectedDeviceID = deviceID
        let deviceStatus = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selectedDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard deviceStatus == noErr else {
            throw RecorderError.engineFailed("Core Audio error \(deviceStatus)")
        }

        guard let targetFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: Self.sampleRate,
                  channels: 1,
                  interleaved: false
              )
        else {
            throw RecorderError.converterUnavailable
        }
        lock.lock()
        converter = nil
        lock.unlock()

        // Let AVAudioEngine use the active device's native format. Passing the
        // input node's cached format can crash when Core Audio is still applying
        // a device change, such as switching from a 48 kHz input to 24 kHz AirPods.
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.append(buffer, targetFormat: targetFormat)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.converter = nil
            throw RecorderError.engineFailed(error.localizedDescription)
        }

        isRunning = true
        return resolution.usedFallback
    }

    /// Stops the engine and returns everything captured so far.
    @discardableResult
    func stop() -> [Float] {
        guard isRunning else { return [] }
        isRunning = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        level = 0

        lock.lock()
        converter = nil
        let captured = samples
        samples.removeAll(keepingCapacity: false)
        lock.unlock()
        return captured
    }

    static func makeConverter(
        from inputFormat: AVAudioFormat,
        to targetFormat: AVAudioFormat
    ) -> AVAudioConverter? {
        AVAudioConverter(from: inputFormat, to: targetFormat)
    }

    private func append(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard buffer.format.sampleRate > 0 else { return }

        lock.lock()
        if converter?.inputFormat.isEqual(buffer.format) != true {
            converter = Self.makeConverter(from: buffer.format, to: targetFormat)
        }
        let activeConverter = converter
        lock.unlock()

        guard let activeConverter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var conversionError: NSError?
        activeConverter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        guard conversionError == nil,
              let channel = output.floatChannelData?[0],
              output.frameLength > 0
        else { return }

        let frames = Int(output.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channel, count: frames))

        var peak: Float = 0
        for sample in chunk {
            peak = max(peak, abs(sample))
        }
        level = peak

        lock.lock()
        if Double(samples.count) < Self.maxDuration * Self.sampleRate {
            samples.append(contentsOf: chunk)
        }
        lock.unlock()
    }
}
