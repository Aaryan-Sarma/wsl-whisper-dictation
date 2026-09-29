#!/usr/bin/env bash
# duration.sh - how does latency scale with how long you talk?
#
# whisper pads every clip to a 30s window, so the ENCODER cost is flat up to 30s.
# The DECODER, though, scales with how many words you actually say - so latency
# grows roughly linearly with speech length, ~6x realtime on a 4-thread laptop
# CPU. This measures it directly, and shows the step where a second 30s window
# opens.
set -uo pipefail

URL="http://127.0.0.1:8178/inference"
VOCAB="$(tr -d '\n' < "$HOME/voice/vocab.txt")"
GEN="${VFLOW_GEN:-C:\\path\\to\\gen-speech.ps1}"
TMP_WIN="${VFLOW_TMP_WIN:-C:\\Users\\Public}"
TMP_WSL="${VFLOW_TMP_WSL:-/mnt/c/Users/Public}"
PWSH="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

SENT="The deploy to staging failed last night, so check the Terraform plan and the Kubernetes cluster before the rollback. "

printf '%-8s %-9s %-9s %s\n' "repeats" "audio_s" "asr_s" "ratio"
for n in 1 2 4 6 9; do
  text=""
  for _ in $(seq 1 "$n"); do text="$text$SENT"; done

  "$PWSH" -NoProfile -File "$GEN" -Text "$text" -Out "$TMP_WIN\\vflow_dur.wav" >/dev/null 2>&1
  wav="$TMP_WSL/vflow_dur.wav"
  [ -s "$wav" ] || { echo "  TTS failed at n=$n"; continue; }

  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$wav" 2>/dev/null)
  sleep 4    # cooldown: mobile CPUs throttle, back-to-back runs decay

  s=$(date +%s.%N)
  curl -s --max-time 180 -F "file=@$wav" -F "response_format=text" -F "temperature=0" \
       -F "prompt=$VOCAB" "$URL" >/dev/null
  e=$(date +%s.%N)

  awk -v n="$n" -v d="$dur" -v a="$s" -v b="$e" \
      'BEGIN{el=b-a; printf "%-8s %-9.1f %-9.2f %.2fx realtime\n", n, d, el, d/el}'
  rm -f "$wav"
done
