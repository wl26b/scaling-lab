#!/usr/bin/env bash
# Ship the current app/ folder to the running server, without replacing the server.
#
#   1. package app/ into releases/<version>.tar.gz   (the "artifact")
#   2. upload it to the S3 artifact bucket
#   3. tell the server (via Session Manager) to download it and run deploy/install.sh
#
# Usage: ./scripts/deploy.sh [stage]      e.g. ./scripts/deploy.sh stage2   (default: stage2)
set -euo pipefail
cd "$(dirname "$0")/.."

STAGE=${1:-stage2}
TF="terraform -chdir=infra/$STAGE"
BUCKET=$($TF output -raw artifact_bucket)
INSTANCE=$($TF output -raw app_instance_id)
VERSION=$(date -u +%Y%m%d-%H%M%S)
KEY="releases/$VERSION.tar.gz"

echo "▶ Packaging release $VERSION"
TMP=$(mktemp -d)
# COPYFILE_DISABLE stops macOS adding hidden ._ files to the archive
COPYFILE_DISABLE=1 tar -czf "$TMP/release.tar.gz" --exclude node_modules --exclude .DS_Store -C app .

echo "▶ Uploading to s3://$BUCKET/$KEY"
aws s3 cp --quiet "$TMP/release.tar.gz" "s3://$BUCKET/$KEY"
rm -rf "$TMP"

echo "▶ Installing on $INSTANCE"
REMOTE="set -eu
cloud-init status --wait > /dev/null || true   # first deploy on a new server: wait for bootstrap to finish
DIR=/opt/app/releases/$VERSION
mkdir -p \$DIR
/snap/bin/aws s3 cp --quiet s3://$BUCKET/$KEY /tmp/release.tar.gz
tar -xzf /tmp/release.tar.gz -C \$DIR && rm /tmp/release.tar.gz
bash \$DIR/deploy/install.sh 2>&1"

CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE" \
  --document-name AWS-RunShellScript \
  --comment "deploy $VERSION" \
  --timeout-seconds 900 \
  --parameters "$(jq -n --arg c "$REMOTE" '{commands: [$c], executionTimeout: ["900"]}')" \
  --query Command.CommandId --output text)

# Wait for it to finish (the first deploy seeds the database: ~2-3 min)
while :; do
  STATUS=$(aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$INSTANCE" \
    --query Status --output text 2>/dev/null || echo Pending)
  case "$STATUS" in
    Pending|InProgress|Delayed) printf '.'; sleep 5 ;;
    *) echo; break ;;
  esac
done

aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$INSTANCE" \
  --query StandardOutputContent --output text | tail -n 15

if [ "$STATUS" = "Success" ]; then
  echo "✅ Deployed $VERSION"
else
  echo "❌ Deploy $STATUS. Full output:"
  echo "   aws ssm get-command-invocation --command-id $CMD_ID --instance-id $INSTANCE"
  exit 1
fi
