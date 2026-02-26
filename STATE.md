# open-builder — State

Last updated: 2026-02-25

## Phase: BUILD → PRE-DEPLOY

All three lanes complete. Code written and committed. Blocked on human-side provisioning.

## Lanes

| Lane | Scope | Status | Blocked By |
|------|-------|--------|------------|
| 1: Infra | flake.nix, configuration.nix, modules/, deploy-rs | done | — |
| 2: Agent Docs | documents/AGENTS.md, SOUL.md, TOOLS.md | done | — |
| 3: Scripts+Skills | scripts/, skills/, config/ | done | — |

## Decisions (Genesis)

- deploy-rs: standard input, single node, placeholder host IP
- Secrets: combined env file at /run/secrets/openclaw.env (injected via systemd EnvironmentFile).
  Individual paths (/run/secrets/ppq-api-key, /run/secrets/discord-token) are set in module
  options for boolean gates but NOT wired at runtime — the env file is what matters.
- Model: Claude Sonnet via ppq.ai
- Personality: hacker energy (terse, technical, irreverent, lowercase)
- openclaw-nix gaps: assume they exist, write workarounds
- Discord: no bot token yet, placeholder paths
- VPS: not provisioned, deploy config uses placeholder

## Secrets Needed (Pre-Deploy)

| Secret | Path on VPS | Source |
|--------|-------------|--------|
| Combined env file | /run/secrets/openclaw.env | Operator creates. Contains OPENAI_API_KEY and DISCORD_BOT_TOKEN |
| ppq.ai API key | (in openclaw.env as OPENAI_API_KEY) | ppq.ai dashboard |
| Discord bot token | (in openclaw.env as DISCORD_BOT_TOKEN) | Discord developer portal |
| Deploy SSH key | generated in-project (keys/deploy) | ssh-keygen (ED25519) |

## ppq.ai API Reference

- Base URL: `https://api.ppq.ai`
- Auth: `Authorization: Bearer {api_key}`
- Chat: `POST /chat/completions` (OpenAI compatible)
- Models: `GET /v1/models`
- Balance: `POST /credits/balance` (body: `{"credit_id": "..."}`)
- Topup: `POST /topup/create/btc-lightning` (body: `{"amount": N, "currency": "SATS"}`)
- Topup status: `GET /topup/status/{invoice_id}`
- Lightning invoices expire in 15 minutes, 5% fee bonus

## Pre-Deploy Checklist (human)

- [ ] Provision NixOS VPS, get hostname/IP
- [ ] Replace `open-builder.example.com` in flake.nix
- [ ] Replace `agents.example.com` in configuration.nix
- [ ] Create Discord app + bot, get token
- [ ] Get ppq.ai API key
- [ ] Create `/run/secrets/openclaw.env` on VPS with OPENAI_API_KEY and DISCORD_BOT_TOKEN
- [ ] Add `keys/deploy.pub` to VPS authorized_keys
- [ ] Run `nix flake check` locally to validate
- [ ] Deploy: `bash scripts/deploy.sh <hostname>`
- [ ] Validate model ID against `GET https://api.ppq.ai/v1/models`

## Open Items (non-blocking)

- `check-balance.sh` sends empty POST body — may need `credit_id` field, validate at integration
- `!wrap` restricted to ITERATE phase only — confirm this is desired behavior
- TOOLS.md still references `/run/secrets/ppq-api-key` in script docs — cosmetic, agent doesn't read secrets directly
