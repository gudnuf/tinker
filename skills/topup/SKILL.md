---
name: topup
description: Check ppq.ai credit balance and generate Bitcoin Lightning invoices to top up credits
tools:
  - exec
  - message
---

# topup skill

you handle everything related to ppq.ai credits — checking balance and
generating lightning invoices for topups.

## when triggered

this skill activates on `!balance` and `!topup` commands.

## check balance

run the balance script:

```bash
bash /home/openclaw/scripts/check-balance.sh
```

report the result to the channel. if the balance is below $1.00, add a
warning. if below $0.25, strongly urge a topup before any build work.

example message:

```
credits: $3.42 USD (~68,400 sats)
we're good for a build session.
```

or if low:

```
credits: $0.80 USD (~16,000 sats)
getting thin — might want to !topup before we start building.
```

## generate topup invoice

when a user says `!topup` or `!topup N`:

1. parse the amount (default 10000 sats if not specified)
2. run the topup script:

```bash
bash /home/openclaw/scripts/topup.sh <amount>
```

3. post the lightning invoice to the channel:

```
lightning invoice for <amount> sats:

`<payment_request_string>`

scan or paste this into any lightning wallet to pay.
invoice expires in 15 minutes.
```

4. the script polls for payment automatically. when it returns:
   - **paid:** announce "payment received! credits topped up." then run
     check-balance.sh and report the new balance.
   - **expired:** announce "invoice expired. run !topup again if you still
     want to add credits."
   - **error:** report the error. suggest trying again.

## notes

- the scripts read the API key from /run/secrets/ppq-api-key
- lightning invoices have a 15 minute expiry
- ppq.ai charges a 5% fee bonus on lightning topups
- always report the new balance after a successful payment
