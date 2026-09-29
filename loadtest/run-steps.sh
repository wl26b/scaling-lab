#!/usr/bin/env bash
# Run the test at increasing user counts. Each run gets its own folder: results/<run-id>/
#   ./run-steps.sh                    # default steps
#   ./run-steps.sh 6000 8000 10000    # custom steps
#
# If the load generator was given an S3 bucket (the "bucket" file), the run folder is uploaded to
# s3://<bucket>/results/<run-id>/ at the end, so results can be read without starting this machine again.
set -euo pipefail
cd "$(dirname "$0")"
# Target server: $BASE_URL, else the "target" file the load generator was set up with.
BASE_URL=${BASE_URL:-$(cat target 2>/dev/null || true)}
: "${BASE_URL:?set BASE_URL=http://<server-ip>}"
STEPS=(${@:-10 50 100 250 500 1000 2000 3000 4000 5000})
COOLDOWN=${COOLDOWN:-30}
RUN_ID=$(date -u +%Y%m%d-%H%M%S)
OUT_DIR=results/$RUN_ID
OUT=$OUT_DIR/results.csv

ulimit -n 250000
mkdir -p "$OUT_DIR"
echo "vus,req_per_s,requests,fail_pct,p50_ms,p95_ms,p99_ms,max_ms" > "$OUT"

# This machine's own CPU/memory every 10 s: shows whether the load generator itself was the bottleneck.
vmstat -t 10 > "$OUT_DIR/loadgen-vmstat.log" &
VMSTAT_PID=$!

for vus in "${STEPS[@]}"; do
  echo "================ $vus virtual users ================"
  k6 run -e BASE_URL="$BASE_URL" -e VUS="$vus" -e OUT_DIR="$OUT_DIR" social.js || true  # a failed threshold is a result
  cat "$OUT_DIR/vus-$vus.row.csv" >> "$OUT" || echo "$vus,k6 crashed (see loadgen-vmstat.log)" >> "$OUT"
  echo; column -s, -t "$OUT"; echo
  sleep "$COOLDOWN"
done

kill "$VMSTAT_PID" || true

if [ -f bucket ]; then
  /snap/bin/aws s3 cp --recursive --quiet --region "$(cat region)" "$OUT_DIR" "s3://$(cat bucket)/results/$RUN_ID/"
  echo "Uploaded to s3://$(cat bucket)/results/$RUN_ID/"
fi
