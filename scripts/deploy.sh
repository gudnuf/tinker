#!/usr/bin/env bash
set -euo pipefail

# deploy.sh — deploy tinker to VPS via rsync + remote nixos-rebuild
# Dependencies: rsync, ssh, nix (for building the system closure)
# Usage: deploy.sh [host]
#   host defaults to TINKER_VPS_IP or 46.225.140.108

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOST="${1:-${TINKER_VPS_IP:-46.225.140.108}}"
SSH_KEY="$PROJECT_DIR/keys/deploy"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

if [[ ! -f "$SSH_KEY" ]]; then
  echo "error: SSH key not found at $SSH_KEY" >&2
  exit 1
fi

cd "$PROJECT_DIR"

echo "deploying tinker to $HOST..."

# Sync flake to VPS and rebuild remotely
# (deploy-rs cross-arch doesn't work from aarch64-darwin → x86_64-linux)
echo "syncing flake to VPS..."
rsync -az --delete \
  --exclude='.git' \
  --exclude='secrets/' \
  --exclude='infra/' \
  --exclude='keys/deploy' \
  -e "ssh $SSH_OPTS" \
  "$PROJECT_DIR/" "root@${HOST}:/etc/nixos/"

echo "syncing landing page to /var/www/tinker/..."
rsync -az --delete \
  -e "ssh $SSH_OPTS" \
  "$PROJECT_DIR/docs/" "root@${HOST}:/var/www/tinker/"

echo "rebuilding on VPS..."
ssh $SSH_OPTS "root@${HOST}" "cd /etc/nixos && nixos-rebuild switch --flake .#tinker"

echo ""
echo "deploy complete. verifying..."

# Quick verification
echo ""
ssh $SSH_OPTS "root@${HOST}" "
  state=\$(systemctl is-active openclaw-gateway 2>/dev/null || echo inactive)
  echo \"service: \$state\"
  test -f /run/secrets/openclaw.env && echo 'secrets: present' || echo 'secrets: MISSING'
  ss -tlnp 2>/dev/null | grep -q ':3000 ' && echo 'port 3000: listening' || echo 'port 3000: not listening'
"

echo ""
echo "done. run 'tinker-status' for full health check."
