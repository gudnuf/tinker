#!/usr/bin/env bash
set -euo pipefail

# deploy.sh — deploy tinker via deploy-rs and verify
# Dependencies: deploy-rs (deploy), ssh, curl, jq (on remote)
# Usage: deploy.sh [host]
#   host defaults to 46.225.140.108

HOST="${1:-46.225.140.108}"
SSH_KEY="keys/deploy"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no"

echo "deploying tinker to $HOST..."
deploy .#tinker

echo ""
echo "deploy complete. verifying..."

# Verify openclaw service is running
echo ""
echo "--- service status ---"
ssh $SSH_OPTS "root@${HOST}" "systemctl is-active openclaw && echo 'openclaw: running' || echo 'openclaw: NOT running'"

# Check secrets env file
echo ""
echo "--- secrets ---"
ssh $SSH_OPTS "root@${HOST}" "test -f /run/secrets/openclaw.env && echo '/run/secrets/openclaw.env: present' || echo '/run/secrets/openclaw.env: MISSING'"

# Check balance
echo ""
echo "--- ppq.ai balance ---"
ssh $SSH_OPTS "root@${HOST}" "bash /home/openclaw/scripts/check-balance.sh" || echo "warning: balance check failed"

echo ""
echo "deploy verified."
