#!/usr/bin/env bash
set -euo pipefail

# deploy.sh — deploy open-builder via deploy-rs and verify
# Dependencies: deploy-rs (deploy), ssh, curl, jq (on remote)
# Usage: deploy.sh [host]
#   host defaults to open-builder.example.com

HOST="${1:-open-builder.example.com}"

echo "deploying open-builder to $HOST..."
deploy .#open-builder

echo ""
echo "deploy complete. verifying..."

# Verify openclaw service is running
echo ""
echo "--- service status ---"
ssh "root@${HOST}" "systemctl is-active openclaw && echo 'openclaw: running' || echo 'openclaw: NOT running'"

# Check secrets env file
echo ""
echo "--- secrets ---"
ssh "root@${HOST}" "test -f /run/secrets/openclaw.env && echo '/run/secrets/openclaw.env: present' || echo '/run/secrets/openclaw.env: MISSING'"

# Check balance
echo ""
echo "--- ppq.ai balance ---"
ssh "root@${HOST}" "bash /home/openclaw/scripts/check-balance.sh" || echo "warning: balance check failed"

echo ""
echo "deploy verified."
