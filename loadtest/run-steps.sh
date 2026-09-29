#!/usr/bin/env bash
# Run the test at increasing user counts; one CSV row per step in results/results.csv.
#   ./run-steps.sh                    # default steps
#   ./run-steps.sh 6000 8000 10000    # custom steps
set -euo pipefail
cd "$(dirname "$0")"
# Target server: $BASE_URL, else the "target" file the load generator was set up with.
BASE_URL=${BASE_URL:-$(cat target 2>/dev/null || true)}
: "${BASE_URL:?set BASE_URL=http://<server-ip>}"
STEPS=(${@:-10 50 100 250 500 1000 2000 3000 4000 5000})
COOLDOWN=${COOLDOWN:-30}

ulimit -n 250000
mkdir -p results
OUT=results/results.csv
[ -f "$OUT" ] || echo "vus,req_per_s,requests,fail_pct,p50_ms,p95_ms,p99_ms,max_ms" > "$OUT"

for vus in "${STEPS[@]}"; do
  echo "================ $vus virtual users ================"
  k6 run -e BASE_URL="$BASE_URL" -e VUS="$vus" social.js || true  # a failed threshold is a result, keep going
  cat "results/vus-$vus.row.csv" >> "$OUT"
  echo; column -s, -t "$OUT"; echo
  sleep "$COOLDOWN"
done
