import AVFoundation
import Testing
@testable import OpenFlow

@Suite("Audio recording")
struct AudioRecorderTests {
    @Test("it(\"should convert native 24 kHz microphone audio to Whisper format\")")
    func convertsAirPodsInputFormat() {
        let input = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        let output = AVAudioFormat(standardFormatWithSampleRate: AudioRecorder.sampleRate, channels: 1)!
        let converter = AudioRecorder.makeConverter(from: input, to: output)

        #expect(converter?.inputFormat.sampleRate == 24_000 && converter?.outputFormat.sampleRate == 16_000)
    }
}
