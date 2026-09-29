# wsl-whisper-dictation

Local, offline voice dictation for Windows + WSL. Speak, and the text lands on
your clipboard to paste. Transcription runs entirely on your machine with
[whisper.cpp](https://github.com/ggerganov/whisper.cpp) — no cloud, no account,
nothing leaves the box.

Built for a work laptop where the built-in Windows voice typing was disabled by
policy and installing third-party apps wasn't an option — but everything here is
generic.

## What it does

- Records a short clip via a signed Windows system DLL (`winmm.dll` MCI) — no
  third-party recorder binary.
- Transcribes it with a resident `whisper.cpp` server inside WSL, kept warm so
  you pay only the inference cost, not the model load.
- Biases the model toward your own jargon with a prompt vocabulary, and applies
  deterministic post-transcription fixes for stubborn homophones.
- Puts the result on the Windows clipboard. You paste it with Ctrl+V.

It is deliberately **manual and clipboard-only** — see the note below.

## Why there's no global hotkey / auto-paste

An earlier version used a background listener for a global hotkey and injected
the text into the focused app automatically. That combination — watching the
keyboard globally and synthesising keystrokes into other apps — is
behaviourally indistinguishable from a keylogger, and endpoint security (EDR)
on a managed machine will correctly flag and block it. That's the security
control working as intended, not a bug to route around.

So this repo does the honest thing: an explicit, user-invoked recording that
only ever writes to your clipboard. You keep the paste in your own hands. If
you're on an unmanaged personal machine and want a global hotkey, wire the same
`vflow.sh` up to a launcher you trust — but that part is on you.

## Requirements

- Windows 10/11 with WSL2 (tested on Ubuntu).
- `networkingMode=mirrored` in `.wslconfig` so Windows can reach the WSL server
  on `127.0.0.1` (or adapt the URL).
- `ffmpeg` in WSL (`sudo apt install ffmpeg`) for the silence check.
- A whisper.cpp build with `whisper-server`, and a model (`ggml-base.en.bin` is
  the accuracy/speed sweet spot; `tiny.en` is faster, `small.en` is slower).

## Setup

```bash
# 1. build whisper.cpp and download a model (see its README)
# 2. put this repo's scripts on your PATH, e.g. ~/bin
# 3. start the resident server
vflow-server start          # or: install vflow-whisper.service as a user unit

# 4. make your own vocab / corrections from the examples
cp vocab.example.txt        ~/voice/vocab.txt
cp corrections.example.txt  ~/voice/corrections.txt
```

Then, to dictate:

```bash
vflow.sh 8        # records 8 seconds, transcribes, copies to clipboard
```

## Files

| file | purpose |
|------|---------|
| `vflow.sh` | record → transcribe → clipboard (the tool) |
| `vflow-server` | `start\|stop\|restart\|status\|ensure` for the whisper server |
| `vflow-whisper.service` | systemd user unit to keep the server resident |
| `vocab.example.txt` | prompt vocabulary — **most-critical terms LAST** (see below) |
| `corrections.example.txt` | post-transcription regex fixes (`regex<TAB>replacement`) |
| `tests/gen-speech.ps1` | Windows SAPI text-to-speech, for mic-free testing |
| `tests/accuracy.sh` | term recall, bare vs prompted |
| `tests/bench.sh` | latency, interleaved + cooled to beat CPU throttling |
| `tests/duration.sh` | latency vs speech length |
| `tests/vocab-order.sh` | shows that prompt position changes recall |

## Tuning notes (things I learned the hard way)

- **Latency is ~6× realtime and roughly linear**, with a ~1.7 s floor (4-thread
  mobile CPU, `base.en`). ~15–25 s per take is the sweet spot: the 30 s encoder
  window is flat, but the decoder scales with word count, so very long takes
  aren't free.
- **A vocab prompt roughly doubles recall on domain jargon**, for a small latency
  cost. Worth it.
- **Prompt order matters — whisper weights the END of the prompt more.** Put
  generic words first and the terms you most need correct last. This alone can
  fix a term that otherwise transcribes wrong.
- **Some terms no prompt can fix** (genuine homophones). Those go in
  `corrections.txt` as regex rules. Keep that list short and high-confidence — a
  bad rule silently corrupts output.
- **The Windows clipboard is racy.** If you extend this to set-then-read the
  clipboard programmatically, verify the write landed before relying on it;
  naive `Set-Clipboard` can return before the data is readable.
- **Benchmark honestly on a laptop:** mobile CPUs throttle, so back-to-back runs
  decay. `bench.sh` interleaves variants, cools between runs, and reports the
  minimum.

## License

MIT — see [LICENSE](LICENSE).
