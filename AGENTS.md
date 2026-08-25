# OpenFlow Agent Guide

## Project

OpenFlow is a native macOS 14+ menu bar application for push-to-talk dictation.
It records microphone audio as 16 kHz mono samples, transcribes locally with
WhisperKit and Core ML, optionally cleans or translates transcript text through
an OpenAI-compatible API, then pastes the result into the active application.

The codebase uses SwiftUI for views and AppKit, Core Graphics, Core Audio, and
AVFoundation for macOS integration. `AppState` is the main-actor state machine.
`TranscriptionEngine` is an actor that owns Whisper pipelines.

Ownership boundaries:

- `AppState` owns application orchestration and UI-visible state.
- `AppStateModels` owns state and notice value types.
- `AppStatePresentation` maps state to localized UI presentation.
- `TranscriptionEngine` exclusively owns and uses Whisper pipeline instances.
- `LanguageDetector` owns pure language probability and selection policy.
- `TranscriptPostprocessor` owns deterministic transcript filtering.
- `ChatCompletionClient` owns shared HTTP transport and response parsing.
- `CleanupService` and `TranslationService` own their prompts and text styles.

## Commands

Run the narrowest relevant check, then the full test suite before handing off.

```sh
swift test
swift build -c release
make debug
make build
```

`make install` writes to `/Applications`, so run it only when the user asks.

## Critical Invariants

- Audio stays on the Mac and in memory. Do not upload or persist recordings.
- A failed optional cleanup must fall back to the raw local transcript.
- A failed API translation must fall back to local Whisper translation, then to
  the source transcript if local translation also fails.
- Only one recording or processing flow may be active at a time.
- A stale asynchronous model load must never replace the newest model choice.
- Clipboard restoration must not overwrite content copied by the user after
  OpenFlow inserted its temporary transcript.
- Missing selected microphones fall back to the system input.
- Keep Accessibility and Microphone permission handling restart-free.
- Preserve the 300-second recording memory bound and the short-tap guard.

## Code Style

- Match existing Swift and SwiftUI patterns. Prefer focused, surgical changes.
- Keep UI state changes on `@MainActor` and model work inside actors.
- Treat actor methods as reentrant across every `await`.
- Do not pass Whisper pipeline instances outside `TranscriptionEngine`.
- Avoid force unwraps, speculative abstractions, and unrelated cleanup.
- Preserve backward compatibility in `UserDefaults` keys and migrations.
- Never use em dashes in source comments, documentation, or user-facing text.

## Tests

- Use Swift Testing in `Tests/OpenFlowTests`.
- Test descriptions must start with `it("should ...")`, following the existing
  escaped form such as `@Test("it(\"should preserve text\")")`.
- Keep one `#expect` statement per test.
- Add regression coverage for changed pure logic. For hardware or AppKit paths,
  extract only the smallest deterministic decision that needs coverage.

## Git Safety

- Do not commit without explicit user approval.
- Do not push without explicit confirmation.
- Never delete branches, force push, or amend pushed commits.
- Preserve pre-existing worktree changes and do not revert unrelated edits.
- Use English Conventional Commit messages: `<type>(<scope>): <description>`.
- Do not add AI tools as authors, co-authors, or commit trailers.
