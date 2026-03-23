#!/usr/bin/env bash
set -euo pipefail

# deploy.sh — deploy tinker to VPS via rsync + remote nixos-rebuild
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOST="${1:-${TINKER_VPS_IP:?Set TINKER_VPS_IP or pass host as argument}}"
SSH_KEY="$PROJECT_DIR/keys/deploy"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

if [[ ! -f "$SSH_KEY" ]]; then
  echo "error: SSH key not found at $SSH_KEY" >&2
  exit 1
fi

cd "$PROJECT_DIR"
echo "deploying tinker to $HOST..."

# Sync flake to VPS — exclude agent-created content
rsync -az --delete \
  --exclude='.git' \
  --exclude='secrets/' \
  --exclude='infra/' \
  --exclude='keys/deploy' \
  --exclude='projects/' \
  --exclude='state/' \
  --exclude='prompts/' \
  --exclude='.claude/channels/' \
  --filter='protect modules/apps/*.nix' \
  -e "ssh $SSH_OPTS" \
  "$PROJECT_DIR/" "root@${HOST}:/srv/tinker/"

echo "rebuilding on VPS..."
ssh $SSH_OPTS "root@${HOST}" "cd /srv/tinker && nixos-rebuild switch --flake .#tinker"

echo ""
echo "deploy complete. verifying..."
ssh $SSH_OPTS "root@${HOST}" "
  echo 'caddy:' \$(systemctl is-active caddy 2>/dev/null || echo inactive)
  echo 'ssh:' \$(systemctl is-active sshd 2>/dev/null || echo inactive)
  id tinker 2>/dev/null && echo 'tinker user: exists' || echo 'tinker user: MISSING'
  test -d /srv/tinker/projects && echo '/srv/tinker: exists' || echo '/srv/tinker: MISSING'
"
echo "done."
