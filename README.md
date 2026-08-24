# OpenFlow

Push-to-talk dictation for macOS, in Polish and English, with on-the-fly
PL→EN translation. A personal replacement for Wispr Flow: no subscription,
speech recognition fully local (audio never leaves the machine), and Polish
quality chosen by measurement rather than marketing.

Hold a key, talk, release. The text lands in whatever app has focus: editor,
browser, Slack, terminal, anywhere.

The app lives in the menu bar only (a microphone icon), with no Dock icon.

## Features at a glance

- **Push-to-talk dictation** (right ⌘ by default): speech becomes text in the
  language you spoke. Polish and English, detected automatically.
- **On-the-fly translation** (right ⌃ by default): speak Polish, English gets
  pasted.
- **Text styles, separate for dictation and translation**: Normal (polished
  prose) and Loose (chat style: lowercase, no full stops).
- **TAB while recording**: cycles the dictation language (Auto/PL/EN) or the
  translation style, live, without releasing the key.
- **Hotkey recorder**: click the button, press a key, done.
- **Developer profile**: feature, PR, commit, deploy stay in English and get
  repaired when the recogniser mangles them ("pi ar" → "PR").
- **AI cleanup**: punctuation, removing "uhm"s, fixing Polish inflection.
  DeepSeek V4 Flash via OpenRouter by default, pennies per month.
- **Everything has a fallback**: no network or no API key never blocks
  dictation.
- **Privacy**: transcription is 100% local (Whisper on the Neural Engine),
  the API key lives only in an environment variable and is never stored.

## Quick start

```sh
git clone <this-repo> && cd open-flow
make install                                   # builds and copies to /Applications
launchctl setenv OPENROUTER_API_KEY sk-or-...  # optional, for the AI features
open /Applications/OpenFlow.app
```

Then:

1. Grant **Microphone** access and **Accessibility**
   (System Settings → Privacy & Security → Accessibility).
2. Wait for the model download (~1.5 GB) and the one-time Core ML
   specialisation (~8 minutes, first launch only).
3. Hold right ⌘, say something in Polish, release. The text gets pasted.
4. Enable "Poprawiaj tekst przez AI" in the menu if you set the key.

## Features in detail

### Two push-to-talk hotkeys

| Hotkey (default) | Action |
| --- | --- |
| Right ⌘ | **Dictation**: text in the language you spoke (PL or EN) |
| Right ⌃ | **Translation**: speak Polish, English gets pasted |

Both hotkeys are set with a click-then-press recorder. Any single key works:
a modifier (right ⌘, right ⌃, Fn...) or a regular key (F13...). A regular key
held as push-to-talk is swallowed by the app, so it never types characters
into the active window. Escape cancels the recorder, the recorder disarms
itself after 10 seconds, and TAB cannot be a hotkey because it is reserved
for cycling (below). The same key cannot serve both roles.

While recording, a pill floats near the bottom of the screen showing the
state ("Słucham…", "Rozpoznaję…", "Poprawiam…", "Tłumaczę…") and the active
language or style. It is visible over full-screen apps too.

### TAB while recording

While holding a hotkey, press TAB:

- during **dictation** it cycles the language: Auto → PL → EN → Auto...
- during **translation** it toggles the style: Normal ↔ Loose

The choice shows live on the pill and is persistent (it stays for future
dictations, until changed with TAB or in Settings). TAB is consumed by the
app, so it neither moves focus nor triggers the ⌘Tab switcher.

Forcing PL/EN skips language detection. Useful when auto-detection guesses
wrong or when you dictate short snippets.

### Dictation and translation styles

Dictation (the style is applied by the AI cleanup pass):

- **Normal**: full punctuation, capital letters, polished prose.
- **Loose**: like a chat message. Everything lowercase (acronyms like PR, API
  and code identifiers keep their casing), no sentence-ending periods,
  thoughts separated with commas or line breaks.

Translation:

- **Normal**: faithful and professional. For PR descriptions, tickets,
  documentation, email.
- **Loose**: relaxed and idiomatic, like a native-speaker developer on
  WhatsApp or Slack, lowercase and without full stops. The model may rephrase
  a sentence as long as the meaning survives.

Both styles switch in the menu bar popover or in Settings; the translation
style additionally with TAB while recording.

### Developer profile

The cleanup and translation prompts assume the speaker is a software
developer. English tech terms (feature, PR, merge request, commit, deploy,
branch, code review, backlog, standup, endpoint, bug...) stay in English,
are never polonised or translated, and forms mangled by speech recognition
get repaired ("pi ar" becomes "PR", "komit" becomes "commit").

On top of that there is a **personal dictionary**: free-form lines appended
to the prompts (name spellings, project names, jargon), edited in Settings.

### AI cleanup (optional)

A second pass after transcription: punctuation, capitalisation, removing
"yyy"/"eee" and false starts, fixing Polish inflection and diacritics.
Defaults to DeepSeek V4 Flash via OpenRouter; any OpenAI-compatible API works
(base URL and model are editable in Settings). If the API does not answer
within the timeout, the raw transcript is pasted.

Cost: one dictation with cleanup is ~$0.00001, a translation ~$0.00003.
Heavy daily use adds up to a few cents per month.

### There is always a fallback

| Scenario | What happens |
| --- | --- |
| No API key / no network during dictation | the raw Whisper transcript is pasted |
| No API key / network error during translation | local Whisper translates (task translate), no style, but offline |
| Recording shorter than 0.35 s | ignored (accidental key brush) |
| Near-silence | known Whisper hallucinations ("Thank you.", amara.org credits...) are stripped |
| Clipboard | snapshotted before pasting and restored 0.4 s later |

## How it works

```
hold hotkey ──▶ AVAudioEngine records 16 kHz mono
                        │
release ────────────────▼
              WhisperKit / Core ML on the Neural Engine
                        │  language: auto (pl/en only) or forced via TAB
                        ▼
   dictation:  optional LLM pass (cleanup + style, 4 s timeout,
               falls back to the raw text)
   translation: LLM pass in the chosen style (falls back to Whisper's
               built-in local translation)
                        │
                        ▼
          pasted into the frontmost app via ⌘V
          (the clipboard is snapshotted and restored)
```

Three details decide the Polish quality:

- **The language detector is constrained to Polish and English.** Whisper's
  unconstrained detector regularly labels Polish speech as Czech or Slovak,
  which ruins the transcript. OpenFlow compares only the `pl` and `en`
  probabilities.
- **Detection is biased towards Polish.** English wins only with a clear
  lead (a 0.2 margin). Polish dev-speak full of terms like "code review"
  drags the detector towards EN, and a wrong EN is the worst failure mode:
  Whisper then *translates* Polish speech instead of transcribing it.
  A wrong PL on English speech is merely a garbled transcript, redone with
  TAB→EN.
- **The default model is `large-v3-turbo`, chosen by measurement.** Turbo
  prunes the decoder from 32 layers to 4, which is usually described as
  costing accuracy in non-English languages. On Polish speech on this machine
  it transcribed **3.7× faster** (speed factor 6.6 vs 1.8, 39 vs 10 tokens/s)
  and got the diacritics and inflection at least as right as full large-v3.
  Full large-v3 stays available in Settings.

## Requirements

- macOS 14 or newer, Apple Silicon
- Xcode (for the Swift toolchain)
- ~1.5 GB of disk for the default model (more for full precision)
- an OpenRouter account (or any OpenAI-compatible API) for the AI features;
  without one, offline dictation and local translation still work

## Building

```sh
make build     # compile + assemble + codesign build/OpenFlow.app
make run       # the above, then launch
make install   # copy to /Applications
make logs      # tail the app's log output
make clean     # remove build artifacts
```

`Scripts/bundle.sh` signs the app with your Apple Development identity. That
matters: macOS ties the Microphone and Accessibility grants to the code
signature, so an ad-hoc signature would mean re-approving the app after every
rebuild. Override with `IDENTITY=...` if you have several.

## First run

1. **Microphone** consent (the standard system prompt).
2. **Accessibility** consent (System Settings → Privacy & Security →
   Accessibility). Needed twice over: to see the hotkeys globally and to send
   ⌘V to other apps. The app detects the grant by itself, no restart needed.
3. The speech model (~1.5 GB) downloads into
   `~/Library/Application Support/OpenFlow/models`. Progress shows in the menu.

Then be patient exactly once. Core ML has to "specialise" the model for your
chip; for a model this size that took **around 8 minutes** here. Apple caches
the result outside the app, so every later launch loads in seconds. The same
wait returns after switching models or when a macOS update evicts the cache.

Once the cache is built, the app never touches the network for transcription.
It only re-downloads when the model files are genuinely missing.

## API key (environment variable only)

The key is never stored by the app: not in settings, not in the Keychain.
It is read exclusively from the `OPENROUTER_API_KEY` variable.

GUI apps inherit launchd's environment rather than the shell's, so an
`export` in `.zshrc` is not enough:

```sh
launchctl setenv OPENROUTER_API_KEY sk-or-...   # until the next reboot
```

To survive reboots, put that line in a LaunchAgent or a login script, or
launch the app from a terminal with the variable exported. The key status
("Wczytany ze środowiska" / "Nie znaleziono") shows in Settings on the AI tab.

## Settings

**Hotkeys.** Click-then-press recorder for both. Right ⌥ Option is a poor
choice on the Polish Pro layout, where it types ą ć ę ł ń ó ś ź ż. The 🌐 Fn
key works after setting System Settings → Keyboard → "Press 🌐 key to" →
"Do Nothing".

**Dictation language.** Auto / Polish / English. The same thing TAB cycles.

**Dictation style.** Normal / Loose. Loose writes lowercase without periods;
requires AI cleanup to be enabled.

**Translation style.** Normal / Loose. The same thing TAB toggles while the
translate hotkey is held.

**Speech model.** Defaults to `large-v3-turbo`. Switching models triggers a
fresh download and a fresh Core ML specialisation (minutes, once).

**AI cleanup.** Toggle, base URL, model name, timeout. Disabled until a key
is present in the environment.

**Personal dictionary.** Free-form lines appended to the AI prompts: name
spellings, project names, jargon. One rule per line.

**Behaviour.** Start/stop and TAB-cycle sounds, launch at login.

Quick access to the language, both styles and the AI toggle also lives in the
menu bar popover, next to the last transcript and its copy button.

## Troubleshooting

**I speak Polish but English comes out.** Three possibilities: you are
holding the translate hotkey instead of dictation (the pill shows "PL→EN"),
TAB switched the language to EN (the pill shows "EN"), or auto-detection
guessed wrong. Check the log line `detekcja języka: ... (pl=... en=...)`:

```sh
make logs        # or: log stream --predicate 'process == "OpenFlow"'
```

Immediate workaround: TAB to force PL.

**Hotkeys do not react.** Accessibility consent is missing, or it lapsed
after a rebuild with a different signing identity. Check the badge in
Settings.

**"Ładowanie modelu…" takes long after a macOS update.** The system evicted
the Core ML cache; specialisation runs again (~8 minutes), once.

**AI cleanup is greyed out.** No key in the environment: `launchctl setenv`,
then restart the app.

**"Thank you." or amara.org credits get pasted.** Whisper hallucinates on
silence; known patterns are stripped, report new ones (add them to the list
in `TranscriptionEngine.swift`).

## Code layout

| File | Role |
| --- | --- |
| `AppState.swift` | Orchestration: hotkey → record → transcribe → clean/translate → paste |
| `HotkeyManager.swift` | Global `CGEventTap`: two push-to-talk keys, TAB, hotkey recorder |
| `AudioRecorder.swift` | `AVAudioEngine` capture, resampled to 16 kHz mono |
| `TranscriptionEngine.swift` | WhisperKit: download, load, transcription, local translation |
| `CleanupService.swift` | Cleanup pass with style (OpenAI-compatible API) |
| `TranslationService.swift` | PL→EN translation, normal or loose style |
| `TextInserter.swift` | Clipboard snapshot / paste / restore |
| `RecordingIndicator.swift` | Floating pill, visible over full-screen apps |
| `Preferences.swift` | UserDefaults + env API key + login item |
| `MenuContentView.swift` | Menu bar popover |
| `SettingsView.swift` | Settings window |

Technical details that are easy to lose:

- The event tap is **active** (`.defaultTap`), not listen-only, because TAB
  and regular-key hotkeys must be consumed before the frontmost app sees
  them. Modifier events (flagsChanged) always pass through.
- The system disables a tap that blocks too long; the callback handles
  `tapDisabledByTimeout` and re-enables it.
- Pasting snapshots the clipboard, swaps it, sends a synthetic ⌘V and
  restores the previous contents 0.4 s later.
- Models live in Application Support, not ~/Documents (the HuggingFace
  client's default location is wrong for multi-gigabyte files).
- Permissions are polled every 2 s, so granting them in System Settings arms
  the app without a restart.

## Known limits

- Apple Silicon only in practice; Core ML on Intel would be far slower.
- The app is not sandboxed, because a sandboxed process cannot install the
  global event tap that push-to-talk needs.
- Recordings are capped at 5 minutes, so a stuck key cannot grow the buffer
  without bound.
- Translation forces Polish transcription. If you start speaking English
  while holding the translate hotkey, the result will be mangled; the pill
  always shows which mode is active.
- Whisper with a forced EN language on Polish speech tends to translate
  instead of transcribing; that is model behaviour, not an app bug. Auto mode
  or forced PL both handle it.
