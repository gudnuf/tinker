#!/usr/bin/env bash
set -euo pipefail

# deploy.sh — deploy tinker via git pull + nixos-rebuild on VPS
#
# NixOS config lives at /etc/nixos (cloned from github.com/gudnuf/tinker)
# App data lives at /srv/tinker (tinker user's home, not in the repo)
#
# Usage: deploy.sh [host]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOST="${1:-${TINKER_VPS_IP:-5.78.193.86}}"
SSH_KEY="$PROJECT_DIR/keys/deploy"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

if [[ ! -f "$SSH_KEY" ]]; then
  echo "error: SSH key not found at $SSH_KEY" >&2
  exit 1
fi

echo "deploying tinker to $HOST..."

echo "pulling latest from github..."
ssh $SSH_OPTS "root@${HOST}" "cd /etc/nixos && git pull"

echo "rebuilding..."
ssh $SSH_OPTS "root@${HOST}" "cd /etc/nixos && nixos-rebuild switch --flake .#tinker"

echo ""
echo "deploy complete. verifying..."
ssh $SSH_OPTS "root@${HOST}" "
  echo 'caddy:' \$(systemctl is-active caddy 2>/dev/null || echo inactive)
  echo 'ssh:' \$(systemctl is-active sshd 2>/dev/null || echo inactive)
  id tinker 2>/dev/null && echo 'tinker user: exists' || echo 'tinker user: MISSING'
"
echo "done."
