# Tinker — State

Last updated: 2026-02-26

## Brand

- **Name:** Tinker
- **Domain:** tinker.builders
- **Tagline:** "for the tinkerin' builders"
- **Roadmap:** v1 Discord bot (join, get started) → v2 Showcase page (gallery of community builds)

## Phase: DEPLOYED — BOT ONLINE

Gateway running on VPS (46.225.140.108). Discord bot connected (@Tinker).
Secrets provisioned. Landing page v2 committed. ppq.ai balance is $0 — needs
topup before the bot can respond to messages.

## Active Lanes

| Lane | Task | Status |
|------|------|--------|
| 1: meta | Strategic coordination (this session) | active |
| 2: lane1 | Round design brainstorm → produced ROUND-DESIGN.md | done, idle |
| 3: lane2 | ppq.ai API spike → found bugs, fixing scripts | fixing scripts |
| 4: lane3 | Landing page v2 rewrite | just started |
| 5: lane4 | VPS boot debugging (GRUB/networking) | active, 8% context — near end |

## Completed Lanes (Genesis)

| Lane | Scope | Status |
|------|-------|--------|
| Infra | flake.nix, configuration.nix, modules/, deploy-rs | done |
| Agent Docs | documents/AGENTS.md, SOUL.md, TOOLS.md | done (v1 — being redesigned) |
| Scripts+Skills | scripts/, skills/, config/ | done (bugs found, being fixed) |
| Provisioning | scripts/provision.sh, teardown.sh, disko, flake updates | done |
| Landing Page v1 | docs/index.html, CNAME | done (v2 in lane3) |

## Decisions (Genesis)

- deploy-rs: standard input, single node, placeholder host IP
- Secrets: combined env file at /run/secrets/openclaw.env (injected via systemd EnvironmentFile).
  Individual paths (/run/secrets/ppq-api-key, /run/secrets/discord-token) are set in module
  options for boolean gates but NOT wired at runtime — the env file is what matters.
- Model: Claude Sonnet 4.6 via ppq.ai (model ID: `claude-sonnet-4.6`)
- Personality: hacker energy (terse, technical, irreverent, lowercase)
- openclaw-nix gaps: assume they exist, write workarounds
- VPS: Hetzner cpx32, IP 46.225.140.108, server name "tinker"
- Boot: GRUB + BIOS boot partition (Hetzner resets UEFI NVRAM on reboot)
- Networking: systemd-networkd, DHCP on en*/eth*
- GitHub: gudnuf/tinker, Pages enabled from docs/ on main
- Passwordless sudo for nixos-rebuild (agent needs it for app deploys)

## Decisions (v2 Design)

- **Round phases:** IDLE → PLAN (10 min, hard-gated) → FUND → BUILD → DEPLOY → ITERATE → WRAP
- **Planning sub-phases:** PITCH (0-4 min) → SYNTHESIZE (4-6) → VOTE (6-8) → SPEC (8-10). Auto-advancing, no commands needed.
- **Cost gate:** bot estimates cost per-step ($0.05/step + 50% buffer), checks balance, hard-blocks on insufficient funds
- **Subagents:** stateless API calls via curl from exec, NOT separate processes. Orchestrator constructs prompts, calls ppq.ai directly.
- **Deployment:** Nix-native. Agent writes app module to modules/apps/{name}.nix, commits, runs nixos-rebuild. Caddy reverse proxy with on-demand TLS.
- **Commit-before-rebuild:** every deploy backed by a git commit. ~15-25 commits per round. Full audit trail.
- **Port allocation:** 10001-10099, sequential per round.
- **App TTL:** 30 days active, then operator archives. Automated cleanup is v2.
- **Discord channels:** #build (stage), #feedback (testing), #questions (bot asks), #credits (funding), #gallery (showcase), #general + #ideas (human, no bot), #ops (admin)
- Full design: documents/ROUND-DESIGN.md

## Validated (ppq.ai API Spike)

Tested all endpoints against live API. Results:

| Endpoint | Status | Notes |
|----------|--------|-------|
| GET /v1/models | works | Model ID is `claude-sonnet-4.6` (not `claude-3.5-sonnet`). 1M context. |
| POST /credits/balance | works | Returns `{"balance": 0}`. No credit_id needed. Empty body is fine. |
| POST /topup/create/btc-lightning | works | Returns 201 (not 200). Field is `.lightning_invoice` (not `.payment_request`). Also returns `.checkout_url`. |
| POST /chat/completions | 402 | Balance is $0. Needs topup before chat works. |

### Script bugs found and being fixed (lane2):
- **topup.sh:** rejects HTTP 201 as error (only accepts 200). Wrong field name for invoice (`.lightning_invoice` not `.payment_request`).
- **config/openclaw.json:** stale model ID `claude-3.5-sonnet` → needs `claude-sonnet-4.6`, context 200K → 1M.
- **check-balance.sh:** works by fallback but output label assumes USD. Minor.

## Validated (openclaw-nix Research)

| Question | Answer |
|----------|--------|
| Does openclaw-nix include Caddy? | **Yes.** Enabled when `services.openclaw.domain` is set. Creates reverse proxy virtualHost with auto TLS. |
| Can exec tool access $OPENAI_API_KEY? | **No, not by default.** openclaw-nix passes the key file path to config internally, doesn't expose it as env var. Agent must read key from file at exec time: `$(cat /path/to/key)`. |
| Passwordless sudo for nixos-rebuild? | **Going with it.** Add sudoers rule for openclaw user. |

## Secrets Status

| Secret | Status | Location |
|--------|--------|----------|
| Discord bot token | **obtained** | secrets/discord.env (gitignored) |
| ppq.ai API key | **obtained** | secrets/ppq.env (gitignored) |
| Discord bot intents | **configured** | Message Content Intent ON, others off |
| Discord invite link | **created** | https://discord.gg/WWPGb5xW (expires ~2026-03-05) |
| Deploy SSH key | **deployed** | keys/deploy (gitignored), pub key in keys/deploy.pub |
| Combined VPS env file | **deployed** | /run/secrets/openclaw.env on VPS (root:root 0600) |

## Pre-Deploy Checklist (human)

- [x] Set HCLOUD_TOKEN
- [x] Run provision.sh — VPS created, IP 46.225.140.108
- [x] GitHub repo created (gudnuf/tinker), Pages enabled
- [x] Landing page v1 live (pending DNS)
- [x] README committed
- [x] Create Discord server + bot, get token
- [x] Configure bot intents (Message Content ON)
- [x] Get ppq.ai API key
- [x] Validate ppq.ai API endpoints (spike complete)
- [x] NixOS boot — resolved (GRUB + BIOS boot partition)
- [x] Landing page v2 committed
- [x] Replace placeholder hostnames in config — renamed to tinker throughout
- [x] Create /run/secrets/openclaw.env on VPS (secrets deployed)
- [x] Deploy: gateway running, Discord connected
- [ ] Fix script bugs (topup.sh 201 handling, field names)
- [ ] Point tinker.builders DNS to GitHub Pages IPs (185.199.108-111.153)
- [ ] Set up wildcard DNS: *.tinker.builders → 46.225.140.108
- [ ] Add Caddy domain config + on-demand TLS to configuration.nix
- [ ] Add passwordless sudo rule for openclaw user → nixos-rebuild
- [ ] Add dynamic app module import to configuration.nix (see ROUND-DESIGN.md §6)
- [ ] Generate permanent Discord invite link (current one expires ~Mar 5)
- [ ] Top up ppq.ai credits (balance is $0)
- [ ] Rewrite AGENTS.md to match ROUND-DESIGN.md v2 phases

## Validated (Deploy — openclaw-nix workarounds)

| Issue | Workaround |
|-------|------------|
| `--config` flag not supported by openclaw | Override ExecStart, use `gateway run` without --config |
| `gateway start` calls systemctl --user (fails in system service) | Use `gateway run` (foreground mode) |
| Systemd sandbox crashes gateway (fchown in uv__fs_copyfile) | Disable ProtectSystem, ProtectHome, PrivateTmp, etc. via mkForce |
| os.networkInterfaces() needs AF_NETLINK | Add AF_NETLINK to RestrictAddressFamilies |
| Config schema mismatch (models array vs providers object) | Seed correct openclaw.json via preStart, guard with if-not-exists |
| deploy-rs cross-arch (aarch64-darwin → x86_64-linux) | rsync + remote nixos-rebuild instead of deploy-rs |
| VPS hostname still shows "open-builder" in logs | Needs redeploy with hostName = "tinker" (cosmetic) |

## Open Items (non-blocking)

- `!wrap` restricted to ITERATE phase only — confirm this is desired behavior
- TOOLS.md still references `/run/secrets/ppq-api-key` in script docs — cosmetic
- Session timeouts not in AGENTS.md yet — see DISCORD-DESIGN.md
- Round state persistence (survives OpenClaw restart) — deferred to v2
- Concurrent rounds — deferred to v2
- Code export to GitHub gist on !wrap — deferred to v2
- QR codes for Lightning invoices — deferred to v2
- Automated app TTL cleanup — deferred to v2
