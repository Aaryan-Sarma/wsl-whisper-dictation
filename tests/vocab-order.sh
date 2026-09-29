#!/usr/bin/env bash
# vocab-order.sh - does prompt ORDER change which terms whisper honours?
#
# Finding: whisper's attention over a long prompt is NOT uniform - terms near the
# END are honoured more reliably. If a term you listed still comes out wrong,
# moving it to the tail of vocab.txt often fixes it. This demonstrates it.
set -uo pipefail

URL="http://127.0.0.1:8178/inference"
FULL="$(tr -d '\n' < "$HOME/voice/vocab.txt")"
GEN="${VFLOW_GEN:-C:\\path\\to\\gen-speech.ps1}"
TMP_WIN="${VFLOW_TMP_WIN:-C:\\Users\\Public}"
TMP_WSL="${VFLOW_TMP_WSL:-/mnt/c/Users/Public}"
PWSH="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

STUBBORN="Kubernetes, Terraform, PostgreSQL"

CASES=(
  "Compare Kafka and PostgreSQL throughput under load.|PostgreSQL"
  "The Terraform plan rebuilt the Kubernetes cluster in production.|Terraform Kubernetes"
)

# 1 = as-is; 2 = stubborn terms moved to the END (recency); 3 = short prompt only
declare -A PROMPTS=(
  [1-asis]="$FULL"
  [2-tail]="$FULL $STUBBORN."
  [3-short]="$STUBBORN, Kafka, Grafana, Prometheus, Datadog, GraphQL, gRPC."
)

for case in "${CASES[@]}"; do
  text="${case%%|*}"; terms="${case##*|}"
  wav_win="$TMP_WIN\\vflow_vo.wav"; wav_wsl="$TMP_WSL/vflow_vo.wav"
  "$PWSH" -NoProfile -File "$GEN" -Text "$text" -Out "$wav_win" >/dev/null 2>&1
  echo "want: $text"
  for key in $(printf '%s\n' "${!PROMPTS[@]}" | sort); do
    out=$(curl -s --max-time 90 -F "file=@$wav_wsl" -F "response_format=text" \
          -F "temperature=0" -F "prompt=${PROMPTS[$key]}" "$URL" \
          | tr -s ' \n' ' ' | sed 's/^ *//; s/ *$//')
    hits=0; total=0
    for t in $terms; do total=$((total+1)); grep -qi -- "$t" <<<"$out" && hits=$((hits+1)); done
    printf "  %-9s (%d/%d): %s\n" "$key" "$hits" "$total" "$out"
  done
  echo
  rm -f "$wav_wsl"
done
