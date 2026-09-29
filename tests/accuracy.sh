#!/usr/bin/env bash
# accuracy.sh - regression-test transcription quality on your domain vocabulary.
#
# Synthesizes each sentence with Windows SAPI, transcribes it twice (bare vs
# with the vocab.txt prompt), and scores how many of the *target terms* survived.
# That is the number that matters: base.en will happily write "post gress" or
# "cuber netties" unless primed.
#
# Needs: the whisper server up (see vflow-server), and gen-speech.ps1 reachable
# from Windows. Set VFLOW_GEN to its Windows path. Everything runs locally.
#
# usage: accuracy.sh
set -uo pipefail

URL="http://127.0.0.1:8178/inference"
VOCAB="$(tr -d '\n' < "$HOME/voice/vocab.txt")"
GEN="${VFLOW_GEN:-C:\\path\\to\\gen-speech.ps1}"
TMP_WIN="${VFLOW_TMP_WIN:-C:\\Users\\Public}"
TMP_WSL="${VFLOW_TMP_WSL:-/mnt/c/Users/Public}"
PWSH="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

# sentence|space-separated terms that must appear (case-insensitive)
CASES=(
  "The deploy to staging failed so we rolled back the pipeline.|deploy staging pipeline"
  "Compare PostgreSQL and Kafka throughput under load.|PostgreSQL Kafka throughput"
  "The Terraform plan rebuilt the Kubernetes cluster in production.|Terraform Kubernetes production"
  "Grafana and Prometheus dashboards show endpoint latency.|Grafana Prometheus endpoint latency"
  "Check the OAuth and JWT flow before the webhook fires.|OAuth JWT webhook"
)

transcribe() { # $1=wav  $2=prompt|bare
  if [ "$2" = "prompt" ]; then
    curl -s --max-time 90 -F "file=@$1" -F "response_format=text" \
         -F "temperature=0" -F "prompt=$VOCAB" "$URL"
  else
    curl -s --max-time 90 -F "file=@$1" -F "response_format=text" \
         -F "temperature=0" "$URL"
  fi
}

score() { # $1=transcript $2=terms -> "hits/total"
  local hits=0 total=0 t
  for t in $2; do
    total=$((total+1))
    grep -qi -- "$t" <<<"$1" && hits=$((hits+1))
  done
  echo "$hits/$total"
}

printf '%s\n' "accuracy: base.en, ${#CASES[@]} synthetic utterances"
echo

bare_h=0; bare_t=0; prom_h=0; prom_t=0; n=0
for case in "${CASES[@]}"; do
  n=$((n+1))
  text="${case%%|*}"; terms="${case##*|}"
  wav_win="$TMP_WIN\\vflow_test_$n.wav"
  wav_wsl="$TMP_WSL/vflow_test_$n.wav"

  "$PWSH" -NoProfile -File "$GEN" -Text "$text" -Out "$wav_win" >/dev/null 2>&1
  [ -s "$wav_wsl" ] || { echo "  [$n] TTS FAILED"; continue; }

  b=$(transcribe "$wav_wsl" bare   | tr -s ' \n' ' ' | sed 's/^ *//; s/ *$//')
  p=$(transcribe "$wav_wsl" prompt | tr -s ' \n' ' ' | sed 's/^ *//; s/ *$//')
  bs=$(score "$b" "$terms"); ps=$(score "$p" "$terms")

  bare_h=$((bare_h + ${bs%/*})); bare_t=$((bare_t + ${bs#*/}))
  prom_h=$((prom_h + ${ps%/*})); prom_t=$((prom_t + ${ps#*/}))

  echo "  [$n] want : $text"
  echo "      bare   ($bs): $b"
  echo "      prompt ($ps): $p"
  echo
  rm -f "$wav_wsl"
done

echo "  ---------------------------------------------"
echo "  TOTAL term recall   bare = $bare_h/$bare_t    prompted = $prom_h/$prom_t"
