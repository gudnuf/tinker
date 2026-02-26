# open-builder — State

Last updated: 2026-02-25 (genesis)

## Phase: GENESIS → BUILD

All open questions resolved. Process codified. Lanes ready to launch.

## Lanes

| Lane | Scope | Status | Blocked By |
|------|-------|--------|------------|
| 1: Infra | flake.nix, configuration.nix, modules/, deploy-rs | pending | — |
| 2: Agent Docs | documents/AGENTS.md, SOUL.md, TOOLS.md | pending | — |
| 3: Scripts+Skills | scripts/, skills/, config/ | pending | ppq.ai research (done) |

## Decisions (Genesis)

- deploy-rs: standard input, single node, placeholder host IP
- Secrets: plain files at /run/secrets/, manual placement
- Model: Claude Sonnet via ppq.ai
- Personality: hacker energy (terse, technical, irreverent, lowercase)
- openclaw-nix gaps: assume they exist, write workarounds
- Discord: no bot token yet, placeholder paths
- VPS: not provisioned, deploy config uses placeholder

## Secrets Needed (Pre-Deploy)

| Secret | Path on VPS | Source |
|--------|-------------|--------|
| ppq.ai API key | /run/secrets/ppq-api-key | ppq.ai dashboard |
| Discord bot token | /run/secrets/discord-token | Discord developer portal |
| Deploy SSH key | generated in-project | ssh-keygen (ED25519) |

## ppq.ai API Reference

- Base URL: `https://api.ppq.ai`
- Auth: `Authorization: Bearer {api_key}`
- Chat: `POST /chat/completions` (OpenAI compatible)
- Models: `GET /v1/models`
- Balance: `POST /credits/balance` (body: `{"credit_id": "..."}`)
- Topup: `POST /topup/create/btc-lightning` (body: `{"amount": N, "currency": "SATS"}`)
- Topup status: `GET /topup/status/{invoice_id}`
- Lightning invoices expire in 15 minutes, 5% fee bonus

## Next Actions

1. Launch Lane 1: write flake.nix + configuration.nix + deploy-rs config
2. Launch Lane 2: write AGENTS.md + SOUL.md + TOOLS.md
3. Launch Lane 3: write scripts + topup skill + reference config
4. Meta-agent: review outputs, resolve cross-cutting issues, update state
