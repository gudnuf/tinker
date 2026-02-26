#!/usr/bin/env bash
set -euo pipefail

# teardown.sh — destroy the Hetzner Cloud VPS and optionally clean up the SSH key
#
# Dependencies: hcloud
# Environment: HCLOUD_TOKEN must be set
#
# Usage: teardown.sh [--delete-key | --keep-key]
#   --delete-key  also remove the SSH key resource from Hetzner
#   --keep-key    keep the SSH key (default)

SERVER_NAME="open-builder"
SSH_KEY_NAME="open-builder-deploy"
DELETE_KEY=false

# --- Parse flags ---

for arg in "$@"; do
  case "$arg" in
    --delete-key) DELETE_KEY=true ;;
    --keep-key)   DELETE_KEY=false ;;
    *)
      echo "usage: teardown.sh [--delete-key | --keep-key]"
      exit 1
      ;;
  esac
done

# --- Preflight checks ---

if [ -z "${HCLOUD_TOKEN:-}" ]; then
  echo "error: HCLOUD_TOKEN is not set"
  echo "export it from your shell or source infra/hetzner.env"
  exit 1
fi

if ! command -v hcloud &>/dev/null; then
  echo "error: hcloud CLI not found — install it first"
  exit 1
fi

# --- Delete server ---

if hcloud server describe "$SERVER_NAME" &>/dev/null; then
  echo "deleting server '$SERVER_NAME'..."
  hcloud server delete "$SERVER_NAME"
  echo "server deleted"
else
  echo "server '$SERVER_NAME' not found — nothing to delete"
fi

# --- Optionally delete SSH key ---

if [ "$DELETE_KEY" = true ]; then
  if hcloud ssh-key describe "$SSH_KEY_NAME" &>/dev/null; then
    echo "deleting SSH key '$SSH_KEY_NAME'..."
    hcloud ssh-key delete "$SSH_KEY_NAME"
    echo "SSH key deleted"
  else
    echo "SSH key '$SSH_KEY_NAME' not found — nothing to delete"
  fi
else
  echo "keeping SSH key '$SSH_KEY_NAME' (use --delete-key to remove)"
fi

echo ""
echo "teardown complete"
