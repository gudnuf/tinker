Alright, no file tools this session — here's the `CLAUDE.md`:

---

```markdown
# CLAUDE.md — open-builder

## What This Is

open-builder is a Discord bot powered by OpenClaw that lets a group of people
collaboratively build software in real time. Anyone in the channel can propose
ideas, vote on what to build, and guide the AI agent as it writes code live.

The bot is funded by Bitcoin Lightning micropayments via ppq.ai — anyone can
send sats to top up the shared credit pool that pays for LLM inference.

The first use case is a developer meetup demo, but the project is designed to
be general-purpose: any community can spin up an open-builder instance and
use it to build in the open together.

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

## How The Bot Works

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

## Project Structure

```
open-builder/
├── flake.nix                 # nix flake — pulls openclaw-nix, defines system
├── configuration.nix         # NixOS config — openclaw service, firewall, ssh
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
│   └── deploy.sh             # nixos-rebuild + post-deploy config
├── config/
│   └── openclaw.json         # reference config template
├── CLAUDE.md                 # this file
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
```
