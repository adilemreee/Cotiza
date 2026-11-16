#!/usr/bin/env bash
# Publishes AppStore/site to https://precia.adilemree.xyz (nginx on the server, behind the Cloudflare tunnel).
# Usage: Tools/deploy_site.sh
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Tools/build_site.py
KEY="${COTIZA_SSH_KEY:-$HOME/.ssh/id_ed25519_sevgili}"
HOST="${COTIZA_SSH_HOST:-root@92.5.38.182}"
rsync -az --delete -e "ssh -i $KEY -o BatchMode=yes" AppStore/site/ "$HOST:/var/www/cotiza/"
ssh -i "$KEY" -o BatchMode=yes "$HOST" 'chown -R root:root /var/www/cotiza && find /var/www/cotiza -type d -exec chmod 755 {} + && find /var/www/cotiza -type f -exec chmod 644 {} +'
echo "Deployed. https://precia.adilemree.xyz/"
