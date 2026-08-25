import AppKit
import Foundation
import Observation

/// Orchestrates the whole dictation flow: hotkey → record → transcribe →
/// optional cleanup or translation → paste.
@Observable
@MainActor
final class AppState {
    struct Failure: Equatable {
        let key: String
        let detail: String

        func message(language: AppLanguage) -> String {
            L10n.text(key, language: language, detail)
        }
    }

    enum Notice {
        case microphoneFallback
        case cleanupFailed(String)
        case translationAPIFailed(String)
        case translationFailed(String, PrimaryLanguage)

        func message(language: AppLanguage) -> String {
            switch self {
            case .microphoneFallback:
                return L10n.text("warning.microphone_fallback", language: language)
            case .cleanupFailed(let detail):
                return L10n.text("warning.cleanup_failed", language: language, detail)
            case .translationAPIFailed(let detail):
                return L10n.text("warning.translation_api_failed", language: language, detail)
            case .translationFailed(let detail, let sourceLanguage):
                return L10n.text(
                    "warning.translation_failed",
                    language: language,
                    detail,
                    sourceLanguage.label(language: language)
                )
            }
        }
    }

    enum Status: Equatable {
        case needsPermissions
        case preparingModel(progress: Double)
        case idle
        case recording
        case transcribing
        case cleaning
        case translating
        case failed(Failure)

        var isBusy: Bool {
            switch self {
            case .transcribing, .cleaning, .translating: return true
            default: return false
            }
        }
    }

    /// The offline translation model that sits next to a turbo model. Shown in
    /// the menu and the indicator, because a cold large-v3 load takes minutes
    /// and must not look like a hang.
    enum TranslationModelState: Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case failed(String)

        init(_ state: TranscriptionEngine.PrepareState) {
            switch state {
            case .downloading(let progress): self = .downloading(progress)
            case .loading: self = .loading
            case .ready: self = .ready
            case .failed(let message): self = .failed(message)
            }
        }

        var isPreparing: Bool {
            switch self {
            case .downloading, .loading: return true
            default: return false
            }
        }
    }

    /// Which hotkey started the current recording.
    enum DictationMode {
        case dictate
        case translate
    }

    /// The app delegate needs to kick off `start()` before any view exists, and
    /// a menu-bar-only app has no other shared entry point.
    static let shared = AppState()

    private(set) var status: Status = .idle
    private(set) var currentMode: DictationMode = .dictate
    private(set) var translationModelState: TranslationModelState = .idle
    private(set) var lastTranscript: String = ""
    /// Set when cleanup failed but we pasted the raw transcript anyway.
    private(set) var lastWarning: Notice?
    /// Non-nil while the Settings hotkey recorder waits for a key press.
    private(set) var capturingRole: HotkeyRole?
    var captureError: HotkeySpec?

    var hasMicrophonePermission = false
    var hasAccessibilityPermission = false
    /// False until `start()` has asked the system once, so the permissions
    /// window does not flash before the microphone prompt.
    private(set) var permissionsChecked = false
    private(set) var audioInputDevices: [AudioInputDevice] = []

    // `var` so SwiftUI can build bindings through it, e.g. $state.preferences.playSounds
    var preferences = Preferences()

    private let recorder = AudioRecorder()
    private let audioDeviceManager = AudioDeviceManager()
    private let hotkeys = HotkeyManager()
    private let engine = TranscriptionEngine()
    private var permissionTimer: Timer?
    private var modelReady = false
    private var modelProgress: Double = 0
    /// Bumped on every capture start so a stale timeout cannot cancel a newer one.
    private var captureGeneration = 0

    init() {
        hotkeys.onPress = { [weak self] role in self?.beginDictation(role: role) }
        hotkeys.onRelease = { [weak self] _ in self?.endDictation() }
        hotkeys.onTab = { [weak self] in self?.handleTab() }
        audioDeviceManager.onDevicesChanged = { [weak self] in
            Task { @MainActor in self?.refreshAudioInputDevices() }
        }
    }

    // MARK: - Lifecycle

    func start() async {
        hasMicrophonePermission = await AudioRecorder.requestMicrophoneAccess()
        refreshAudioInputDevices()
        refreshAccessibilityPermission()
        permissionsChecked = true
        applyHotkeyBinding()
        watchForPermissionChanges()
        await loadModel()
    }

    /// Both permissions are granted in System Settings, outside our process and
    /// with no notification back to us, so poll until they land and arm the app
    /// without making the user restart it.
    private func watchForPermissionChanges() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let accessibility = HotkeyManager.hasAccessibilityPermission
                let microphone = AudioRecorder.hasMicrophoneAccess

                guard accessibility != self.hasAccessibilityPermission
                        || microphone != self.hasMicrophonePermission
                else { return }

                self.hasAccessibilityPermission = accessibility
                self.hasMicrophonePermission = microphone
                self.applyHotkeyBinding()
            }
        }
    }

    func refreshAccessibilityPermission() {
        hasAccessibilityPermission = HotkeyManager.hasAccessibilityPermission
    }

    func refreshAudioInputDevices() {
        audioInputDevices = audioDeviceManager.inputDevices()
    }

    func requestAccessibilityPermission() {
        HotkeyManager.requestAccessibilityPermission()
    }

    func applyHotkeyBinding() {
        hotkeys.dictationKey = preferences.dictationHotkey
        hotkeys.translationKey = preferences.translationHotkey
        if hasAccessibilityPermission {
            if !hotkeys.isRunning { hotkeys.start() }
        } else {
            hotkeys.stop()
        }
        recomputeIdleStatus()
    }

    // MARK: - Hotkey capture

    /// Click-then-press recorder in Settings. The next key pressed becomes the
    /// binding for `role`; Escape cancels.
    func startHotkeyCapture(role: HotkeyRole) {
        guard hasAccessibilityPermission, hotkeys.isRunning else { return }
        captureError = nil

        if capturingRole != nil {
            hotkeys.cancelCapture()
        }
        capturingRole = role
        captureGeneration += 1

        // An armed capture swallows the next key press system-wide. If the
        // user clicked the recorder and wandered off, disarm it rather than
        // eating a keystroke in some other app minutes later.
        let generation = captureGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.captureGeneration == generation, self.capturingRole != nil else { return }
            self.cancelHotkeyCapture()
        }

        hotkeys.beginCapture { [weak self] spec in
            guard let self else { return }
            // A cancelled capture may resolve after a newer one started; only
            // the capture that still owns `capturingRole` may touch state.
            guard self.capturingRole == role else { return }
            self.capturingRole = nil
            guard let spec else { return }

            let other = role == .dictate
                ? self.preferences.translationHotkey
                : self.preferences.dictationHotkey
            guard spec != other else {
                self.captureError = spec
                return
            }

            switch role {
            case .dictate: self.preferences.dictationHotkey = spec
            case .translate: self.preferences.translationHotkey = spec
            }
            self.applyHotkeyBinding()
        }
    }

    func cancelHotkeyCapture() {
        hotkeys.cancelCapture()
        capturingRole = nil
    }

    func loadModel() async {
        modelReady = false
        modelProgress = 0
        translationModelState = .idle

        for await state in engine.prepare(model: preferences.whisperModel) {
            switch state {
            case .downloading(let progress):
                modelProgress = progress
                status = .preparingModel(progress: progress)
            case .loading:
                modelProgress = 1
                status = .preparingModel(progress: 1)
            case .ready:
                modelReady = true
                recomputeIdleStatus()
                warmUpTranslationIfNeeded()
            case .failed(let message):
                status = .failed(.init(key: "error.model_prepare", detail: message))
            }
        }
    }

    /// Without an API key every translation uses the local fallback model, so
    /// load it in the background now rather than on the first translate press.
    private func warmUpTranslationIfNeeded() {
        guard preferences.apiKey.isEmpty else { return }
        Task { await engine.warmUpTranslation(report: translationModelReporter()) }
    }

    /// Bridges the engine's load progress onto the main actor for the UI.
    private func translationModelReporter() -> (TranscriptionEngine.PrepareState) -> Void {
        { state in
            Task { @MainActor [weak self] in
                self?.translationModelState = .init(state)
            }
        }
    }

    /// Recomputes the resting status. Anything that can change readiness, such as a
    /// permission landing or a model finishing, routes through here so it cannot
    /// report "ready" while something is still missing.
    private func recomputeIdleStatus() {
        guard !status.isBusy else { return }
        if !hasAccessibilityPermission || !hasMicrophonePermission {
            status = .needsPermissions
        } else if !modelReady {
            status = .preparingModel(progress: modelProgress)
        } else {
            status = .idle
        }
    }

    // MARK: - Dictation

    private func beginDictation(role: HotkeyRole) {
        guard !status.isBusy else { return }
        // Still downloading or specialising: the menu already says so, and
        // recording now would only fail at the transcription step.
        guard modelReady else { return }
        guard hasMicrophonePermission else {
            status = .needsPermissions
            return
        }

        do {
            lastWarning = nil
            let usedFallback = try recorder.start(
                deviceUID: preferences.selectedInputDeviceUID
            )
            if usedFallback {
                lastWarning = .microphoneFallback
            }
            currentMode = role == .translate ? .translate : .dictate
            status = .recording
            play(.start)
        } catch {
            status = .failed(.init(
                key: "error.recording_failed",
                detail: error.localizedDescription
            ))
        }
    }

    private func endDictation() {
        guard case .recording = status else { return }

        let samples = recorder.stop()
        let duration = Double(samples.count) / AudioRecorder.sampleRate

        guard duration >= AudioRecorder.minDuration else {
            recomputeIdleStatus()
            return
        }

        play(.stop)
        status = .transcribing

        let mode = currentMode
        Task { await process(samples, mode: mode) }
    }

    /// TAB pressed while the hotkey is held: cycle the dictation language
    /// (Auto → PL → EN) or the translation style (normal ↔ loose). The choice
    /// is persisted, not just for this one recording, and the pill shows it.
    private func handleTab() {
        guard status == .recording else { return }
        switch currentMode {
        case .dictate:
            preferences.languageMode = preferences.languageMode.next
        case .translate:
            preferences.translationStyle = preferences.translationStyle.next
        }
        play(.tick)
    }

    private func process(_ samples: [Float], mode: DictationMode) async {
        do {
            let final: String

            switch mode {
            case .dictate:
                NSLog("OpenFlow: dictation language mode: %@", preferences.languageMode.rawValue)
                let raw = try await engine.transcribe(
                    samples,
                    language: preferences.languageMode.whisperCode(
                        primaryLanguage: preferences.primaryLanguage
                    ),
                    primaryLanguage: preferences.primaryLanguage.rawValue
                )
                let transcript = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcript.isEmpty else {
                    finishProcessing()
                    return
                }

                if preferences.cleanupEnabled && !preferences.apiKey.isEmpty {
                    status = .cleaning
                    final = await cleanedUp(transcript)
                } else {
                    final = transcript
                }

            case .translate:
                NSLog(
                    "OpenFlow: %@ to English translation, style: %@",
                    preferences.primaryLanguage.rawValue,
                    preferences.translationStyle.rawValue
                )
                let raw = try await engine.transcribe(
                    samples,
                    language: preferences.primaryLanguage.rawValue,
                    primaryLanguage: preferences.primaryLanguage.rawValue
                )
                let transcript = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcript.isEmpty else {
                    finishProcessing()
                    return
                }

                status = .translating
                final = await translated(transcript, fallbackSamples: samples)
            }

            guard !final.isEmpty else {
                finishProcessing()
                return
            }

            lastTranscript = final
            TextInserter.insert(final)
            finishProcessing()
        } catch {
            status = .failed(.init(
                key: "error.processing_failed",
                detail: error.localizedDescription
            ))
        }
    }

    /// `recomputeIdleStatus` deliberately refuses to touch a busy status, so the
    /// end of processing must drop out of the busy state first, otherwise the
    /// app stays on "Rozpoznaję…" forever.
    private func finishProcessing() {
        status = .idle
        recomputeIdleStatus()
    }

    /// Cleanup is a nice-to-have: if it fails, paste the raw transcript rather
    /// than losing what the user just said.
    private func cleanedUp(_ transcript: String) async -> String {
        let service = CleanupService(configuration: preferences.cleanupConfiguration)
        do {
            return try await service.clean(transcript)
        } catch {
            lastWarning = .cleanupFailed(error.localizedDescription)
            return transcript
        }
    }

    /// LLM translation in the chosen style; without an API key, or when the
    /// request fails, Whisper translates locally instead (no style, but the
    /// dictation is never lost).
    private func translated(_ transcript: String, fallbackSamples: [Float]) async -> String {
        if !preferences.apiKey.isEmpty {
            let service = TranslationService(configuration: preferences.translationConfiguration)
            do {
                return try await service.translate(transcript)
            } catch {
                lastWarning = .translationAPIFailed(error.localizedDescription)
            }
        }

        do {
            return try await engine.translateNatively(
                fallbackSamples,
                language: preferences.primaryLanguage.rawValue,
                report: translationModelReporter()
            )
        } catch {
            lastWarning = .translationFailed(
                error.localizedDescription,
                preferences.primaryLanguage
            )
            return transcript
        }
    }

    // MARK: - Feedback

    private enum Cue {
        case start, stop, tick
    }

    private func play(_ cue: Cue) {
        guard preferences.playSounds else { return }
        let name: String
        switch cue {
        case .start: name = "Tink"
        case .stop: name = "Pop"
        case .tick: name = "Morse"
        }
        guard let sound = NSSound(named: name) else { return }
        sound.volume = 0.35
        sound.play()
    }
}
