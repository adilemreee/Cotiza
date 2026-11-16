#!/usr/bin/env bash
# Deploys the signing-link service (Server/sign) to /opt/cotiza-sign and the Cotiza nginx site config.
# Usage: Tools/deploy_sign.sh
set -euo pipefail
cd "$(dirname "$0")/.."
KEY="${COTIZA_SSH_KEY:-$HOME/.ssh/id_ed25519_sevgili}"
HOST="${COTIZA_SSH_HOST:-root@92.5.38.182}"
SSH=(ssh -i "$KEY" -o BatchMode=yes "$HOST")

(cd Server/sign && node --test >/dev/null) || { echo "Server tests failed"; exit 1; }
"${SSH[@]}" 'mkdir -p /opt/cotiza-sign/data && chown 1000:1000 /opt/cotiza-sign/data'
rsync -az -e "ssh -i $KEY -o BatchMode=yes" --exclude node_modules --exclude data --exclude '*.test.js' Server/sign/ "$HOST:/opt/cotiza-sign/"
"${SSH[@]}" 'cd /opt/cotiza-sign && docker compose up -d --build && sleep 3 && wget -qO- http://127.0.0.1:4130/api/v1/health'
echo
# nginx: keep a dated copy of the live config, install the new one, and only reload if it validates.
scp -i "$KEY" -o BatchMode=yes AppStore/server/nginx-precia.conf "$HOST:/tmp/nginx-precia.conf"
"${SSH[@]}" 'set -e; live=$(readlink -f /etc/nginx/sites-enabled/cotiza)
  cp "$live" "$live.bak-$(date +%Y%m%d-%H%M%S)"
  cp /tmp/nginx-precia.conf "$live"
  if nginx -t 2>/dev/null; then systemctl reload nginx; echo "nginx reloaded"; else cp "$(ls -t "$live".bak-* | head -1)" "$live"; echo "nginx config invalid, restored"; exit 1; fi'
echo "Deployed. https://precia.adilemree.xyz/api/v1/health"
