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
- **Caddy** serves the landing page (static files from /var/www/tinker/) on
  tinker.builders with on-demand TLS for app subdomains (`*.tinker.builders`).
  DNS points to the VPS (IP configured via `TINKER_VPS_IP` env var). The
  landing page is deployed from `docs/` via rsync.
- **Credit bot** is a lightweight sidecar service (Node.js) that handles
  `!topup` and `!balance` commands without LLM calls. Lives in
  `services/credit-bot/`, deployed as a NixOS module (`modules/credit-bot.nix`).

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

The bot operates as a phase state machine. Two bang commands control sessions:
`!start` begins a round, `!wrap` ends it. Everything else auto-advances.

```
IDLE ──!start──> PLAN (10 min, hard-gated)
                   ├── PITCH     (0:00 - 4:00)  collect ideas
                   ├── SYNTHESIZE (4:00 - 6:00)  merge into 3 proposals
                   ├── VOTE      (6:00 - 8:00)  emoji reactions
                   └── SPEC      (8:00 - 10:00) write build plan
              ──auto──> FUND (cost estimate + balance gate)
              ──auto──> BUILD (subagent execution, step by step)
              ──auto──> DEPLOY (write NixOS module, rebuild, go live)
              ──auto──> ITERATE (feedback loops, redeploy)
              ──!wrap──> WRAP (summary, showcase, return to IDLE)
```

- **PLAN** is a 10-minute structured phase with four sub-phases. The bot
  runs the clock — no commands needed to advance between sub-phases.
- **FUND** estimates cost ($0.05/step × 1.5 buffer) and checks ppq.ai
  balance. Building hard-blocks on insufficient funds.
- **BUILD** uses subagent calls (stateless curl to ppq.ai) for code
  generation. The orchestrator delegates — it doesn't write code in-context.
- **DEPLOY** writes a NixOS app module to `modules/apps/{name}.nix`,
  commits, and runs `nixos-rebuild switch`. App goes live at
  `{name}.tinker.builders`.
- **ITERATE** runs 90-second feedback windows with redeploys between them.

The phase logic lives in documents/AGENTS.md (the system prompt OpenClaw
injects into every agent session). The v2 design doc is
documents/ROUND-DESIGN.md. The personality lives in SOUL.md.

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
The phase system gives it a state machine: plan → fund → build → deploy →
iterate. OpenClaw's built-in message queue serializes concurrent messages,
so nothing gets dropped.

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
│   ├── tinker.nix            # activation scripts for docs/skills/scripts
│   ├── credit-bot.nix        # NixOS module for credit bot sidecar
│   └── apps/                 # bot writes app modules here (auto-imported)
│       └── _template.nix.example
├── services/
│   └── credit-bot/           # credit bot sidecar (handles !topup, !balance)
│       ├── index.js
│       └── package.json
├── documents/
│   ├── AGENTS.md             # agent behavior — v2 phases, commands, rules
│   ├── ROUND-DESIGN.md       # v2 round design doc (canonical reference)
│   ├── SOUL.md               # personality — voice, tone, principles
│   └── TOOLS.md              # tool-specific notes for the agent
├── skills/
│   └── topup/
│       └── SKILL.md          # Bitcoin Lightning topup skill
├── scripts/
│   ├── tinker-ssh            # SSH into VPS
│   ├── tinker-logs           # tail gateway logs
│   ├── tinker-status         # quick health check
│   ├── tinker-deploy         # deploy with safety checks
│   ├── tinker-config         # read/set openclaw config
│   ├── tinker-balance        # check ppq.ai balance
│   ├── deploy.sh             # core deploy (rsync + remote nixos-rebuild)
│   ├── check-balance.sh      # ppq.ai balance (runs on VPS)
│   ├── topup.sh              # ppq.ai topup (runs on VPS)
│   ├── provision.sh          # Hetzner VPS provisioning via hcloud
│   └── teardown.sh           # destroy Hetzner VPS
├── config/
│   └── openclaw.json         # reference config template
├── docs/
│   └── index.html            # landing page (served via Caddy on VPS)
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

**If changing infrastructure** → edit configuration.nix or modules/tinker.nix.
The flake.nix should rarely change unless swapping inputs.

**If changing the model or provider** → edit config/openclaw.json or the
deploy.sh script that sets the config on the VPS. The ppq.ai provider config
follows OpenClaw's custom provider format: baseUrl, apiKey, api type, and a
models array with id/name/contextWindow/maxTokens.

**If adding a new script the agent can call** → put it in scripts/, make it
executable, and reference it in TOOLS.md so the agent knows it exists. Wire
it into modules/tinker.nix so it gets copied on deploy.

**If working on project coordination** → read STATE.md first. If you're the
meta-agent, update it after significant changes. If you're a lane agent,
read it but don't modify it.

## Things To Be Careful About

- **Secrets never go in the repo.** API keys and bot tokens live in
  /run/secrets/openclaw.env on the VPS (injected via systemd EnvironmentFile).
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

## Developer Commands

Enter the dev shell first: `nix develop` (provides all tools + scripts on PATH).

| Command | Description |
|---------|-------------|
| `tinker-ssh` | SSH into the VPS (interactive or `tinker-ssh <cmd>`) |
| `tinker-logs` | Tail gateway logs (`tinker-logs`, `tinker-logs 100`, `tinker-logs grep <pat>`) |
| `tinker-status` | Quick health check — service state, uptime, memory, port, secrets, last log |
| `tinker-deploy` | Deploy with safety checks — warns about uncommitted changes, confirms before running |
| `tinker-config` | Read/set openclaw config (`tinker-config`, `tinker-config set <path> <val>`, `tinker-config doctor`) |
| `tinker-balance` | Check ppq.ai credit balance via VPS |

All commands use `keys/deploy` for SSH. VPS IP is set via `TINKER_VPS_IP`
env var (scripts have a hardcoded default — check the script source for the
current value).
