#!/usr/bin/env bash
# vflow - local voice dictation for WSL/Windows (terminal fallback).
#
#   Records via Windows MCI (winmm.dll, no third-party exe -> AppLocker safe),
#   transcribes locally with whisper.cpp, puts text on the Windows clipboard.
#
# This is the manual, fixed-duration path. The everyday tool is the hotkey
# daemon (Ctrl+Alt+Space) - see README.md. Keep this working: it is how you
# diagnose the pipeline when the daemon misbehaves, since it exercises the same
# recording and transcription route with none of the Windows-side machinery.
#
# usage: vflow.sh [seconds]        default 8
set -uo pipefail

DUR="${1:-8}"
ROOT="$HOME/voice"
WCPP="$ROOT/whisper.cpp"
MODEL="$WCPP/models/ggml-base.en.bin"
THREADS=4                      # 4 physical cores; 8 threads is ~5x SLOWER (SMT contention)
URL="http://127.0.0.1:8178/inference"

WIN_USER="${WIN_USER:-$USER}"    # override if your Windows username differs from your WSL one
WAV_WIN="C:\\Users\\${WIN_USER}\\AppData\\Local\\Temp\\vflow.wav"
WAV_WSL="/mnt/c/Users/${WIN_USER}/AppData/Local/Temp/vflow.wav"

[ -f "$MODEL" ] || { echo "vflow: missing model $MODEL" >&2; exit 1; }
VOCAB="$(tr -d '\n' < "$ROOT/vocab.txt" 2>/dev/null || true)"

rm -f "$WAV_WSL"

# ---- record (Windows side, via signed system DLL) --------------------------
echo "vflow: recording ${DUR}s - speak now..." >&2
powershell.exe -NoProfile -Command "
Add-Type -Namespace W -Name M -MemberDefinition '[DllImport(\"winmm.dll\", CharSet=CharSet.Auto)] public static extern int mciSendString(string c, System.Text.StringBuilder r, int l, System.IntPtr h);'
\$sb = New-Object System.Text.StringBuilder 512
function M(\$c){ [void][W.M]::mciSendString(\$c,\$sb,512,[IntPtr]::Zero) }
M 'open new type waveaudio alias vf'
M 'set vf bitspersample 16 channels 1 samplespersec 16000 alignment 2 bytespersec 32000 format tag pcm'
M 'record vf'
Start-Sleep -Seconds $DUR
M 'stop vf'
M 'save vf \"$WAV_WIN\"'
M 'close vf'
" >/dev/null 2>&1

[ -s "$WAV_WSL" ] || { echo "vflow: no audio captured" >&2; exit 1; }

# ---- signal check ----------------------------------------------------------
PEAK=$(ffmpeg -hide_banner -i "$WAV_WSL" -af volumedetect -f null - 2>&1 \
       | sed -n 's/.*max_volume: \(-\?[0-9.]*\) dB.*/\1/p')
echo "vflow: peak ${PEAK} dB" >&2
if [ -n "$PEAK" ] && awk "BEGIN{exit !($PEAK < -80)}"; then
  echo "vflow: SILENT - mic muted or wrong default device" >&2
  exit 2
fi

# ---- transcribe ------------------------------------------------------------
# Prefer the resident server (model already in RAM, ~0.6s cheaper per call);
# fall back to the one-shot CLI so this still works with the server stopped.
TXT=""
if timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/8178' 2>/dev/null; then
  TXT=$(curl -s --max-time 180 \
          -F "file=@$WAV_WSL" -F "response_format=text" -F "temperature=0" \
          -F "no_timestamps=true" -F "language=en" -F "prompt=$VOCAB" "$URL")
else
  echo "vflow: server down, using one-shot CLI (slower)" >&2
  TXT=$("$WCPP/build/bin/whisper-cli" -m "$MODEL" -f "$WAV_WSL" \
          -t "$THREADS" -np -nt --prompt "$VOCAB" 2>/dev/null)
fi

TXT=$(printf '%s' "$TXT" | tr '\n' ' ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/  */ /g')

# Recorded audio may contain commercial/patient-adjacent content - do not leave
# it sitting in Temp.
rm -f "$WAV_WSL"

[ -n "$TXT" ] || { echo "vflow: empty transcript" >&2; exit 3; }

# ---- post-transcription corrections ----------------------------------------
# Deterministic fixes for terms no prompt can rescue (homophones etc).
if [ -f "$ROOT/corrections.txt" ]; then
  while IFS=$'\t' read -r pat rep; do
    case "$pat" in ''|'#'*) continue ;; esac
    [ -n "$rep" ] || continue
    TXT=$(printf '%s' "$TXT" | sed -E "s/${pat}/${rep}/Ig")
  done < "$ROOT/corrections.txt"
fi

printf '%s' "$TXT" | clip.exe 2>/dev/null
echo "$TXT"
