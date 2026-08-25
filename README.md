<div align="center">

# OpenFlow

### Your voice, already typed.

Hold a key. Speak. Release. Your words appear in the app you are using.

**Local speech recognition. Five interface languages. No subscription.**

`macOS 14+` · `Apple Silicon` · `Whisper large-v3-turbo` · `Open source`

</div>

---

## Stop typing. Keep working.

OpenFlow is push-to-talk dictation for macOS. It lives in the menu bar and
works wherever your cursor works: editors, browsers, Slack, terminals, tickets
and documentation.

```text
hold ⌘  →  speak  →  release  →  text appears
```

Your audio stays on your Mac. Whisper runs locally on the Neural Engine. An
optional AI pass can clean or translate the resulting text, but audio is never
uploaded.

## Start in 60 seconds

```sh
git clone https://github.com/DevWichrowski/open-flow.git
cd open-flow
make install
open /Applications/OpenFlow.app
```

Then:

1. Grant Microphone and Accessibility permissions.
2. Let OpenFlow download the speech model once.
3. Hold **Right ⌘**, speak, then release.
4. Keep working. The transcript is pasted at your cursor.

The first model preparation can take several minutes. After that, transcription
works offline.

## Two keys. The whole workflow.

| Hold | What happens |
| --- | --- |
| **Right ⌘** | Dictates in your primary language or English |
| **Right ⌃** | Translates your primary language into English |
| **TAB while holding Right ⌘** | Cycles `Auto → Primary → EN` |
| **TAB while holding Right ⌃** | Switches between Normal and Casual translation |

Both hotkeys are editable. Modifier keys, function keys and regular keys are
supported.

## Your language, your setup

Choose Polish, Italian, Spanish or Bulgarian as your **Primary Language**. English always
stays available.

| Primary Language | Dictation modes | Translation |
| --- | --- | --- |
| Polish | `Auto · PL · EN` | `PL → EN` |
| Italian | `Auto · IT · EN` | `IT → EN` |
| Spanish | `Auto · ES · EN` | `ES → EN` |
| Bulgarian | `Auto · BG · EN` | `BG → EN` |

Auto mode compares only your primary language with English. This avoids the
common Whisper problem of confusing similar languages during short dictation.

The entire interface can switch instantly between:

`English` · `Polski` · `Italiano` · `Español` · `Български`

## Small app. Serious details.

### Speak naturally

OpenFlow removes the friction between an idea and written text. Short messages,
long explanations and technical notes all use the same hold, speak, release
gesture.

### Keep developer language intact

Terms such as `feature`, `PR`, `commit`, `deploy`, `branch`, `code review` and
code identifiers stay in English. The optional cleanup pass can repair terms
that speech recognition heard phonetically.

### Pick the right microphone

Use **System Default** or select a specific built-in, USB or Bluetooth input.
If the selected microphone disappears, OpenFlow temporarily falls back to the
system input instead of blocking dictation.

### Choose how the result sounds

- **Normal:** punctuation, capitals and polished prose.
- **Casual:** lowercase chat style without sentence-ending periods.

Dictation styling uses AI Cleanup. Translation styling uses the same optional
API connection.

### See what was pasted

The menu shows the latest transcript in a readable, scrollable area. Select it
directly or copy it with one click.

## Private by design

```text
microphone
    ↓
16 kHz audio in memory
    ↓
WhisperKit + Core ML on your Mac
    ↓
optional text-only AI cleanup or translation
    ↓
paste at the cursor
```

- Audio never leaves the machine.
- Recordings are not saved.
- The API key is read from an environment variable and is never stored by the app.
- AI Cleanup is off by default.
- Clipboard contents are restored after the transcript is pasted.

## Optional AI Cleanup

Without AI Cleanup, OpenFlow pastes the raw local Whisper transcript. With it,
OpenFlow can fix punctuation, remove filler sounds and correct obvious recognition
mistakes without changing the meaning or language.

Set an OpenRouter key:

```sh
launchctl setenv OPENROUTER_API_KEY sk-or-...
```

Restart OpenFlow, then enable **Improve text with AI**. DeepSeek V4 Flash is the
default model, but any OpenAI-compatible endpoint and model can be configured.

You can also add personal spelling rules for names, projects and team jargon in
the Personal Dictionary.

## Nothing should block dictation

| Situation | OpenFlow response |
| --- | --- |
| AI API unavailable | Pastes the raw local transcript |
| Translation API unavailable | Translates locally with Whisper large-v3 (~950 MB, because turbo cannot translate); without an API key it is loaded at startup |
| Selected microphone disconnected | Uses the current system input |
| Recording shorter than 0.35 seconds | Ignores the accidental tap |
| Known silence hallucination | Removes it before pasting |
| Previous clipboard content | Restores it after insertion |

## Build commands

```sh
make debug      # fast signed debug build
make build      # signed release build in build/OpenFlow.app
make install    # build and copy to /Applications
make logs       # stream OpenFlow logs
```

Requirements:

- macOS 14 or newer
- Apple Silicon
- Xcode command-line tools
- Approximately 1.5 GB for the default speech model

## Troubleshooting

<details>
<summary><strong>The hotkeys do nothing</strong></summary>

Grant Accessibility permission in System Settings. If the app was rebuilt with
a different signing identity, macOS may require permission again.

</details>

<details>
<summary><strong>The wrong language is detected</strong></summary>

Press TAB while holding the dictation key and force Primary or EN. Very short
phrases and sentences dominated by English technical terms are hardest to detect.

</details>

<details>
<summary><strong>Model loading takes a long time</strong></summary>

Core ML prepares the model for the current Apple chip. This happens after the
first download and can happen again after a macOS update clears the cache.

</details>

<details>
<summary><strong>AI Cleanup is disabled</strong></summary>

Set `OPENROUTER_API_KEY` with `launchctl setenv`, then restart OpenFlow.

</details>

## Under the hood

<details>
<summary><strong>Architecture and implementation notes</strong></summary>

- `AVAudioEngine` captures the selected microphone and converts it to 16 kHz mono.
- WhisperKit runs `large-v3-turbo` locally through Core ML.
- Auto detection runs one Whisper decoder step over the first 30 seconds, takes
  the full language distribution and compares the configured primary language
  with English using a conservative English margin.
- `large-v3-turbo` was fine-tuned on transcription only, so offline translation
  loads a compact `large-v3` next to it: at startup when there is no API key,
  otherwise on the first fallback. The menu and the indicator show that load,
  since a cold Core ML load of large-v3 takes a few minutes.
- A global `CGEventTap` handles both push-to-talk keys and consumes TAB while recording.
- The recording indicator uses a floating AppKit panel visible over full-screen apps.
- Models live in Application Support and are downloaded only when missing.
- Transcripts are inserted through a temporary clipboard swap, then the previous
  clipboard is restored.

</details>

---

<div align="center">

**One key between thought and text.**

</div>
