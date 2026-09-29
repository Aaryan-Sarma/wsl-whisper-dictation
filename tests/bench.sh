#!/usr/bin/env bash
# bench.sh - measure vflow transcription latency honestly.
#
# WHY THE CARE: the i7-10610U is a 15W mobile part that throttles hard. Naive
# back-to-back runs decay (measured 2.52 -> 5.09 -> 4.21s on identical input),
# which makes A/B comparisons meaningless. So we:
#   - interleave the two variants so thermal drift hits both equally
#   - cool down between runs
#   - report the MINIMUM, which is the least-contended = truest capability
#
# usage: bench.sh [runs] [cooldown_seconds]
set -uo pipefail

RUNS="${1:-4}"
COOL="${2:-4}"
WAV="${WAV:-$HOME/voice/whisper.cpp/samples/jfk.wav}"
VOCAB_FILE="$HOME/voice/vocab.txt"
URL="http://127.0.0.1:8178/inference"

[ -f "$WAV" ] || { echo "bench: missing $WAV" >&2; exit 1; }
VOCAB="$(tr -d '\n' < "$VOCAB_FILE" 2>/dev/null || true)"

time_one() {
  local start end
  start=$(date +%s.%N)
  if [ "$1" = "prompted" ]; then
    curl -s --max-time 90 -F "file=@$WAV" -F "response_format=text" \
         -F "temperature=0" -F "prompt=$VOCAB" "$URL" >/dev/null
  else
    curl -s --max-time 90 -F "file=@$WAV" -F "response_format=text" \
         -F "temperature=0" "$URL" >/dev/null
  fi
  end=$(date +%s.%N)
  awk -v a="$start" -v b="$end" 'BEGIN{printf "%.2f", b-a}'
}

echo "bench: $(basename "$WAV"), $RUNS runs, ${COOL}s cooldown, interleaved"
echo "       vocab prompt = ${#VOCAB} chars"
echo

bare_min=999; prom_min=999
for i in $(seq 1 "$RUNS"); do
  sleep "$COOL"; a=$(time_one bare)
  sleep "$COOL"; b=$(time_one prompted)
  printf "  run%-2d  bare=%5ss  prompted=%5ss\n" "$i" "$a" "$b"
  bare_min=$(awk -v x="$a" -v m="$bare_min" 'BEGIN{print (x<m)?x:m}')
  prom_min=$(awk -v x="$b" -v m="$prom_min" 'BEGIN{print (x<m)?x:m}')
done

echo
printf "  MIN bare     = %ss\n" "$bare_min"
printf "  MIN prompted = %ss\n" "$prom_min"
awk -v a="$bare_min" -v b="$prom_min" \
    'BEGIN{printf "  prompt cost  = %+.2fs (%.0f%%)\n", b-a, (b-a)/a*100}'
