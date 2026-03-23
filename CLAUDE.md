# CLAUDE.md — Tinker

## What This Is

Tinker is a Discord server where groups of people build and deploy real apps
together with AI agents. Someone pitches an idea, the group votes, and a
Claude Code meta-agent orchestrates parallel workers to build it live —
deploying to `{name}.tinker.builders` with screenshots along the way.

**Brand:** Tinker / tinker.builders / "for the tinkerin' builders"
**Repo:** gudnuf/tinker on GitHub

## Architecture

A single Claude Code session (keeper:tinker) runs on a NixOS VPS with the
official Discord plugin. It manages the round lifecycle: pitch → vote →
plan → build → deploy → iterate → wrap. Code generation is delegated to
Agent subagents (parallel). The keeper never writes code itself.

```
Discord #build
    ↕ discord plugin
keeper:tinker (Claude Code meta-agent)
    ├── Agent → build step 1 ─┐
    ├── Agent → build step 2  ├ parallel
    ├── Agent → build step 3 ─┘
    ↓ commit + nixos-rebuild + screenshot
Caddy → {name}.tinker.builders
```

## Key Paths

```
/etc/nixos/                     # NixOS config (cloned from GitHub)
├── flake.nix                   # nixpkgs + disko
├── configuration.nix           # networking, SSH, boot
├── modules/
│   ├── agent.nix               # tinker user, Claude Code, Chromium, tmux
│   ├── caddy.nix               # landing page + app subdomains
│   └── apps/                   # bot-generated app modules (auto-imported)
├── .claude/CLAUDE.md           # keeper system prompt
├── documents/SOUL.md           # personality
├── docs/index.html             # landing page (served by Caddy)
└── scripts/                    # deploy.sh, launch-agent, provision.sh

/srv/tinker/                    # tinker user home (app data, NOT config)
├── projects/{name}/            # app source code
├── .claude/                    # Claude Code settings, plugins, channels
└── .npm-global/                # Claude Code npm install
```

## Deploy Workflow

Push to GitHub, pull on VPS, rebuild:

```bash
git push origin main
# then:
ssh tinker-root "cd /etc/nixos && git pull && nixos-rebuild switch --flake .#tinker"
# or:
bash scripts/deploy.sh
```

No rsync. The NixOS config lives at `/etc/nixos/` (cloned from GitHub).
App code lives at `/srv/tinker/projects/` (tinker user home, not in the repo).

## VPS

- **Provider:** Hetzner Cloud, cpx31 (4 vCPU, 8 GB RAM)
- **Location:** Hillsboro, OR (hil)
- **IP:** 5.78.193.86
- **OS:** NixOS
- **Domain:** tinker.builders + *.tinker.builders

## Discord

- New Discord app with Administrator permission, all intents ON
- Bot token in `/run/secrets/tinker.env` and `~/.claude/channels/discord/.env`
- Discord plugin: `discord@claude-plugins-official`
- Channels: #welcome, #build, #showcase (keeper can create more)

## Secrets

```
/run/secrets/tinker.env         # DISCORD_BOT_TOKEN (on VPS, not in repo)
~/.claude/channels/discord/.env # same token, for Discord plugin
```

Operator authenticates Claude Code via `claude login` (OAuth).

## Key Design Decisions

- **Claude Code, not OpenClaw** — full tool access, parallel subagents, Discord plugin
- **Meta-agent pattern** — keeper flies high, never writes code, delegates to Agent subagents
- **Git-pull deploy** — push to GitHub, pull on VPS. No rsync, no permission issues.
- **NixOS app modules** — each app gets a .nix file in modules/apps/, Caddy reverse proxy, systemd sandboxing
- **Screenshots** — headless Chromium after each deploy, posted to Discord
- **Ambient + sprint modes** — phases stretch for meetups or compress for focused events

## Git Conventions

- Commit with `-c commit.gpgsign=false` (hardware key not available to agents)
- No Co-Authored-By footers
- Message format: `tinker: {project} — {description}`

## Detailed Docs

- `.claude/CLAUDE.md` — keeper system prompt (phases, commands, deployment, personality)
- `ARCHITECTURE.md` — full system design, NixOS modules, implementation plan
- `documents/SOUL.md` — personality voice
- `documents/ROUND-DESIGN.md` — v1 phase design (phases carry over, implementation changed)
