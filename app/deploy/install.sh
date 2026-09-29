#!/bin/bash
# Runs ON THE SERVER, from inside an unpacked release, to make that release live.
#   /opt/app/releases/<version>/   ← one folder per deploy
#   /opt/app/current → releases/<version>   ← the live one (a symlink)
set -euxo pipefail
RELEASE_DIR=$(cd "$(dirname "$0")/.." && pwd)

# 1. Dependencies for this release (exact versions from package-lock.json)
cd "$RELEASE_DIR" && npm ci --omit=dev --no-audit --no-fund

# 2. Database: create and seed the tables only if they don't exist yet.
#    Later deploys leave the data alone.
#    Connection settings come from /etc/app/app.env (PGHOST, PGUSER, ...), which psql reads directly.
set -a; . /etc/app/app.env; set +a
if [ -n "${DB_SECRET_ARN:-}" ]; then
  set +x   # don't print the password into the deploy log
  PGPASSWORD=$(/snap/bin/aws secretsmanager get-secret-value --secret-id "$DB_SECRET_ARN" \
    --query SecretString --output text | jq -r .password)
  export PGPASSWORD
  set -x
fi
PSQL="psql -v ON_ERROR_STOP=1"
if [ "$($PSQL -tAc "SELECT to_regclass('public.users') IS NOT NULL")" != "t" ]; then
  $PSQL -f db/schema.sql
  $PSQL -f db/seed.sql
fi

# 3. Switch "current" to this release in one step.
ln -sfn "$RELEASE_DIR" /opt/app/current

# 4. Config files that ship with the code
cp deploy/nginx.conf /etc/nginx/sites-available/app
ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/app
cp deploy/app.service /etc/systemd/system/app.service
systemctl daemon-reload

# 5. Restart Node, reload nginx (reload = no dropped connections)
nginx -t
systemctl enable app
systemctl restart app
systemctl reload nginx

# 6. Is it actually up?
for i in $(seq 1 20); do curl -fsS localhost/health && break; sleep 0.5; done
echo

# 7. Keep the last 3 releases (for rollback), delete older ones
ls -1dt /opt/app/releases/*/ | tail -n +4 | xargs -r rm -rf

echo "DEPLOYED $(basename "$RELEASE_DIR")"
