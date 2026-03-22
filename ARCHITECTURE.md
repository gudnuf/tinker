# Tinker v2 — Architecture

How a swarm of Claude Code agents runs collaborative build sessions in
Discord, deployed on NixOS.

Based on proven patterns from the damsac-studio VPS.

---

## MVP vs Full Architecture

This doc describes both the MVP (what we build first) and the full
architecture (where we're heading). Sections marked **(MVP)** are in
scope for the first deploy. Sections marked **(Future)** are designed
but not implemented yet.

**MVP principle:** one Claude Code session, one Discord channel, parallel
subagents via the built-in Agent tool, screenshot feedback loop. No
Mercury, no separate worker processes, no multi-channel routing. Prove
the concept, then layer on infrastructure.

---

## System Overview

### MVP

```
                    DISCORD SERVER
          ┌──────────────────────────────┐
          │  #welcome  #build  #showcase │
          └──────────────┬───────────────┘
                         │
              discord plugin (official)
                         │
          ┌──────────────▼───────────────┐
          │      TINKER VPS (NixOS)      │
          │                              │
          │  keeper:tinker               │
          │  (Claude Code session)       │
          │    ├── Agent → step 1 ─┐     │
          │    ├── Agent → step 2  ├ par │
          │    ├── Agent → step 3 ─┘     │
          │    │                         │
          │    ├── git commit            │
          │    ├── nixos-rebuild         │
          │    ├── chromium --screenshot  │
          │    └── reply (screenshot.png)│
          │                              │
          │  Caddy                       │
          │  app.tinker.builders         │
          └──────────────────────────────┘
```

### Full Architecture (Future)

```
                         DISCORD SERVER
            ┌──────────────────────────────────────┐
            │  #welcome  #build  #showcase          │
            │  #mercury  (+ keeper-created channels)│
            └────────────┬──────────────▲───────────┘
                         │              │
              discord plugin      Mercury→Discord
             (claude-plugins-      feed service
              official)
                         │              │
            ┌────────────▼──────────────┤───────────┐
            │          TINKER VPS (NixOS)            │
            │                                       │
            │  keeper:tinker ◄── Mercury MCP push   │
            │    ├── launch-agent → worker:step-1   │
            │    ├── launch-agent → worker:step-2   │
            │    └── launch-agent → worker:step-3   │
            │                                       │
            │  Caddy → app.tinker.builders          │
            └───────────────────────────────────────┘
```

---

## Discord Integration (from damsac)

### The Official Discord Plugin

Tinker uses `discord@claude-plugins-official` — Anthropic's official
Claude Code Discord plugin. **Not a custom MCP server.** This is the
exact same plugin running on the damsac VPS.

The plugin is a Bun-based MCP server (`server.ts`, ~500 lines) using
`discord.js` + `@modelcontextprotocol/sdk`. It runs as a subprocess
spawned by Claude Code when launched with `--channels plugin:discord@claude-plugins-official`.

**MCP tools it provides to Claude Code:**

| Tool | Purpose |
|------|---------|
| `reply` | Send message to Discord. Supports `chat_id`, `text`, `reply_to` (threading), `files` (attachments). Auto-chunks at 2000 chars. |
| `react` | Add emoji reaction to a message |
| `edit_message` | Edit a previously sent message (progress updates) |
| `fetch_messages` | Pull recent history from a channel (up to 100 messages) |
| `download_attachment` | Download files from a message to `inbox/` |

Inbound messages trigger a typing indicator and are delivered to the
Claude Code session via MCP notification. The agent responds using the
tools above.

### One Bot Token, Multiple Agents

The damsac pattern: **one Discord bot token shared across multiple Claude
Code sessions**, each scoped to different channels via separate state dirs.

```
~/.claude/channels/
├── discord/                        # Default (keeper:tinker → #build)
│   ├── .env                        # DISCORD_BOT_TOKEN=MTIz...
│   └── access.json                 # { groups: { "CHANNEL_ID": {...} } }
├── discord-keeper-feedback/        # Scoped to #feedback
│   ├── .env                        # Same bot token
│   └── access.json                 # Different channel ID
└── discord-keeper-questions/       # Scoped to #questions
    ├── .env                        # Same bot token
    └── access.json                 # Different channel ID
```

Each `access.json` specifies which Discord channel(s) the agent monitors:

```json
{
  "dm": { "policy": "allowlist", "allowlist": ["OPERATOR_USER_ID"] },
  "groups": {
    "DISCORD_CHANNEL_ID": {
      "requireMention": false,
      "allowFrom": []
    }
  }
}
```

`requireMention: false` means the agent sees ALL messages in that channel,
not just @mentions. `allowFrom: []` means any Discord user can trigger it.

### Bot Token Storage

Token lives in `~/.claude/channels/discord/.env`:
```
DISCORD_BOT_TOKEN=MTIz...
```
Set via the `/discord:configure <token>` skill command on first setup.
Copied to each agent's state dir by the `launch-agent` script.

### Discord Bot Permissions

New Discord application, separate from everything else. The bot gets
**full server control** — Administrator permission. The keeper should be
able to create channels, manage roles, adjust server structure, and
iterate on the Discord layout without human intervention.

**Permission:** Administrator (covers everything below and more)

This includes:
- Manage Channels (create, delete, reorder channels and categories)
- Manage Roles (create roles, assign permissions)
- Manage Server (change server name, icon, settings)
- View Channels, Send Messages, Read Message History
- Attach Files, Add Reactions, Manage Messages
- Send Messages in Threads, Create Public/Private Threads
- Embed Links, Use External Emojis

**Intents (all privileged intents ON):**
- DirectMessages (ON)
- Guilds (ON)
- GuildMessages (ON)
- MessageContent (ON — privileged, must enable in Developer Portal)
- GuildMembers (ON — for tracking participants)
- Presence (ON — for seeing who's online)

**Why full access?** The channel structure in this doc is a starting
point. The keeper should be able to create new channels mid-event
(e.g., a per-project feedback channel), restructure categories, set
up temporary voice channels, or adjust permissions — all without the
operator having to touch Discord settings. The whole point is that the
system iterates on itself.

Credentials are locked down on the VPS (secrets file, not in repo).
The bot only runs on our server.

### Channel Structure (MVP)

Three channels. That's it. People join, read #welcome, go to #build.

```
TINKER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  #welcome     (read-only)   what tinker is + how to participate
  #build       (interactive) THE channel. everything happens here.
  #showcase    (read-only)   completed builds — proof this works
```

**Why one interactive channel?** At a meetup, people don't want to switch
between channels. They miss context, they don't know where to go. One
channel means everyone sees everything. The bot's phase announcements
drive the UX — they tell people what to do at each step.

The keeper has **Administrator** permission. If #build gets too noisy
mid-event, the keeper creates additional channels on the fly (e.g.,
a #feedback channel, per-project channels, voice channels). The channel
structure is a living thing that the keeper evolves based on what's
happening. But start with one.

**#welcome** has a pinned message with:
- One-sentence description of Tinker
- The phase flow diagram (visual)
- "Go to #build to participate"

**#build** is the entire experience:
- PITCH: "drop your ideas here" → people type
- VOTE: proposals with emoji reactions → people tap
- BUILD: progress + screenshots → people watch
- FEEDBACK: "what's broken? reply here" → people respond
- WRAP: summary + final screenshot

**#showcase** is the gallery. After each round, the keeper posts the
final build with screenshot, URL, and contributor credits.

### Channel Routing (MVP)

Everything goes to #build. The keeper reads #build and writes to #build.
Gallery posts go to #showcase.

### Channel Structure (Future)

The keeper can create channels as needed. Possible evolution:

- #mercury — Mercury→Discord feed showing agent coordination
- Per-project feedback channels during BUILD
- Voice channels for live discussion
- #ops for admin diagnostics
- Separate #feedback and #questions channels if #build gets noisy

---

## Mercury Integration (from damsac)

### Mercury MCP Plugin

Mercury is not just a CLI — it has an **MCP plugin** that integrates
directly into Claude Code sessions. This is the same plugin running on
damsac (`plugins/mercury/server.ts`).

**How it works:**
- Runs as an MCP server within each Claude Code session
- Polls the Mercury SQLite DB every 2 seconds
- **Pushes** new messages to the agent via `notifications/claude/channel`
  — agents receive messages automatically, no manual polling needed
- Provides tools: `send`, `read`, `subscribe`, `unsubscribe`, `channels`, `log`
- Set identity via `MERCURY_IDENTITY` env var (e.g., `keeper:tinker`)

**Auto-subscribe on startup based on role prefix:**
- `keeper:*` → subscribes to `status`, `studio`, own channel (`keeper:tinker`)
- `worker:*` → subscribes to `status`, `workers`
- `oracle` → subscribes to `status`, `studio`

**Auto-announce:** On startup, sends `"{identity} online"` to `status`.

Agents are launched with `--channels server:mercury` to get the MCP plugin.

### Mercury Channels

| Channel | Purpose | Writers | Readers |
|---------|---------|---------|---------|
| `status` | Agent lifecycle events | All agents | All agents |
| `tinker` | Round coordination + timer events | keeper, timer | keeper |
| `build` | Worker completion signals | Workers | keeper |

### Mercury CLI

The Go binary (`mercury`) is also on PATH for scripted use:

```bash
mercury send --as keeper:tinker --to status "round starting"
mercury read --as keeper:tinker
mercury channels
mercury log --channel build --limit 10
```

The CLI and MCP plugin share the same SQLite database. Messages sent via
one are visible to the other.

### Mercury → Discord Feed

A systemd service that mirrors all Mercury messages to the #mercury
Discord channel. Copied from damsac's `mercury-discord-feed.service`.

**How it works:**
- Bun + discord.js service (`tools/mercury-discord-feed/index.ts`)
- Polls Mercury SQLite DB every 2 seconds for new messages
- Posts each message as a color-coded Discord embed
- Uses the same bot token as the Discord plugin (full discord.js client)
- Persists cursor position to a flat file (survives restarts)
- Color-codes by channel: status=gray, tinker=blurple, build=green
- On startup with large backlog (>100 messages), skips to current

**This is the meetup UX differentiator.** Project #mercury on screen
while #build is on people's phones. Participants watch agents coordinate
in real-time. Theatre AND transparency.

---

## Agent Architecture

### keeper:tinker (MVP)

The central coordinator. A single Claude Code session on the VPS with
the Discord plugin. This is the only process. It handles everything:
phase management, Discord interaction, code generation (via subagents),
deployment, and screenshots.

**Launched with:**
```bash
cd /srv/tinker && claude --dangerously-skip-permissions \
  --channels plugin:discord@claude-plugins-official
```

Or via `launch-agent` (see below):
```bash
launch-agent keeper:tinker BUILD_CHANNEL_ID
```

**Responsibilities:**
- Read Discord messages from #build
- Manage phase transitions (IDLE → PLAN → BUILD → DEPLOY → ITERATE → WRAP)
- Synthesize ideas during PLAN
- Dispatch parallel subagents during BUILD (via Claude Code Agent tool)
- Commit code, run nixos-rebuild, take screenshots
- Post updates, screenshots, and deploy URLs to Discord
- Track contributors and credit them in WRAP

**Where it runs:**
- tmux session `tinker`, window `keeper`
- Working directory: `/srv/tinker/`
- System prompt: `/srv/tinker/.claude/CLAUDE.md`

### Parallel Subagents (MVP)

Build steps are parallelized via Claude Code's built-in **Agent tool**.
The keeper dispatches multiple subagents in a single message — they run
concurrently as child processes sharing the same file system.

**Build flow:**
1. Keeper writes the plan (6-12 steps with dependency graph)
2. Keeper identifies independent steps (no deps on each other)
3. Keeper dispatches 2-3 parallel Agent calls:
   ```
   Agent("Write the Express server scaffold in /srv/tinker/projects/app/")
   Agent("Write the CSS and HTML layout in /srv/tinker/projects/app/public/")
   Agent("Write the database schema in /srv/tinker/projects/app/db/")
   ```
4. Subagents write files, run syntax checks, return summaries
5. Keeper commits all changes at once:
   `git add -A && git commit -m "tinker: app — steps 1-3"`
6. Next batch of steps (that depended on steps 1-3)
7. Repeat until plan is complete

**Why not separate worker processes (tmux/Mercury)?**
A 20-40 minute meetup builds a small-to-medium app. The Agent tool gives
parallel execution with zero infrastructure overhead — no Mercury, no
tmux pane management, no launch-agent for workers. Subagents get their
own clean context (keeper context stays unpolluted) and can iterate on
their own code.

**Performance:** 12-step plan with 3-wide parallelism = 4 rounds instead
of 12. At ~1-2 min per round, that's 4-8 minutes of build time.

### Separate Worker Processes (Future)

For longer builds or when subagent context limits become a problem, the
full worker architecture uses separate Claude Code sessions in tmux,
coordinated via Mercury. See the Mercury Integration and `launch-agent`
sections below.

### Screenshot Flow (MVP)

After every deploy, the keeper takes a screenshot and posts it to #build.
This creates a visual timeline of the app evolving — people see what's
being built without opening the URL.

**Flow:**
1. Keeper deploys (nixos-rebuild)
2. Waits a few seconds for the app to start
3. Takes a screenshot:
   ```bash
   chromium --headless --disable-gpu --no-sandbox \
     --screenshot=/tmp/preview.png --window-size=1280,800 \
     https://app.tinker.builders
   ```
4. Posts to #build with the screenshot attached:
   ```
   ✓ steps 1-3 done: scaffold, layout, database
   live: https://app.tinker.builders

   [screenshot.png]

   4 steps left. poke around and tell me what to change.
   ```

The Discord plugin's `reply` tool supports `files` — up to 10 files,
25MB each. The keeper attaches the screenshot PNG.

**For iteration:** People see the screenshot, reply in #build with
feedback ("make the header bigger", "the button doesn't work"). They
don't even need to open the URL — the screenshot IS the feedback
surface. The keeper reads replies and incorporates feedback.

**NixOS requirement:** headless Chromium in system packages:
```nix
environment.systemPackages = [ pkgs.chromium ];
```

---

## Phase Flow (MVP)

Same phases as v1. The keeper manages timing internally — it's an LLM
with a 1M context window tracking a 10-minute phase, which is fine for
a demo. The operator can nudge if timing drifts.

```
IDLE ──!start──> PLAN (~10 min)
                   ├── PITCH     (~4 min)    collect ideas
                   ├── SYNTHESIZE (~2 min)   merge into 3 proposals
                   ├── VOTE      (~2 min)    emoji reactions
                   └── SPEC      (~2 min)    write build plan
              ──auto──> BUILD (parallel subagents, screenshot after each deploy)
              ──auto──> DEPLOY (nixos-rebuild, screenshot, post URL)
              ──auto──> ITERATE (feedback in #build, screenshot loop)
              ──!wrap──> WRAP (summary + screenshot → #build + #showcase)
```

### State persistence (Future)

MVP: state lives in the keeper's context. If the keeper crashes, the
round is lost. Acceptable for a meetup demo.

Future: phase.json on disk, survives restarts via rekindle.

### Phase details

| Aspect | v1 (OpenClaw) | MVP (Claude Code) |
|--------|---------------|-------------------|
| Timing | LLM-internal | LLM-internal (good enough for demo) |
| State | In-context only | In-context only (phase.json is Future) |
| Discord I/O | OpenClaw Discord plugin | `discord@claude-plugins-official` |
| Code gen | Curl to ppq.ai (stateless) | Parallel subagents via Agent tool |
| Deploy | Single agent rebuilds | Keeper commits + rebuilds |
| Screenshots | None | Headless Chromium after each deploy |
| Feedback | Separate #feedback channel | Inline in #build with screenshots |

### FUND phase (simplified)

The operator (gudnuf) pays via Anthropic API billing. No cost gate.

```
plan ready. {N} steps. building.
```

Lightning funding via ppq.ai deferred to future version.

---

## `launch-agent` Script (from damsac)

The key operational script. Creates per-agent Discord state dirs,
configures Mercury identity, and launches Claude Code with the right
channels.

```bash
#!/usr/bin/env bash
# launch-agent <agent-name> [discord-channel-id ...]
#
# Examples:
#   launch-agent keeper:tinker 123456 789012 345678
#   launch-agent worker:step-3

AGENT_NAME="$1"
shift
DISCORD_CHANNELS=("$@")

CHANNELS_DIR="$HOME/.claude/channels"
DISCORD_DIR="$CHANNELS_DIR/discord"
AGENT_DISCORD_DIR="$CHANNELS_DIR/discord-${AGENT_NAME//:/-}"
PLUGINS_DIR="$HOME/.claude/plugins"

# --- Mercury setup ---
export MERCURY_IDENTITY="$AGENT_NAME"

# Subscribe based on role
ROLE_PREFIX="${AGENT_NAME%%:*}"
mercury subscribe --as "$AGENT_NAME" --channel status
case "$ROLE_PREFIX" in
  keeper)
    mercury subscribe --as "$AGENT_NAME" --channel tinker
    mercury subscribe --as "$AGENT_NAME" --channel build
    ;;
  worker)
    mercury subscribe --as "$AGENT_NAME" --channel build
    ;;
esac

# Announce
mercury send --as "$AGENT_NAME" --to status "$AGENT_NAME online"

# --- Build Claude Code launch args ---
CLAUDE_ARGS=(--dangerously-skip-permissions --channels server:mercury)

# --- Discord setup (only if channel IDs provided) ---
if [ ${#DISCORD_CHANNELS[@]} -gt 0 ]; then
  mkdir -p "$AGENT_DISCORD_DIR"

  # Copy bot token from default Discord state dir
  cp "$DISCORD_DIR/.env" "$AGENT_DISCORD_DIR/.env"

  # Build access.json with specified channels
  GROUPS="{"
  for i in "${!DISCORD_CHANNELS[@]}"; do
    [ $i -gt 0 ] && GROUPS+=","
    GROUPS+="\"${DISCORD_CHANNELS[$i]}\": {\"requireMention\": false, \"allowFrom\": []}"
  done
  GROUPS+="}"

  cat > "$AGENT_DISCORD_DIR/access.json" << EOF
{
  "dm": {"policy": "allowlist", "allowlist": []},
  "groups": $GROUPS
}
EOF

  export DISCORD_STATE_DIR="$AGENT_DISCORD_DIR"
  CLAUDE_ARGS+=(--channels "plugin:discord@claude-plugins-official")
fi

# --- Launch ---
exec claude "${CLAUDE_ARGS[@]}"
```

This script is installed to the `tinker` user's PATH via the NixOS module.

---

## VPS Architecture

### Server

- **Provider:** Hetzner Cloud
- **Type:** cpx31 (4 vCPU, 8 GB RAM)
- **Location:** ash (Ashburn, VA, US)
- **OS:** NixOS (installed via nixos-anywhere)
- **Domain:** tinker.builders + *.tinker.builders (wildcard A record)

### Directory Structure (MVP)

```
/srv/tinker/                       # Git repo root (rsynced from dev machine)
├── flake.nix
├── flake.lock
├── configuration.nix
├── disko-config.nix
├── modules/
│   ├── agent.nix                  # User, tmux, Claude Code, launch-agent, Chromium
│   ├── caddy.nix                  # Landing page + app subdomains
│   └── apps/                      # Subagent-generated app modules
│       └── _template.nix.example
├── .claude/
│   └── CLAUDE.md                  # Keeper system prompt (phases, deployment, screenshots)
├── documents/
│   └── SOUL.md                    # Personality
├── projects/                      # App source code (subagents write here)
│   └── {app-name}/
├── scripts/
│   ├── launch-agent               # Agent launcher
│   ├── deploy.sh                  # rsync + remote nixos-rebuild
│   ├── provision.sh               # Hetzner VPS provisioning
│   └── teardown.sh                # Destroy VPS
└── docs/
    └── index.html                 # Landing page
```

Future additions: `tools/mercury-discord-feed/`, `plugins/mercury/`,
`state/phase.json`, `modules/mercury.nix`.

### Secrets

File: `/run/secrets/tinker.env` (created manually on VPS before first deploy)

```
ANTHROPIC_API_KEY=sk-ant-...
DISCORD_BOT_TOKEN=MTIz...
```

The bot token is also stored at `~/.claude/channels/discord/.env` for
the Claude Code Discord plugin (set via `/discord:configure` on first
agent launch).

### Users

| User | Purpose | Home |
|------|---------|------|
| `tinker` | Runs Claude Code sessions + workers | `/srv/tinker` |
| `root` | System management, nixos-rebuild | — |

Passwordless sudo for nixos-rebuild:

```nix
security.sudo.extraRules = [{
  users = [ "tinker" ];
  commands = [{
    command = "/run/current-system/sw/bin/nixos-rebuild";
    options = [ "NOPASSWD" ];
  }];
}];
```

### Tmux Layout

```
Session: tinker (owned by tinker user, auto-created on SSH)

  Window 0: keeper    — keeper:tinker (Claude Code + Discord + Mercury)
  Window 1: worker-1  — idle or active worker
  Window 2: worker-2  — idle or active worker
  Window 3: ops       — operational shell
```

Auto-attach on SSH login (from damsac `home.nix` pattern):

```bash
# In .zshrc:
if [[ -n "$SSH_CONNECTION" ]] && [[ -z "$TMUX" ]]; then
  SESSION="tinker"
  if ! tmux has -t "$SESSION" 2>/dev/null; then
    tmux new-session -d -s "$SESSION" -c /srv/tinker
  fi
  exec tmux attach -t "$SESSION"
fi
```

---

## NixOS Flake Design (MVP)

### Inputs

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

Removed from v1: `openclaw`, `deploy-rs`, `nixos-anywhere`.
Mercury flake input deferred to Future (not needed for MVP).

### NixOS Configuration

```nix
nixosConfigurations.tinker = nixpkgs.lib.nixosSystem {
  modules = [
    disko.nixosModules.disko
    ./disko-config.nix
    ./configuration.nix
    ./modules/agent.nix
    ./modules/caddy.nix
  ] ++ (dynamicAppImports);
};
```

### modules/agent.nix

Provides:
- `tinker` system user (home: `/srv/tinker/`, shell: zsh, wheel group)
- Packages on PATH: claude-code, bun, tmux, git, jq, curl, ripgrep, fd, chromium
- `launch-agent` script on PATH
- zsh with tmux auto-attach on SSH login
- Claude Code configuration:
  - `~/.claude/settings.json` with `enabledPlugins: { "discord@claude-plugins-official": true }`
  - Workspace CLAUDE.md at `/srv/tinker/.claude/CLAUDE.md`
- `/srv/tinker/` directory structure (projects/, docs/, modules/apps/)
- Passwordless sudo for nixos-rebuild

### modules/caddy.nix

Provides:
- Landing page at `tinker.builders` → `/srv/tinker/docs/`
- On-demand TLS for `*.tinker.builders`
- Firewall: ports 22, 80, 443
- App modules in `modules/apps/` add their own virtualHosts

### modules/apps/ (dynamic import — unchanged from v1)

```nix
imports = let appsDir = ./modules/apps; in
  if builtins.pathExists appsDir then
    map (f: appsDir + "/${f}")
      (builtins.attrNames
        (lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".nix" n)
          (builtins.readDir appsDir)))
  else [];
```

### Dev Shell

```nix
devShells.default = pkgs.mkShell {
  packages = with pkgs; [ openssh rsync jq curl hcloud ];
  shellHook = ''
    export PATH="$PWD/scripts:$PATH"
    echo "tinker dev shell"
  '';
};
```

---

## App Deployment Model (unchanged from v1)

1. Worker writes app code to `/srv/tinker/projects/{name}/`
2. Worker writes NixOS module to `/srv/tinker/modules/apps/{name}.nix`
3. `git add -A && git commit -m "tinker: {name} — {what}"`
4. Keeper runs: `sudo nixos-rebuild switch --flake /srv/tinker#tinker`
5. Caddy picks up the subdomain, provisions TLS
6. App live at `https://{name}.tinker.builders`

Same systemd sandboxing, port allocation (10001-10099), Caddy reverse
proxy, and static site shortcut as v1. See documents/ROUND-DESIGN.md §6.

---

## Operational Procedures

### Starting an Event

1. SSH into VPS: `tinker-ssh` (auto-attaches to tmux)
2. In the keeper window:
   ```bash
   launch-agent keeper:tinker BUILD_CHANNEL_ID FEEDBACK_CHANNEL_ID QUESTIONS_CHANNEL_ID
   ```
3. Keeper connects to Discord, announces online in #build
4. Share Discord invite QR code at the meetup

### Stopping an Event

1. `!wrap` in #build (or keeper auto-wraps after silent feedback windows)
2. Keeper posts summary and gallery entry
3. Leave running for next event, or kill the Claude Code session

### Monitoring

- `tinker-status` — health check (services, ports, disk)
- `tinker-logs` — tail systemd journal
- #mercury Discord channel — real-time agent coordination
- #ops Discord channel — admin diagnostics

### Recovering from Keeper Crash

1. `tinker-ssh` → check tmux
2. Re-launch keeper in the keeper window
3. Keeper reads `/srv/tinker/state/phase.json`, resumes
4. Posts in #build: "back. picking up where we left off."

### Deploying Config Changes

```bash
tinker-deploy  # From operator's dev machine:
# 1. rsync flake to VPS (exclude projects/, apps/, state/, prompts/)
# 2. remote nixos-rebuild switch
# 3. verify services
```

---

## What to Copy from damsac

| damsac source | Tinker destination | Adaptation needed |
|---|---|---|
| `modules/home.nix` → `launch-agent` | `scripts/launch-agent` | Change role-based subscriptions, remove jj references |
| `modules/home.nix` → packages | `modules/agent.nix` | Same package set minus Go/Air (add nodejs) |
| `modules/home.nix` → zsh tmux auto-attach | `modules/agent.nix` | Change session name to `tinker`, socket path optional |
| `modules/claude.nix` → settings + MCP config | `modules/agent.nix` | Write Tinker CLAUDE.md instead of damsac CLAUDE.md |
| `modules/claude.nix` → Mercury plugin install | `modules/mercury.nix` | Same plugin source, just copy |
| `modules/mercury-feed.nix` | `modules/mercury.nix` | Change Discord channel ID, same service structure |
| `tools/mercury-discord-feed/index.ts` | `tools/mercury-discord-feed/index.ts` | Change channel colors/names, same code |
| `plugins/mercury/server.ts` | `plugins/mercury/server.ts` | Copy as-is, same protocol |
| `modules/tmux.nix` | `modules/agent.nix` (simplified) | Single user, no shared socket needed |
| `modules/workspace.nix` | `modules/agent.nix` | `/srv/tinker` instead of `/srv/damsac` |
| `modules/users.nix` | `modules/agent.nix` | Single `tinker` user instead of gudnuf+isaac |
| `disko-config.nix` | `disko-config.nix` | Unchanged — same Hetzner boot layout |

---

## What's Deferred

| Feature | Why | Target |
|---------|-----|--------|
| Mercury + MCP plugin | Not needed with Agent tool subagents | Future |
| Mercury→Discord feed (#mercury) | No Mercury yet | Future |
| Separate worker processes (tmux) | Agent tool parallelism is sufficient | Future |
| phase.json state persistence | Context is fine for demo length | Future |
| External timer service | Keeper manages time internally | Future |
| Lightning funding (ppq.ai) | Different runtime model | Future |
| Credit-bot sidecar | No ppq.ai | Future |
| Self-improving meta-structure | Need event data first | Future |
| Discord threads per build step | Not critical for first event | Future |
| App gallery web page | Nice-to-have | Future |
| Automated app TTL cleanup | Manual for now | Future |
| jj instead of git | Adds complexity for meetups | Future |
| Concurrent rounds | One at a time is fine | Future |

---

## Implementation Plan (MVP)

### 1. NixOS Config (can build locally before VPS exists)
- Rewrite flake.nix (remove openclaw, just nixpkgs + disko)
- Rewrite configuration.nix (base system: networking, SSH, boot, sudoers)
- Keep disko-config.nix (unchanged)
- Write modules/agent.nix (tinker user, Claude Code, Chromium, tmux, launch-agent)
- Write modules/caddy.nix (landing page + wildcard TLS for app subdomains)
- Verify: `nix flake check` passes

### 2. VPS Provisioning
- Generate new SSH key pair for deploy
- Provision Hetzner cpx31 in Ashburn via provision.sh
- Install NixOS via nixos-anywhere
- Deploy NixOS config via deploy.sh
- Create `/run/secrets/tinker.env` (ANTHROPIC_API_KEY, DISCORD_BOT_TOKEN)
- Verify: SSH works, services running, Caddy serves landing page

### 3. Discord Setup (human: gudnuf)
- Create new Discord application + bot (Administrator permission, all intents)
- Create Discord server with 3 channels (#welcome, #build, #showcase)
- Write #welcome pinned message
- Add bot to server
- SSH to VPS, configure bot token: `/discord:configure <token>`
- Set up access.json for #build channel
- Verify: keeper can read/write in #build

### 4. Keeper System Prompt
- Write .claude/CLAUDE.md (phases, subagent dispatch, deployment, screenshots, personality)
- Include SOUL.md content (terse dev voice)
- Include NixOS app module template
- Include commit-before-rebuild instructions
- Include screenshot flow instructions
- Verify: launch keeper, run a test round

### 5. Operational Scripts
- Rewrite deploy.sh for new directory structure (/srv/tinker/)
- Update provision.sh (new VPS, new SSH key)
- Write launch-agent script
- Verify: full deploy cycle from dev machine

### 6. Landing Page
- Update docs/index.html for v2
- Keep it simple: what Tinker is, Discord invite QR/link

### 7. End-to-End Test
- SSH in, launch keeper
- Run a full round: !start → pitch → vote → build → deploy → screenshot → iterate → !wrap
- Verify: app deploys to subdomain, screenshots post to #build, #showcase gets gallery entry
- Tune CLAUDE.md based on what works
