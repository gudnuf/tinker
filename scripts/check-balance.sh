#!/usr/bin/env bash
set -euo pipefail

# check-balance.sh — query ppq.ai credit balance
# Dependencies: curl, jq
# Auth: sources OPENAI_API_KEY from /run/secrets/openclaw.env

API_URL="https://api.ppq.ai/credits/balance"

# Load secrets from combined env file
ENV_FILE="/run/secrets/openclaw.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: secrets file not found at $ENV_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

API_KEY="${OPENAI_API_KEY:?error: OPENAI_API_KEY not set in $ENV_FILE}"

response="$(curl -s -w "\n%{http_code}" -X POST "$API_URL" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{}')"

http_code="$(echo "$response" | tail -1)"
body="$(echo "$response" | sed '$d')"

if [[ "$http_code" -ne 200 ]]; then
  echo "error: API returned HTTP $http_code" >&2
  echo "$body" >&2
  exit 1
fi

if ! echo "$body" | jq empty 2>/dev/null; then
  echo "error: invalid JSON response" >&2
  echo "$body" >&2
  exit 1
fi

# Extract balance fields — adapt to actual API response shape
usd="$(echo "$body" | jq -r '.balance_usd // .balance // .credits // "unknown"')"
sats="$(echo "$body" | jq -r '.balance_sats // empty' 2>/dev/null || true)"

echo "ppq.ai balance: \$${usd} USD"
if [[ -n "$sats" ]]; then
  echo "              ≈ ${sats} sats"
fi
