# Tinker — State

Last updated: 2026-02-25

## Brand

- **Name:** Tinker
- **Domain:** tinker.builders
- **Tagline:** "for the tinkerin' builders"
- **Roadmap:** v1 Discord bot (join, get started) → v2 Showcase page (gallery of community builds)

## Phase: DEPLOYING

All lanes complete. VPS provisioned (46.225.140.108). NixOS install via nixos-anywhere
succeeds but boot is blocked — deploy agent fixing GRUB/UEFI/networking in window 5.

## Lanes

| Lane | Scope | Status | Blocked By |
|------|-------|--------|------------|
| 1: Infra | flake.nix, configuration.nix, modules/, deploy-rs | done | — |
| 2: Agent Docs | documents/AGENTS.md, SOUL.md, TOOLS.md | done | — |
| 3: Scripts+Skills | scripts/, skills/, config/ | done | — |
| 4: Provisioning | scripts/provision.sh, teardown.sh, disko, flake updates | done | — |
| 5: Deploy | VPS boot + networking + first deploy | in progress | GRUB boot fix |
| 6: Landing Page | docs/index.html, CNAME | done | — |

## Decisions (Genesis)

- deploy-rs: standard input, single node, placeholder host IP
- Secrets: combined env file at /run/secrets/openclaw.env (injected via systemd EnvironmentFile).
  Individual paths (/run/secrets/ppq-api-key, /run/secrets/discord-token) are set in module
  options for boolean gates but NOT wired at runtime — the env file is what matters.
- Model: Claude Sonnet via ppq.ai
- Personality: hacker energy (terse, technical, irreverent, lowercase)
- openclaw-nix gaps: assume they exist, write workarounds
- Discord: no bot token yet, placeholder paths
- VPS: Hetzner cpx32, IP 46.225.140.108, server name "open-builder"
- Boot: GRUB + BIOS boot partition (Hetzner resets UEFI NVRAM on reboot)
- Networking: systemd-networkd, DHCP on en*/eth*
- GitHub: gudnuf/tinker, Pages enabled from docs/ on main

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

- [x] Set HCLOUD_TOKEN
- [x] Run provision.sh — VPS created, IP 46.225.140.108
- [x] GitHub repo created (gudnuf/tinker), Pages enabled
- [x] Landing page live (pending DNS)
- [x] README committed
- [ ] **BLOCKED: NixOS boot** — deploy agent working on GRUB fix (window 5)
- [ ] Replace placeholder hostnames (open-builder.example.com → 46.225.140.108, agents.example.com → tinker.builders)
- [ ] Point tinker.builders DNS to GitHub Pages IPs (185.199.108-111.153)
- [ ] Create Discord server + bot, get token
- [ ] Get ppq.ai API key
- [ ] Create /run/secrets/openclaw.env on VPS
- [ ] Deploy: bash scripts/deploy.sh 46.225.140.108
- [ ] Validate model ID against GET https://api.ppq.ai/v1/models
- [ ] Update docs/index.html Discord invite link (replace PLACEHOLDER)

## Open Items (non-blocking)

- `check-balance.sh` sends empty POST body — may need `credit_id` field, validate at integration
- `!wrap` restricted to ITERATE phase only — confirm this is desired behavior
- TOOLS.md still references `/run/secrets/ppq-api-key` in script docs — cosmetic, agent doesn't read secrets directly
- Session timeouts not in AGENTS.md yet — see DISCORD-DESIGN.md
- Discord server structure designed but not created yet — see DISCORD-DESIGN.md
