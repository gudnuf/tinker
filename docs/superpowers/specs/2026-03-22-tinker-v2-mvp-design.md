# Tinker v2 MVP — Design Spec

**Date:** 2026-03-22
**Status:** Approved (brainstormed and iterated with alchemist)

## Problem

Tinker v1 (OpenClaw-based) has a single agent context that degrades during
builds, rigid prose-driven phases, stateless curl subagents with no tool
access, and a single Discord channel. It's deployed but dormant.

## Solution

Replace OpenClaw with a single Claude Code session using the official Discord
plugin, parallel subagents via the built-in Agent tool, headless Chromium
screenshots, and NixOS app deployment to subdomains.

## MVP Scope

**In scope:**
- One Claude Code session (keeper:tinker) with Discord plugin
- 3-channel Discord server (#welcome, #build, #showcase)
- Parallel build via Agent tool subagents (2-3 concurrent)
- Screenshot flow: headless Chromium → Discord after each deploy
- NixOS app modules + Caddy reverse proxy for *.tinker.builders
- Phase flow: !start → pitch → vote → plan → build → deploy → iterate → !wrap
- SOUL.md personality (terse dev voice)
- Fresh Hetzner VPS (cpx31, Ashburn)

**Out of scope (deferred):**
- Mercury (inter-agent comms, feed service)
- Separate worker processes in tmux
- phase.json state persistence
- ppq.ai / Lightning funding / credit-bot
- External phase timer service
- Multi-channel routing beyond #build

## Architecture

See ARCHITECTURE.md for the full design. Key points:

- **Runtime:** Claude Code + `discord@claude-plugins-official` plugin
- **Parallelism:** Agent tool subagents (built-in, zero infra overhead)
- **Screenshots:** headless Chromium, posted as file attachments to Discord
- **Deployment:** NixOS modules in modules/apps/, Caddy reverse proxy, commit-before-rebuild
- **Discord:** Administrator permission, full server control, 3 channels to start
- **VPS:** Hetzner cpx31, NixOS, /srv/tinker/ as git repo root

## Discord Design

Three channels. One interactive. Bot has Administrator permission and can
create more channels on the fly if needed.

- **#welcome** — read-only, pinned explainer + flow diagram
- **#build** — everything: ideas, votes, progress, screenshots, feedback
- **#showcase** — gallery of completed builds

The channel structure drives the workflow: people join, read #welcome,
go to #build. The bot's phase announcements tell them what to do next.

## Key Decisions

1. **No workers for MVP** — Agent tool gives parallel execution without Mercury/tmux overhead
2. **One channel** — lowest friction for meetups, bot drives the flow
3. **Screenshots inline** — visual feedback loop without opening URLs
4. **Administrator bot** — keeper can iterate on Discord structure itself
5. **No FUND phase** — operator pays via Anthropic API
6. **State in context** — no persistence, acceptable for demo-length rounds

## Implementation Order

1. NixOS config (flake, configuration, modules — buildable locally)
2. VPS provisioning (Hetzner, nixos-anywhere, deploy)
3. Discord setup (new app, server, channels, bot token)
4. Keeper CLAUDE.md (the system prompt that makes it all work)
5. Operational scripts (deploy.sh, launch-agent, provision.sh)
6. Landing page update
7. End-to-end test

## Success Criteria

- Someone types !start in #build
- Ideas get pitched, synthesized, voted on
- The keeper builds the app using parallel subagents
- A live URL appears at {name}.tinker.builders
- Screenshots of the app post to #build after each deploy
- People give feedback, the keeper iterates
- !wrap produces a summary and gallery entry in #showcase
- Total time: under 30 minutes for a simple app
