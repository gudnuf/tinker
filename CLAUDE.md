# CLAUDE.md — open-builder (Tinker)

## What This Is

Tinker is a Discord bot powered by OpenClaw that lets a group of people
collaboratively build software in real time. Anyone in the channel can propose
ideas, vote on what to build, and guide the AI agent as it writes code live.

The bot is funded by Bitcoin Lightning micropayments via ppq.ai — anyone can
send sats to top up the shared credit pool that pays for LLM inference.

The first use case is a developer meetup demo, but the project is designed to
be general-purpose: any community can spin up a Tinker instance and use it to
build in the open together.

**Brand:** Tinker / tinker.builders / "for the tinkerin' builders"
**Repo:** gudnuf/tinker on GitHub

## Architecture

```
Discord channel
    ↕ (messages)
OpenClaw Gateway (NixOS systemd service)
    ↕ (LLM calls)
ppq.ai (OpenAI-compatible proxy, pay-per-query)
    ↑
⚡ Bitcoin Lightning (anyone tops up credits)
```

- **OpenClaw** is the agent runtime. It handles Discord as a channel, manages
  sessions, runs the agent loop (model call → tool use → respond), and persists
  memory. It runs as a single Node.js process on a NixOS VPS.
- **ppq.ai** is the model provider. It exposes an OpenAI-compatible API and
  accepts Bitcoin Lightning for payment. We configure it as a custom provider
  in openclaw.json.
- **Discord** is the user interface. All interaction happens in a Discord
  server. The bot listens to messages in designated channels.
- **NixOS** is the deployment target. The entire system is declared in a
  single flake. `nixos-rebuild switch` deploys everything.

## How We Build This Project

This project uses a **meta-agent workflow** — one agent holds the strategic
context while lane agents do scoped implementation work. The human operator
bridges them via tmux.

### Roles

- **Human (william):** Final decisions, domain knowledge (OpenClaw, ppq.ai,
  Discord), secret provisioning, VPS setup, Discord app creation. Operates
  the tmux workspace — launches agents, relays outputs, makes allocation calls.
- **Meta-agent:** Coordinates lanes, drafts prompts for lane agents, resolves
  cross-cutting issues, maintains STATE.md. Never writes implementation code.
  Flies high — the moment it starts debugging a specific file, it has abandoned
  its post.
- **Lane agents:** Execute scoped work in tmux panes. Each gets a narrow task,
  clear acceptance criteria, and boundaries on what not to touch.

### Tmux Workspace

```
Session: open-builder

  Window 1: meta    — meta-agent (Claude Code). Strategic coordination.
  Window 2: lane1   — lane agent or idle shell
  Window 3: lane2   — lane agent or idle shell
  Window 4: lane3   — lane agent or idle shell
  Window 5: lane4   — lane agent or idle shell
```

Lane agents are launched by the human pasting prompts drafted by the meta-agent.
Each lane gets its own Claude Code instance with a focused prompt. Lanes don't
talk to each other — they communicate through files and the meta-agent.

### Process Files

| File | Owner | Purpose |
|------|-------|---------|
| STATE.md | Meta-agent | Living dashboard. Current phase, lane status, decisions, blockers, checklists. |
| PROCESS.md | Meta-agent | Coordination rules. Roles, lane scoping, file ownership, decision log. |
| DISCORD-DESIGN.md | Meta-agent | Discord server structure, channel layout, demo plan. |
| CLAUDE.md | Human | This file. Project context for any agent that opens the repo. |

**STATE.md is the source of truth.** Any agent can read it. Only the meta-agent
updates it. If you need to know what's happening, read STATE.md first.

### Coordination Rules

1. **Lanes don't edit each other's files.** Cross-cutting changes go through
   the meta-agent (who drafts the change, human executes).
2. **State lives in STATE.md.** Updated after each significant change.
3. **Secrets never go in the repo.** Placeholder paths only.
4. **Prompts are artifacts.** The meta-agent drafts lane prompts as text blocks
   the human can paste. This is the primary coordination mechanism.

### Workflow Pattern

```
1. Meta-agent reads state, identifies what needs doing
2. Meta-agent drafts a prompt for a lane agent
3. Human pastes prompt into an idle lane
4. Lane agent does scoped work, commits (or leaves changes for review)
5. Meta-agent reviews outputs, updates STATE.md
6. Repeat
```

For brainstorming / design work, the meta-agent drafts exploration prompts
that produce design documents rather than code. These get reviewed and folded
into the project docs.

## How The Bot Works

> Note: the phase system is being redesigned. The description below reflects
> the v1 design in documents/AGENTS.md. A v2 design is in progress that adds
> a 10-minute structured planning phase, cost estimation gates, subagent
> architecture, and Nix-native deployment to subdomains of tinker.builders.

The bot operates in phases, controlled by bang commands:

1. **IDLE** — default. Responds to questions, banter, !topup, !balance.
2. **IDEATION** (!start) — collects ideas from everyone for ~2 minutes.
3. **SYNTHESIS** (!close-ideas) — combines ideas into 3 proposals, group votes.
4. **BUILD** (!pick) — scaffolds the winning project, posts progress.
5. **ITERATE** — collects feedback in ~90s windows, builds what the group wants.
6. **WRAP** (!wrap) — summarizes what was built and who contributed.

The phase logic lives in documents/AGENTS.md which is the system prompt
OpenClaw injects into every agent session. The personality lives in SOUL.md.

## Key Design Decisions

**Why OpenClaw, not a custom Discord bot?**
OpenClaw gives us the full agent loop for free — tool use, exec, web search,
session management, memory, and multi-channel support. We just write the
personality docs and deploy. No agent framework code to maintain.

**Why ppq.ai, not direct Anthropic/OpenAI API?**
ppq.ai lets anyone fund the bot with Bitcoin Lightning. No credit card needed,
no account needed on the LLM provider side. The topup API is programmable —
the bot can generate invoices and post them directly in Discord.

**Why NixOS?**
Declarative, reproducible deployment. The entire system config is in the repo.
Scout-DJ/openclaw-nix gives us security hardening out of the box (systemd
sandboxing, auto TLS, firewall, dedicated user).

**Why phases instead of freeform chat?**
With 10-30 people talking at once, the bot needs structure to avoid chaos.
The phase system gives it a state machine: collect → synthesize → build → repeat.
OpenClaw's built-in message queue serializes concurrent messages, so nothing
gets dropped.

**Why a meta-agent workflow for building the project itself?**
The project has multiple parallel concerns (infra, agent docs, scripts, deploy,
design) that benefit from focused agents. A single agent trying to hold all of
it loses context. The meta-agent keeps the strategic view while lane agents
go deep on specific tasks.

## Project Structure

```
open-builder/
├── flake.nix                 # nix flake — pulls openclaw-nix, defines system
├── configuration.nix         # NixOS config — openclaw service, firewall, ssh
├── disko-config.nix          # disk partitioning for nixos-anywhere
├── modules/
│   └── open-builder.nix      # activation scripts for docs/skills/scripts
├── documents/
│   ├── AGENTS.md             # agent behavior — phases, commands, rules
│   ├── SOUL.md               # personality — voice, tone, principles
│   └── TOOLS.md              # tool-specific notes for the agent
├── skills/
│   └── topup/
│       └── SKILL.md          # Bitcoin Lightning topup skill
├── scripts/
│   ├── topup.sh              # calls ppq.ai topup API
│   ├── check-balance.sh      # calls ppq.ai balance API
│   ├── deploy.sh             # nixos-rebuild + post-deploy config
│   └── provision.sh          # Hetzner VPS provisioning via hcloud
├── config/
│   └── openclaw.json         # reference config template
├── docs/
│   └── index.html            # landing page (GitHub Pages at tinker.builders)
├── CLAUDE.md                 # this file
├── STATE.md                  # meta-agent state dashboard
├── PROCESS.md                # coordination rules and decisions
├── DISCORD-DESIGN.md         # discord server design doc
└── README.md
```

## How To Think About Changes

**If changing agent behavior** → edit documents/AGENTS.md. This is the system
prompt. Phase logic, command handling, Discord formatting rules — it's all here.

**If changing personality/tone** → edit documents/SOUL.md.

**If changing what tools the agent knows about** → edit documents/TOOLS.md.

**If adding a new skill** → create a new directory under skills/ with a SKILL.md.
Follow the topup skill as a template. Skills are self-contained: a SKILL.md
with YAML frontmatter declaring the name, description, and required tools,
plus instructions the agent reads to know how to use it.

**If changing infrastructure** → edit configuration.nix or modules/open-builder.nix.
The flake.nix should rarely change unless swapping inputs.

**If changing the model or provider** → edit config/openclaw.json or the
deploy.sh script that sets the config on the VPS. The ppq.ai provider config
follows OpenClaw's custom provider format: baseUrl, apiKey, api type, and a
models array with id/name/contextWindow/maxTokens.

**If adding a new script the agent can call** → put it in scripts/, make it
executable, and reference it in TOOLS.md so the agent knows it exists. Wire
it into modules/open-builder.nix so it gets copied on deploy.

**If working on project coordination** → read STATE.md first. If you're the
meta-agent, update it after significant changes. If you're a lane agent,
read it but don't modify it.

## Things To Be Careful About

- **Secrets never go in the repo.** API keys and bot tokens live in
  /run/secrets/ on the VPS. The deploy script reads them from there.
- **The agent has exec access.** It can run shell commands inside the systemd
  sandbox. Keep its working directory scoped to /home/openclaw/projects/.
  AGENTS.md tells it to never run destructive commands outside that path.
- **Discord has a 2000 char message limit.** OpenClaw chunks automatically,
  but keep AGENTS.md instructions for message length in mind.
- **ppq.ai balance can hit zero.** The bot should proactively warn when
  credits are low. The threshold is in AGENTS.md.
- **openclaw-nix is still stabilizing.** Check the workarounds gist
  (gudnuf/8fe65ca0e49087105cb86543dc8f0799) if you hit config issues,
  especially around gateway.mode, gateway.auth.token, or missing templates.
- **Git signing requires hardware key.** Claude Code can't trigger the
  hardware key prompt. Commits from agents use `-c commit.gpgsign=false`.
- **No Co-Authored-By footers.** Keep commits clean per global config.

## Useful Commands

```bash
# deploy to VPS
bash scripts/deploy.sh root@your-vps

# check gateway status
ssh root@your-vps "systemctl status openclaw"

# watch logs
ssh root@your-vps "journalctl -u openclaw -f"

# check discord channel connection
ssh root@your-vps "openclaw channels status --probe"

# manually restart gateway
ssh root@your-vps "openclaw gateway restart"

# check ppq.ai balance
ssh root@your-vps "bash /home/openclaw/scripts/check-balance.sh"
```
