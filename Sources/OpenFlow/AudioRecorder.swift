import AVFoundation
import Foundation

/// Captures microphone input and delivers it as 16 kHz mono Float32 samples,
/// the format Whisper models expect.
final class AudioRecorder {
    enum RecorderError: LocalizedError {
        case microphoneDenied
        case converterUnavailable
        case engineFailed(String)

        var errorDescription: String? {
            switch self {
            case .microphoneDenied:
                return "Brak dostępu do mikrofonu. Włącz go w Ustawieniach systemowych → Prywatność i ochrona → Mikrofon."
            case .converterUnavailable:
                return "Nie udało się przygotować konwersji audio do 16 kHz."
            case .engineFailed(let message):
                return "Nie udało się uruchomić nagrywania: \(message)"
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

    func start() throws {
        guard !isRunning else { return }

        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecorderError.microphoneDenied
        }

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        level = 0

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0,
              let targetFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: Self.sampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else {
            throw RecorderError.converterUnavailable
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer, using: converter, targetFormat: targetFormat)
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
    }

    /// Stops the engine and returns everything captured so far.
    @discardableResult
    func stop() -> [Float] {
        guard isRunning else { return [] }
        isRunning = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        level = 0

        lock.lock()
        let captured = samples
        samples.removeAll(keepingCapacity: false)
        lock.unlock()
        return captured
    }

    private func append(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
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
