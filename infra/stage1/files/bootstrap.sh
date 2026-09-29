#!/bin/bash
# First boot of the single server: install and configure the *machine*.
# The app itself is not here. It arrives later via ./scripts/deploy.sh.
# Runs once as root via cloud-init. Output: /var/log/cloud-init-output.log
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Packages ────────────────────────────────────────────────────────────────
apt-get update
apt-get install -y ca-certificates curl nginx postgresql htop sysstat
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
snap install aws-cli --classic   # deploys download releases from S3

# ── Postgres: tuning, user, empty database ──────────────────────────────────
# Sized for 2 GB RAM shared with Node and nginx.
PG_CONF_DIR=$(ls -d /etc/postgresql/*/main | head -1)
cat > "$PG_CONF_DIR/conf.d/tuning.conf" <<'CONF'
shared_buffers = 512MB
effective_cache_size = 1GB
work_mem = 4MB
maintenance_work_mem = 128MB
max_connections = 100
random_page_cost = 1.1
CONF
systemctl restart postgresql

sudo -u postgres psql -v ON_ERROR_STOP=1 <<'SQL'
CREATE ROLE app LOGIN PASSWORD 'app';
CREATE DATABASE social OWNER app;
SQL

# ── nginx: machine-wide limits; the site config comes with each deploy ──────
rm -f /etc/nginx/sites-enabled/default
sed -i 's/worker_connections [0-9]*/worker_connections 8192/' /etc/nginx/nginx.conf
sed -i '1i worker_rlimit_nofile 65535;' /etc/nginx/nginx.conf
systemctl reload nginx

mkdir -p /opt/app/releases
echo "BOOTSTRAP COMPLETE: ready for ./scripts/deploy.sh"
