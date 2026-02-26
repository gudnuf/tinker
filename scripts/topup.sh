#!/usr/bin/env bash
set -euo pipefail

# topup.sh — create a Bitcoin Lightning invoice to top up ppq.ai credits
# Dependencies: curl, jq
# Auth: sources OPENAI_API_KEY from /run/secrets/openclaw.env
# Usage: topup.sh [amount_in_sats] [currency]
#   amount defaults to 10000, currency defaults to SATS

AMOUNT="${1:-10000}"
CURRENCY="${2:-SATS}"
CREATE_URL="https://api.ppq.ai/topup/create/btc-lightning"
STATUS_URL="https://api.ppq.ai/topup/status"
POLL_INTERVAL=10
TIMEOUT=900  # 15 minutes in seconds

# Load secrets from combined env file
ENV_FILE="/run/secrets/openclaw.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: secrets file not found at $ENV_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

API_KEY="${OPENAI_API_KEY:?error: OPENAI_API_KEY not set in $ENV_FILE}"

# Create the Lightning invoice
response="$(curl -s -w "\n%{http_code}" -X POST "$CREATE_URL" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"amount\": $AMOUNT, \"currency\": \"$CURRENCY\"}")"

http_code="$(echo "$response" | tail -1)"
body="$(echo "$response" | sed '$d')"

if [[ "$http_code" -ne 200 ]]; then
  echo "error: failed to create invoice (HTTP $http_code)" >&2
  echo "$body" >&2
  exit 1
fi

if ! echo "$body" | jq empty 2>/dev/null; then
  echo "error: invalid JSON response" >&2
  echo "$body" >&2
  exit 1
fi

invoice_id="$(echo "$body" | jq -r '.invoice_id // .id')"
payment_request="$(echo "$body" | jq -r '.payment_request // .invoice // .bolt11')"

if [[ "$invoice_id" == "null" || -z "$invoice_id" ]]; then
  echo "error: no invoice ID in response" >&2
  echo "$body" >&2
  exit 1
fi

echo "Lightning invoice created"
echo "  invoice_id: $invoice_id"
echo "  amount: $AMOUNT $CURRENCY"
echo ""
echo "payment_request:"
echo "$payment_request"
echo ""
echo "waiting for payment (${TIMEOUT}s timeout)..."

# Poll for payment status
elapsed=0
while [[ "$elapsed" -lt "$TIMEOUT" ]]; do
  sleep "$POLL_INTERVAL"
  elapsed=$((elapsed + POLL_INTERVAL))

  status_response="$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $API_KEY" \
    "${STATUS_URL}/${invoice_id}")"

  status_code="$(echo "$status_response" | tail -1)"
  status_body="$(echo "$status_response" | sed '$d')"

  if [[ "$status_code" -ne 200 ]]; then
    echo "warning: status check returned HTTP $status_code (retrying...)" >&2
    continue
  fi

  state="$(echo "$status_body" | jq -r '.status // .state // "unknown"')"

  case "$state" in
    paid|completed|settled)
      echo "payment confirmed!"
      echo "$status_body" | jq -r '"  status: \(.status // .state)\n  credited: \(.credited // .amount // "unknown")"' 2>/dev/null || true
      exit 0
      ;;
    expired|cancelled|failed)
      echo "invoice $state." >&2
      exit 1
      ;;
    *)
      # still pending — keep polling
      remaining=$(( (TIMEOUT - elapsed) / 60 ))
      echo "  ...pending (~${remaining}m remaining)"
      ;;
  esac
done

echo "error: timed out waiting for payment after ${TIMEOUT}s" >&2
exit 1
