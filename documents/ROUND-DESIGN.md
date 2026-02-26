# Tinker — Round Design

How a group of people in a Discord channel go from zero to a deployed app
at `{name}.tinker.builders` in under an hour.

---

## 1. Round Phases

A round is a single build session. One round runs at a time. The lifecycle:

```
IDLE ──!start──> PLAN (10 min, hard-gated)
                   ├── PITCH     (0:00 - 4:00)
                   ├── SYNTHESIZE (4:00 - 6:00)
                   ├── VOTE      (6:00 - 8:00)
                   └── SPEC      (8:00 - 10:00)
              ──auto──> FUND (cost estimate + balance gate)
              ──auto──> BUILD (subagent execution, step by step)
              ──auto──> DEPLOY (write NixOS module, rebuild, go live)
              ──auto──> ITERATE (feedback loops, redeploy)
              ──!wrap──> WRAP (summary, showcase, return to IDLE)
```

Phase transitions are explicit announcements in #build. The bot always states
what phase it's entering and what happens next. No ambiguity.

Key change from the old design: IDEATION and SYNTHESIS are merged into a
single 10-minute PLAN phase with internal time gates. BUILD and DEPLOY are
separated — the agent builds locally first, then deploys. ITERATE now
includes live URLs people can actually test.

---

## 2. The 10-Minute Planning Phase

The PLAN phase is the most structured part of a round. Four sub-phases,
each with a hard time gate enforced by the bot. No human needs to type
a command to advance — the bot runs the clock.

### Minute 0:00 — PITCH opens

Triggered by `!start`. The bot posts:

```
round starting. pitch your ideas — what should we build?

you've got 4 minutes. anything goes: apps, tools, games, weird stuff.
one idea per message. go.
```

The bot starts a 4-minute internal timer.

**Bot behavior during PITCH:**
- Acknowledge each idea with a brief reaction ("solid", "interesting",
  "ambitious but sure"). No long responses.
- Track ideas as `{ author, text }` pairs.
- If the channel is quiet after 1 minute, nudge: "anyone else? 3 minutes
  left."
- If only 1-2 ideas by minute 2, encourage: "need more raw material here.
  doesn't have to be polished — just throw something out."

### Minute 4:00 — PITCH closes, SYNTHESIZE begins

The bot auto-closes PITCH. No command needed. Posts:

```
ideas closed. got {N} from {M} people. synthesizing into proposals...
```

The bot takes 1-2 minutes to combine ideas into exactly 3 buildable
proposals. Rules for synthesis:

- Merge related ideas. If three people said variations of "chat app," that's
  one proposal.
- Make each proposal concrete enough to build in 30-40 minutes. If an idea
  is too ambitious, scope it down and say so.
- Credit contributors by Discord username.
- Each proposal gets a one-line title and a 2-sentence description.
- The proposals should be genuinely different directions, not three flavors
  of the same thing.

### Minute 6:00 — SYNTHESIZE posts, VOTE opens

The bot posts proposals and opens voting:

```
three options. react to vote — you've got 2 minutes.

**1️⃣ [title]**
[description]. (from @user1, @user2)

**2️⃣ [title]**
[description]. (from @user3)

**3️⃣ [title]**
[description]. (from @user1, @user4)

most votes at 8:00 wins. tie = i pick.
```

The bot adds 1️⃣ 2️⃣ 3️⃣ reactions to its own message as seeds.

**During VOTE:**
- The bot stays quiet. Let people vote.
- If someone asks a clarifying question about a proposal, answer briefly.
- At 7:30: "30 seconds left to vote."

### Minute 8:00 — VOTE closes, SPEC begins

The bot tallies reactions and announces the winner:

```
option {N} wins: "{title}" — {X} votes.
writing the build plan...
```

**Tie-breaking:** If two options are tied, the bot picks the one that's
more buildable in the time available. If all three are tied, the bot picks
randomly and owns it: "three-way tie. going with option 2 — it's the most
buildable in our window."

The bot now writes a detailed build plan. This is the critical artifact.
The plan has:

1. **Project name** (kebab-case, becomes the subdomain)
2. **One-line summary**
3. **Tech stack** (language, framework, key libraries)
4. **Architecture** (what components exist, how they connect)
5. **Numbered build steps** (6-20 steps, each a discrete piece of work)
6. **Acceptance criteria** (what "done" looks like for the whole project)

Each build step has:
- A short title
- What it produces (files, endpoints, UI elements)
- Dependencies on other steps (which steps must complete first)

### Minute 10:00 — SPEC posts, PLAN ends

The bot posts the plan. Because plans can be long, it uses 2-3 Discord
messages, breaking at logical boundaries (e.g., steps 1-7 in one message,
steps 8-15 in another).

After the plan, the bot auto-transitions to FUND:

```
plan ready. {N} steps. checking if we can afford this...
```

### What if things go wrong?

**Nobody pitches ideas:** If 0 ideas by minute 2:00, the bot nudges. If
still 0 by 3:00, the bot offers a seed: "alright, here are two starter
ideas: [X] or [Y]. riff on these or pitch your own. 1 minute left." If
0 by 4:00, the bot aborts: "no ideas, no build. try again when
inspiration strikes." Returns to IDLE.

**Only one idea:** Skip VOTE. The bot confirms: "only one idea — building
that. writing the plan..." and jumps to SPEC at minute 4:00 (reclaims
the vote time for planning).

**Someone pitches late (during SYNTHESIZE/VOTE):** Too late. The bot says:
"ideas are closed but i'll keep that in mind if we iterate." Does not
re-open PITCH.

**Group wants to change the plan after SPEC:** They can — during ITERATE.
The plan is a starting point, not a contract. But the bot doesn't re-plan
before building. Build first, iterate after.

**The 10 minutes feel rushed:** They should. Constraint breeds focus. If
10 minutes consistently feels too short, this is a tuning knob — bump to
12 or 15. But start tight.

---

## 3. Cost Gate

After the plan is posted, the bot estimates cost and checks the balance.
Building does NOT start until this gate passes.

### Cost Estimation Model

The bot estimates cost based on step count. Each build step costs LLM
tokens — both for the subagent call that generates code and for the
orchestrator overhead (reviewing, posting updates, handling errors).

**Per-step cost estimate: $0.05**

This is a blended rate that accounts for:
- ~2-4K input tokens per subagent call (plan step + file context)
- ~1-2K output tokens per subagent call (generated code)
- Orchestrator overhead (reading files, composing messages, review)
- Claude Sonnet pricing through ppq.ai

For a 15-step plan: 15 × $0.05 = $0.75 base.

**Buffer: 50%** — to cover retries, iteration, errors, and overhead
that's hard to predict.

15-step plan estimated cost: $0.75 × 1.5 = **$1.13**

The bot rounds to the nearest $0.25 for presentation. The estimate is
intentionally conservative — better to over-estimate and have credits left
than to run dry mid-build.

### The Gate

The bot runs `check-balance.sh` and compares against the estimate.
Three outcomes:

**FUNDED** (balance > estimate × 1.5):
```
cost estimate: ~$1.25 for {N} steps
balance: $4.50 ✓

we're good. building.
```
Auto-transitions to BUILD.

**TIGHT** (estimate < balance < estimate × 1.5):
```
cost estimate: ~$1.25 for {N} steps
balance: $1.60 — that's close.

we can probably do it but no margin for iteration.
someone might want to !topup before we start. or we build lean.

starting in 30 seconds unless someone objects.
```
Waits 30 seconds, then auto-transitions to BUILD.

**SHORT** (balance < estimate):
```
cost estimate: ~$1.25 for {N} steps
balance: $0.40 — not enough.

need at least $0.85 more. that's roughly {sats} sats.
someone !topup and we'll get going.
```
Posts a lightning invoice to #topup. Waits. Checks balance every 60
seconds. When funded, announces in #build: "funded. let's go."

**BROKE** (balance < $0.10):
```
credits are basically zero. need a !topup before we can do anything.
```
Same as SHORT but more direct.

### Simplification Escape Hatch

If the group thinks the plan is too expensive, they can simplify.

Anyone can say "cut steps" or "simplify" during the FUND phase. The bot
responds: "which steps do you want to drop?" or offers: "i can cut
steps {X, Y, Z} — they're nice-to-haves. that'd bring it down to ~$0.75.
drop them?"

If the group agrees, the bot revises the plan, recalculates, and re-checks
the gate. This doesn't restart the 10-minute clock — it's a quick
amendment.

---

## 4. Subagent Architecture

The main agent (running inside OpenClaw) is the **orchestrator**. It does
NOT write code itself. It delegates code generation to **subagent calls**
— direct API calls to ppq.ai via curl.

### Why Not Build In-Context?

The orchestrator's context window fills up with:
- Discord messages (every message from every participant)
- Phase announcements, plan text, status updates
- Coordination logic (tracking steps, handling errors)

If it also generates code in-context, it degrades fast. By step 8 of a
15-step plan, the model is working with 100K+ tokens of accumulated
context and the code quality drops.

Subagent calls start fresh. Each call gets only what it needs: the
specific step, the relevant existing files, and the project conventions.
Clean context = better code.

### How It Works

For each build step, the orchestrator:

1. **Reads the step** from the plan (title, description, dependencies)
2. **Gathers context** — reads any existing project files the step depends
   on (using OpenClaw's read tool)
3. **Constructs a prompt** — a focused system message + user message:

   System: "You are a code generator. You write one piece of a larger
   project. Output complete file contents. Do not explain — just write
   code. Use the specified tech stack. Follow existing conventions in
   the provided files."

   User: "Project: {name}. Tech: {stack}. Step {N}: {description}.
   Existing files: [file contents]. Write: {expected output files}."

4. **Calls ppq.ai** via exec + curl:

   ```
   exec: curl -s -X POST https://api.ppq.ai/chat/completions \
     -H "Authorization: Bearer $OPENAI_API_KEY" \
     -H "Content-Type: application/json" \
     -d @/tmp/step-{N}-prompt.json
   ```

   The orchestrator writes the prompt to a temp JSON file first (easier
   than escaping in a curl command), then reads the response.

5. **Parses the response** — extracts code blocks, maps them to file paths
6. **Writes files** to `/home/openclaw/projects/{name}/` using OpenClaw's
   write tool
7. **Reviews** — reads the written files back, runs a basic sanity check
   (does it parse? does it import its dependencies?)
8. **Posts progress** to #build: "step {N} done: {what was built}"

### Subagent Context Budget

Each subagent call should stay under 8K input tokens:
- System prompt: ~200 tokens
- Step description: ~200 tokens
- Existing file context: ~4K tokens (2-3 relevant files)
- Tech stack / conventions: ~200 tokens
- Buffer: ~3.4K tokens

If a step requires more context (e.g., it touches 6 files), the
orchestrator breaks it into sub-steps or summarizes the existing code
instead of including full files.

Output budget: 4K tokens per subagent call. If a single file needs to
be longer, the step should be split.

### Failure Handling

**API error (network, rate limit, 500):**
Retry once after 5 seconds. If still failing, post to #build: "api hiccup
on step {N}. trying again..." Retry a second time. If still failing,
pause and ask the group: "stuck on step {N}. api issues. wait or skip?"

**Bad code (doesn't parse, missing imports):**
The orchestrator re-prompts the subagent with the error: "previous attempt
had this error: {error}. fix it." One retry. If still broken, the
orchestrator attempts a manual fix (it can edit files directly). If that
fails, skip the step and note it as a known issue.

**Subagent goes off-script (builds something different from the step):**
The orchestrator compares the output against the step description. If
it's clearly wrong, discard and re-prompt with a more explicit instruction.
This should be rare if the prompts are focused.

**Credits run out mid-build:**
The orchestrator checks balance every 3 steps. If balance drops below
$0.25, it pauses: "credits getting low. need a !topup to keep going.
i'll wait." Posts an invoice to #topup.

### What Subagents Are NOT

This is not a multi-process architecture. There are no long-running
subagent processes. Each "subagent" is a single, stateless API call.
The orchestrator is the only persistent process. It calls the API,
gets a response, and moves on. The word "subagent" describes a pattern,
not a process.

OpenClaw runs as a single Node.js process. We work within that. The
orchestrator uses OpenClaw's exec tool to make curl calls. No separate
processes, no IPC, no job queues.

---

## 5. Build Phase Mechanics

After the FUND gate passes:

### Kickoff

```
building: {project-name}
{N} steps. estimated time: {N × 2} minutes.
updates in #build. questions in #questions. deployments in #feedback.
```

### Step Execution

Steps execute sequentially (respecting dependency order from the plan).
For each step:

1. **Announce** in #build:
   ```
   [step {i}/{N}] {step title}
   ```

2. **Delegate** to subagent (curl call, as described in section 4)

3. **Write files** to project directory

4. **Verify** — run a quick check if possible:
   - For Node: `node -c {file}` (syntax check)
   - For Python: `python -c "import ast; ast.parse(open('{file}').read())"`
   - For static files: just check they exist
   - For anything with a build step: run it

5. **Commit** the step's work:
   ```
   cd /home/openclaw/system && git add -A && \
     git commit -m "tinker: {name} — step {i}: {step title}"
   ```

6. **Report** in #build:
   ```
   ✓ step {i}: {what was produced}
   ```
   Include a brief code snippet (key function signature or important logic)
   if it's interesting. Not the full file — just the highlight.

7. **Handle questions** — if the step requires a decision the plan didn't
   cover, post to #questions:
   ```
   step {i} question: the plan says "user auth" but doesn't specify
   the method. options:
   A) simple password (fastest)
   B) magic link via email (needs SMTP)
   C) OAuth with GitHub (needs client ID)
   what do you want?
   ```
   Wait for a response in #questions. Timeout after 2 minutes — pick
   the simplest option and note it: "going with A, we can change it
   in iteration."

### First Deploy (MVP)

After enough steps complete to have something runnable (usually 60-70%
through the plan), the orchestrator deploys:

1. Writes the NixOS app module (see section 6)
2. Commits: `git add -A && git commit -m "tinker: {name} — v0 deploy"`
3. Rebuilds: `sudo nixos-rebuild switch --flake .#open-builder`
4. Verifies the app is accessible
5. Posts in #build:
   ```
   v0 is live: https://{name}.tinker.builders
   basic version — still have {remaining} steps to go.
   ```
6. Posts in #feedback:
   ```
   first deploy is up: https://{name}.tinker.builders
   poke around and tell me what's broken or what you want.
   ```

### Remaining Steps + Iteration

After the first deploy, the orchestrator continues executing remaining
plan steps AND accepts feedback simultaneously:

- Remaining plan steps execute as before
- Feedback from #feedback gets queued
- After completing each step, the orchestrator checks #feedback for
  new messages
- Small feedback items (typos, color changes) get folded into the
  current step
- Larger feedback items get queued for the ITERATE phase

### ITERATE Phase

Once all plan steps are done, the bot enters ITERATE:

```
plan complete. {N}/{N} steps done.
live at https://{name}.tinker.builders

taking feedback. what do you want changed? you've got 90 seconds.
```

Iteration loop:
1. 90-second feedback window — collect messages from #feedback
2. Synthesize feedback into a change list
3. Announce: "building: {change summary}"
4. Execute changes (same subagent pattern, 1-3 steps per iteration)
5. Commit: `git add -A && git commit -m "tinker: {name} — iteration: {summary}"`
6. Redeploy: `sudo nixos-rebuild switch --flake .#open-builder`
7. Post updated URL and open next feedback window
8. Repeat until `!wrap` or group says "good enough"

If feedback is contradictory, the bot calls it out in #build:
```
@user1 wants dark mode, @user2 wants it brighter. pick one, team.
```

If no feedback comes in a window, the bot prompts once: "no changes?
say !wrap if you're happy, or tell me what to fix." If still nothing
after another 60 seconds, the bot auto-wraps.

---

## 6. Nix Deployment Model

Every round produces a deployed app. The deployment is Nix-native:
the agent writes a NixOS module, rebuilds the system, and the app goes
live at a subdomain with TLS.

### System Layout on the VPS

```
/home/openclaw/
├── system/                     # git repo — copy of the flake + agent additions
│   ├── flake.nix
│   ├── flake.lock
│   ├── configuration.nix
│   ├── disko-config.nix
│   ├── keys/
│   │   └── deploy.pub
│   ├── modules/
│   │   ├── open-builder.nix
│   │   └── apps/               # agent writes app modules here
│   │       ├── lightning-tip-jar.nix
│   │       └── pixel-art-wall.nix
│   └── ...
├── projects/                   # app source code (inside the same git repo)
│   ├── lightning-tip-jar/
│   │   ├── server.js
│   │   ├── package.json
│   │   └── ...
│   └── pixel-art-wall/
│       └── ...
└── scripts/
    ├── check-balance.sh
    └── topup.sh
```

### Commit-Before-Rebuild Rule

Nix flakes have a hard rule: **in a git repo, only git-tracked files are
visible to the evaluator.** Untracked or unstaged files are invisible to
`nixos-rebuild`. This means the agent MUST commit before every rebuild.

This is a feature, not a bug. Every rebuild is backed by a git commit,
giving us:
- **Full history** of what the agent built, step by step
- **Diffable changes** — the operator can `git log` to see exactly what
  happened during a round
- **Rollback via git** — in addition to NixOS generations, we can
  `git revert` a bad app module
- **Auditability** — every deploy has a commit message explaining what
  changed and why

The agent follows this pattern for every deploy:

```bash
cd /home/openclaw/system
git add -A
git commit -m "tinker: {project-name} — {what changed}"
sudo nixos-rebuild switch --flake .#open-builder
```

The `git add -A` captures everything: new app modules, modified project
files, deleted files. No file is invisible. The commit message follows a
convention: `tinker: {project} — {description}`.

### Commit Cadence

The agent commits at every meaningful checkpoint, not just deploys:

| Event                         | Commit message example                                    |
|-------------------------------|-----------------------------------------------------------|
| Plan finalized                | `tinker: lightning-tip-jar — build plan (12 steps)`       |
| Build step completed          | `tinker: lightning-tip-jar — step 3: express routes`      |
| App module written            | `tinker: lightning-tip-jar — nixos module, port 10001`    |
| First deploy                  | `tinker: lightning-tip-jar — v0 deploy`                   |
| Iteration change              | `tinker: lightning-tip-jar — iteration: dark mode toggle` |
| Final wrap                    | `tinker: lightning-tip-jar — final`                       |

This means a typical round produces 15-25 commits. Each one is small,
focused, and describes exactly what the agent did. The operator can
review the full build history with `git log --oneline`.

### Deploy Script (Operator → VPS)

The deploy script syncs the repo's base config to the VPS without
wiping agent-created content:

```bash
# In scripts/deploy.sh — sync base config, preserve agent work
rsync -av --delete \
  --exclude '.git' \
  --exclude 'modules/apps' \
  --exclude 'projects' \
  ./ root@$VPS:/home/openclaw/system/

# Commit the base config update on the VPS
ssh root@$VPS "cd /home/openclaw/system && git add -A && \
  git commit -m 'operator: base config update' --allow-empty && \
  sudo nixos-rebuild switch --flake .#open-builder"
```

The rsync excludes `modules/apps/` and `projects/` so operator deploys
don't wipe what the agent has built. The commit on the VPS records the
base config change in the same git history as the agent's work.

### App NixOS Module Template

Each app gets a NixOS module at `/home/openclaw/system/modules/apps/{name}.nix`.
The agent generates this. A typical module:

```nix
# Auto-generated by Tinker for round: lightning-tip-jar
{ config, pkgs, lib, ... }:
{
  # Systemd service
  systemd.services."tinker-lightning-tip-jar" = {
    description = "Tinker app: lightning-tip-jar";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      WorkingDirectory = "/home/openclaw/projects/lightning-tip-jar";
      ExecStart = "${pkgs.nodejs}/bin/node server.js";
      Restart = "on-failure";
      RestartSec = 5;

      # Sandboxing
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [ "/home/openclaw/projects/lightning-tip-jar" ];
      PrivateTmp = true;
      NoNewPrivileges = true;

      # Resource limits
      MemoryMax = "256M";
      CPUQuota = "50%";

      # Environment
      Environment = [
        "PORT=10001"
        "NODE_ENV=production"
      ];
    };
  };

  # Caddy reverse proxy (extends the existing Caddy config)
  services.caddy.virtualHosts."lightning-tip-jar.tinker.builders" = {
    extraConfig = ''
      reverse_proxy localhost:10001
    '';
  };

  # Firewall — Caddy handles external access, apps only bind localhost
  # (no additional ports needed)
}
```

### Dynamic Module Import

The system's `configuration.nix` imports all .nix files from the apps
directory:

```nix
imports = [
  ./modules/open-builder.nix
] ++ (
  let
    appsDir = ./modules/apps;
  in
    if builtins.pathExists appsDir then
      map (f: appsDir + "/${f}")
        (builtins.attrNames
          (lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".nix" n)
            (builtins.readDir appsDir)))
    else []
);
```

When the agent adds a new .nix file to `modules/apps/` and runs
`nixos-rebuild switch`, the system picks it up automatically.

### Port Allocation

Apps get ports from a reserved range: **10001-10099**.

The agent assigns ports sequentially. Before creating a new module, it
scans existing modules for used ports and picks the next available one.

Convention: port = 10000 + round number. First round gets 10001, second
gets 10002, etc. The round number is tracked in a simple counter file
at `/home/openclaw/system/modules/apps/.next-port`.

### DNS

**Wildcard A record:** `*.tinker.builders` → `46.225.140.108`

This is a single DNS record set once. Every subdomain automatically
resolves to the VPS. Caddy handles TLS via Let's Encrypt with on-demand
TLS or a wildcard cert.

Caddy config for wildcard TLS (in the base NixOS config):

```nix
services.caddy = {
  enable = true;
  globalConfig = ''
    on_demand_tls {
      ask http://localhost:5555/check  # internal endpoint that validates subdomains
    }
  '';
};
```

The validation endpoint is a simple script that checks if the subdomain
has a corresponding app module. This prevents abuse (someone pointing
a random subdomain at the VPS and getting a TLS cert).

### Rebuild Flow

The agent triggers deployment by:

1. Writing the app code to `/home/openclaw/projects/{name}/`
2. Writing the NixOS app module to `/home/openclaw/system/modules/apps/{name}.nix`
3. Committing and rebuilding:
   ```
   cd /home/openclaw/system
   git add -A
   git commit -m "tinker: {name} — {what changed}"
   sudo nixos-rebuild switch --flake .#open-builder
   ```

The `git add -A` ensures Nix sees every file — new, modified, or deleted.
The commit records what changed. The rebuild applies it. Three commands,
always in this order, never skipped.

The openclaw user has passwordless sudo for exactly this command:

```nix
security.sudo.extraRules = [{
  users = [ "openclaw" ];
  commands = [{
    command = "${pkgs.nixos-rebuild}/bin/nixos-rebuild";
    options = [ "NOPASSWD" ];
  }];
}];
```

A rebuild takes 15-30 seconds for an incremental change (adding one
service). The agent posts "deploying..." before and "live" after.

### Rollback

If a deploy breaks something, the agent runs:

```
sudo nixos-rebuild switch --rollback
```

This reverts to the previous system generation. Built-in NixOS feature,
no extra tooling needed.

The agent detects failed deploys by:
- nixos-rebuild exit code != 0
- The app URL returns an error after rebuild
- The systemd service fails to start (checked via `systemctl is-active`)

### Sandboxing

Each app runs in its own systemd service with:
- **DynamicUser=true** — gets a unique UID, no persistent user to compromise
- **ProtectSystem=strict** — can't write outside designated paths
- **ProtectHome=read-only** — can read project files but can't modify others
- **MemoryMax=256M** — can't OOM the host
- **CPUQuota=50%** — can't starve other services
- **PrivateTmp=true** — isolated /tmp
- **NoNewPrivileges=true** — can't escalate

A misbehaving app can't take down the host or affect other apps.

### What Can Be Built?

Anything Nix can package and run:
- **Node.js apps** — Express, Fastify, plain http.createServer
- **Python apps** — Flask, FastAPI, plain http.server
- **Static sites** — served by Caddy directly (no app service needed)
- **Go binaries** — compiled, single binary, fast startup
- **Deno/Bun** — if available in nixpkgs
- **Shell scripts** — a cgi-bin vibe, if someone's feeling retro

The tech choice is made during SPEC based on what the group wants to build.
The agent picks the simplest stack that works. Default preference order:
static HTML > Node.js > Python > Go.

### Static Site Shortcut

For apps that are purely static (HTML/CSS/JS, no server), skip the
systemd service entirely. Just write files and add a Caddy file server:

```nix
services.caddy.virtualHosts."pixel-art-wall.tinker.builders" = {
  extraConfig = ''
    root * /home/openclaw/projects/pixel-art-wall/public
    file_server
  '';
};
```

No port allocation needed. Faster rebuild. This is the happy path for
simple apps.

### App Lifecycle

- **Active:** app is running, subdomain is live, Caddy serves it
- **Stopped:** service stopped but module still exists. URL returns 502.
- **Archived:** module removed, files kept in projects/ for reference
- **Deleted:** everything gone (manual operator action only)

**Default TTL: 30 days.** After 30 days, the operator moves apps from
active to archived. A cron job or systemd timer can automate this
(stop the service, remove the module, rebuild). Project source files
persist indefinitely unless manually cleaned.

For v1, the operator manages this manually. Automated TTL is v2.

---

## 7. Discord Channel Map

### Server Structure

```
━━ TINKER ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📌 WELCOME
  #readme              read-only     what tinker is, how to join a round
  #how-it-works        read-only     phase diagram, example session transcript

🔨 BUILD
  #build               interactive   the stage — phases, plans, progress
  #feedback            interactive   test the app, report bugs, suggest changes
  #questions           interactive   bot asks, humans answer

⚡ FUNDING
  #credits             interactive   !topup, !balance, invoices, payment confirms

🏆 SHOWCASE
  #gallery             read-only     completed builds with live URLs

💬 COMMUNITY
  #general             no bot        human chat, banter, off-topic
  #ideas               no bot        async idea parking between rounds

🔧 META (admin only)
  #ops                 admin only    deploy logs, bot health, system status
```

### Channel Details

**#build — the stage**
- The primary channel. All phase announcements happen here.
- Bot reads and writes. Everyone can write.
- During PLAN: ideas go here, proposals posted here, votes here.
- During BUILD: step progress posted here.
- During ITERATE: iteration announcements here.
- This is the channel people watch. If you only follow one channel,
  follow this one.

**#feedback — testing ground**
- Bot posts deploy URLs here with a prompt: "test this and tell me
  what's broken."
- Humans respond with bugs, feature requests, opinions.
- Bot reads this channel during BUILD and ITERATE to collect feedback.
- Not active during PLAN or IDLE.
- Keeps test chatter out of #build so the main channel stays readable.

**#questions — bot asks, humans answer**
- Bot posts clarifying questions during BUILD: "dark mode — toggle or
  always dark?"
- Humans answer. Bot reads responses and acts on them.
- Keeps Q&A out of #build.
- If nobody answers in 2 minutes, bot picks the simplest option and
  announces in #build.

**#credits — funding**
- All money-related interactions: !topup, !balance, invoices, payment
  confirmations.
- Bot posts lightning invoices here (with the bolt11 string).
- Bot acknowledges !topup in #build briefly ("invoice posted in
  #credits") to avoid cluttering the build flow.
- Cost estimates during FUND phase are posted in #build (they're part
  of the round flow) but the actual invoice goes to #credits.

**#gallery — completed builds**
- Bot auto-posts here after !wrap with:
  - Project name and one-line description
  - Live URL (https://{name}.tinker.builders)
  - Contributors
  - Key stats (steps, time, cost)
- Read-only. Only the bot writes here.
- This becomes the portfolio of what the community has built.

**#general — human space**
- Bot does NOT read or write here.
- Pure human chat. Off-topic welcome.
- Where people hang out between rounds.

**#ideas — idea parking lot**
- Bot does NOT read or write here.
- Between rounds, people can drop ideas for future builds.
- When someone types !start, they can reference ideas from here.
- Not structured. Just a scratchpad.

**#ops — admin only**
- System health, deploy logs, error monitoring.
- The operator watches this channel.
- Bot could optionally log internal errors here (v2).

### Bot Channel Permissions

| Channel     | Bot Reads | Bot Writes | Purpose                    |
|-------------|-----------|------------|----------------------------|
| #build      | yes       | yes        | phase flow, progress       |
| #feedback   | yes       | yes        | deploy URLs, bug reports   |
| #questions  | yes       | yes        | clarifications             |
| #credits    | yes       | yes        | invoices, balance          |
| #gallery    | no        | yes        | showcase posts             |
| #general    | no        | no         | human space                |
| #ideas      | no        | no         | human space                |
| #ops        | no        | optional   | admin diagnostics          |

### Message Routing

The bot routes messages to the right channel based on type:

| Message Type            | Channel      |
|-------------------------|-------------|
| Phase announcement      | #build      |
| Plan / proposals        | #build      |
| Step progress           | #build      |
| Deploy URL              | #build + #feedback |
| Bug report prompt       | #feedback   |
| Clarifying question     | #questions  |
| Cost estimate           | #build      |
| Lightning invoice       | #credits    |
| Payment confirmation    | #credits    |
| Balance report          | #credits    |
| Wrap summary            | #build + #gallery |

---

## 8. Round Lifecycle

### Starting a Round

1. Someone types `!start` in #build
2. Bot checks: are we in IDLE? If not, reject: "round in progress.
   !wrap it first."
3. Bot checks balance: if < $0.10, reject: "credits are empty.
   !topup first."
4. PLAN phase begins (10-minute clock starts)

### During a Round

One round at a time. No concurrent rounds. The bot tracks its current
phase as internal state. Phase transitions are announced and sequential.

If the bot crashes mid-round (OpenClaw restarts), the round state is lost.
The bot returns to IDLE. The project files on disk persist, so the operator
can manually restart where things left off. Resilient round state
persistence is v2 (would require writing state to disk).

### Ending a Round

`!wrap` triggers the wrap phase. The bot:

1. Runs a final deploy if there are uncommitted changes
2. Posts a summary in #build:
   ```
   round complete: {project-name}

   what we built:
   - {bullet point 1}
   - {bullet point 2}
   - {bullet point 3}

   live at: https://{name}.tinker.builders

   contributors:
   - @user1 — original idea, feedback on v2
   - @user2 — dark mode suggestion, found the auth bug
   - @user3 — proposed the project name

   {N} steps, {M} iterations, ~${cost} in credits
   ```

3. Posts to #gallery:
   ```
   **{project-name}**
   {one-line description}
   🔗 https://{name}.tinker.builders
   built by: @user1, @user2, @user3
   ```

4. Returns to IDLE

### Between Rounds

In IDLE state, the bot:
- Responds to general chat in #build (but keeps it brief)
- Handles !topup, !balance, !status, !help
- If credits are low, periodically nudges: "credits are at $X. someone
  !topup before next round."
- Does NOT start building anything unprompted
- Does NOT read #general or #ideas

### What Persists After a Round

| What                          | Where                                          | TTL          |
|-------------------------------|------------------------------------------------|-------------|
| App source code               | /home/openclaw/projects/{name}/                | indefinite  |
| NixOS app module              | /home/openclaw/system/modules/apps/{name}.nix  | 30 days     |
| Running systemd service       | active on VPS                                  | 30 days     |
| Live subdomain                | https://{name}.tinker.builders                 | 30 days     |
| Gallery post in #showcase     | Discord message                                | forever     |
| Build log in #build           | Discord message history                        | forever     |

### Cleanup (operator-managed for v1)

After 30 days, the operator:
1. Stops the systemd service: `systemctl stop tinker-{name}`
2. Removes the app module: `rm modules/apps/{name}.nix`
3. Runs `nixos-rebuild switch` to apply
4. Optionally archives the project source or deletes it

A cleanup script (`scripts/archive-app.sh`) could automate steps 1-3.
Not a priority for launch.

---

## 9. Open Questions

### Must resolve before building

1. **Does openclaw-nix include Caddy?** The module configures a domain
   and opens ports 80/443, which implies a web server. Need to confirm
   it's Caddy (not nginx or something else) so the app modules can extend
   its config. If it's not Caddy, we need to add our own — or use whatever
   it provides.

2. **Can the openclaw user access $OPENAI_API_KEY at exec time?** The
   EnvironmentFile is set on the openclaw-gateway systemd service. The
   exec tool runs commands inside that service's context, so the env vars
   should be available. But need to confirm — if the exec tool spawns a
   separate process outside the service context, the env vars won't be
   there and subagent curl calls won't work.

3. **Passwordless sudo for nixos-rebuild — security implications?** Giving
   the openclaw user (which the agent controls) sudo access to
   nixos-rebuild means a compromised or misbehaving agent could
   rewrite the system config. The systemd sandbox mitigates some of this,
   but nixos-rebuild is powerful. Alternative: a dedicated rebuild service
   that the agent triggers via a socket or signal, scoped to only read
   modules from the apps directory.

4. **Flake on the VPS — resolved.** The deploy script rsyncs the base
   config to `/home/openclaw/system/` (excluding `.git`, `modules/apps/`,
   and `projects/`). The VPS system directory is a git repo. The agent
   commits all changes before every rebuild so Nix always sees the full
   current state. See "Commit-Before-Rebuild Rule" section above.

### Should resolve but not blocking

5. **check-balance.sh sends an empty POST body** — ppq.ai might require
   a `credit_id` field. Needs validation against the actual API.

6. **Port conflicts** — if an app crashes and its port is "in use" by a
   zombie process, the next rebuild will fail. systemd should handle this
   (it manages the process lifecycle), but worth testing.

7. **App dependencies** — Node.js apps need `npm install`. This means the
   VPS needs npm and node in the system packages (or the agent runs them
   via nix-shell). The NixOS module's ExecStart uses `${pkgs.nodejs}/bin/node`,
   but the project's node_modules need to exist. The agent needs to run
   `npm install` as a build step before deploying.

8. **Caddy TLS rate limits** — Let's Encrypt has rate limits. On-demand TLS
   generates a cert per subdomain. If the VPS gets many subdomains quickly
   (unlikely for v1 but possible), we'll hit limits. A wildcard cert
   (via DNS challenge) avoids this but requires DNS API access.

### Deferred to v2

9. **Round state persistence** — currently, if OpenClaw restarts mid-round,
   the round is lost. Persisting phase state to disk would allow resuming.

10. **Concurrent rounds** — multiple rounds in parallel, each with its own
    subagent context. Requires either multiple OpenClaw instances or a
    fundamentally different architecture.

11. **Code export** — posting final code to GitHub (gist or repo) after
    !wrap. Needs a GitHub token and API integration.

12. **QR codes for Lightning invoices** — killer demo moment. Needs
    qrencode and image posting to Discord. Stretch goal.

13. **Spectator role** — read-only access for people who just want to
    watch. Currently everyone can write to #build, which means anyone
    can !start or !wrap. A session-owner model (only the person who
    !started can !wrap) would help.

14. **Automated app TTL** — systemd timer that archives apps after 30 days
    without manual operator intervention.
