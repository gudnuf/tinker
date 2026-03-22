# Tinker v2 MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a Claude Code session on a NixOS VPS that runs collaborative build rounds in Discord — people pitch ideas, vote, the agent builds with parallel subagents, deploys to subdomains, posts screenshots, iterates on feedback.

**Architecture:** Single Claude Code session (keeper:tinker) with the official Discord plugin, parallel build via Agent tool subagents, headless Chromium for screenshots, NixOS + Caddy for app deployment to *.tinker.builders subdomains. Three Discord channels: #welcome, #build, #showcase.

**Tech Stack:** NixOS, Claude Code, Discord plugin (`discord@claude-plugins-official`), Caddy, headless Chromium, git, tmux

**Spec:** `docs/superpowers/specs/2026-03-22-tinker-v2-mvp-design.md`
**Architecture doc:** `ARCHITECTURE.md`

**Git conventions:** Always commit with `-c commit.gpgsign=false` (hardware key not available). No Co-Authored-By footers.

---

## File Structure

### Files to CREATE

| File | Responsibility |
|------|---------------|
| `modules/agent.nix` | tinker user, Claude Code + deps, tmux auto-attach, launch-agent, Chromium, sudoers |
| `modules/caddy.nix` | Landing page, wildcard TLS, app subdomain reverse proxies, firewall |
| `.claude/CLAUDE.md` | Keeper system prompt — phases, subagent dispatch, deployment, screenshots, personality |
| `scripts/launch-agent` | Create Discord state dir, launch Claude Code with --channels |

### Files to REWRITE

| File | What changes |
|------|-------------|
| `flake.nix` | Remove openclaw + deploy-rs + nixos-anywhere inputs. Keep nixpkgs + disko. |
| `configuration.nix` | Remove all openclaw config. Keep networking/SSH/boot. Import new modules. |
| `scripts/deploy.sh` | New paths (/srv/tinker/ instead of /etc/nixos/), new excludes |
| `scripts/provision.sh` | Update SSH key name, server type, location |
| `docs/index.html` | Update copy for v2, new Discord invite placeholder |

### Files UNCHANGED

| File | Why |
|------|-----|
| `disko-config.nix` | Same Hetzner boot layout |
| `keys/deploy.pub` | Same SSH key format (new key will be generated) |
| `documents/SOUL.md` | Personality carries over |
| `documents/ROUND-DESIGN.md` | Phase reference (still valid) |
| `scripts/teardown.sh` | VPS teardown script, still useful |

### Files to DELETE

| File | Why |
|------|-----|
| `modules/tinker.nix` | Replaced by modules/agent.nix |
| `modules/credit-bot.nix` | ppq.ai deferred |
| `services/credit-bot/` | ppq.ai deferred |
| `config/openclaw.json` | No more openclaw |
| `scripts/check-balance.sh` | ppq.ai deferred |
| `scripts/topup.sh` | ppq.ai deferred |
| `scripts/tinker-balance` | ppq.ai deferred |
| `scripts/tinker-config` | openclaw-specific |
| `skills/topup/SKILL.md` | ppq.ai deferred |
| `LANE4-CHECKPOINT.md` | v1 artifact |

---

## Task 1: Clean Up v1 Artifacts

**Files:**
- Delete: `modules/tinker.nix`, `modules/credit-bot.nix`, `services/credit-bot/`, `config/openclaw.json`, `scripts/check-balance.sh`, `scripts/topup.sh`, `scripts/tinker-balance`, `scripts/tinker-config`, `skills/topup/SKILL.md`, `LANE4-CHECKPOINT.md`

- [ ] **Step 1: Delete v1-only files**

```bash
cd /Users/claude/.superset/projects/open-builder
rm -f modules/tinker.nix modules/credit-bot.nix
rm -rf services/credit-bot
rm -f config/openclaw.json && rmdir config 2>/dev/null || true
rm -rf skills/topup && rmdir skills 2>/dev/null || true
rm -f scripts/check-balance.sh scripts/topup.sh scripts/tinker-balance scripts/tinker-config
rm -f LANE4-CHECKPOINT.md
```

- [ ] **Step 2: Verify no broken references**

Check that no remaining file references the deleted files:
```bash
grep -r "credit-bot\|openclaw.json\|check-balance\|topup\.sh\|tinker-balance\|tinker-config\|LANE4" --include='*.nix' --include='*.sh' --include='*.md' . | grep -v '.git/' | grep -v 'ARCHITECTURE.md' | grep -v 'docs/superpowers/'
```
Expected: no results (or only references in docs/specs that describe what was removed)

- [ ] **Step 3: Commit**

```bash
git -c commit.gpgsign=false add -A
git -c commit.gpgsign=false commit -m "chore: remove v1 openclaw artifacts (credit-bot, ppq.ai scripts, openclaw config)"
```

---

## Task 2: Rewrite flake.nix

**Files:**
- Rewrite: `flake.nix`

- [ ] **Step 1: Write the new flake**

```nix
{
  description = "tinker — collaborative AI building platform";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko }:
    let
      system = "x86_64-linux";
      devSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forDevSystems = nixpkgs.lib.genAttrs devSystems;
    in
    {
      nixosConfigurations.tinker = nixpkgs.lib.nixosSystem {
        modules = [
          disko.nixosModules.disko
          {
            nixpkgs.hostPlatform = system;
          }
          ./disko-config.nix
          ./configuration.nix
          ./modules/agent.nix
          ./modules/caddy.nix
        ];
      };

      devShells = forDevSystems (devSystem:
        let pkgs = nixpkgs.legacyPackages.${devSystem};
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              openssh
              rsync
              jq
              curl
              hcloud
            ];
            shellHook = ''
              export PATH="$PWD/scripts:$PATH"
              echo "tinker dev shell — run 'tinker-status' to check VPS"
            '';
          };
        }
      );
    };
}
```

- [ ] **Step 2: Commit**

```bash
git -c commit.gpgsign=false add flake.nix
git -c commit.gpgsign=false commit -m "feat: rewrite flake.nix — remove openclaw, keep nixpkgs + disko"
```

---

## Task 3: Write modules/agent.nix

This is the biggest module. It sets up the tinker user, installs Claude Code and dependencies, configures tmux auto-attach, and provides the launch-agent script.

**Files:**
- Create: `modules/agent.nix`

**Reference:** Check how damsac installs Claude Code — `ssh damsac "which claude && claude --version 2>/dev/null"` and `ssh damsac "nix eval /etc/nixos#nixosConfigurations.damsac.config.users.users.gudnuf.packages --json 2>/dev/null | head -5"`. The key question is whether Claude Code is available as a nixpkg or needs a custom derivation. The simplest approach: include `nodejs` in system packages and install Claude Code to the user's home via npm in an activation script.

- [ ] **Step 1: Research Claude Code packaging on damsac**

```bash
ssh damsac "which claude; file \$(which claude); claude --version 2>/dev/null; head -5 \$(which claude) 2>/dev/null"
```

Note the result — this determines how we package Claude Code for Tinker.

- [ ] **Step 2: Write modules/agent.nix**

The module must provide:

1. **`tinker` user** — home: `/srv/tinker/`, shell: zsh, in `wheel` group
2. **System packages** — tmux, git, jq, curl, ripgrep, fd, chromium, nodejs, bun
3. **Claude Code** — on PATH for the tinker user (method TBD from step 1)
4. **Tmux auto-attach** — in the tinker user's `.zshrc`:
   ```bash
   if [[ -n "$SSH_CONNECTION" ]] && [[ -z "$TMUX" ]]; then
     SESSION="tinker"
     if ! tmux has -t "$SESSION" 2>/dev/null; then
       tmux new-session -d -s "$SESSION" -c /srv/tinker
     fi
     exec tmux attach -t "$SESSION"
   fi
   ```
5. **Directory structure** — activation script creates `/srv/tinker/{projects,docs,modules/apps,state,prompts}`
6. **Claude Code settings** — activation script writes `~/.claude/settings.json`:
   ```json
   { "enabledPlugins": { "discord@claude-plugins-official": true } }
   ```
7. **Sudoers** — passwordless nixos-rebuild for tinker user
8. **Git config** — set user.name and user.email for commits

9. **SSH authorized keys** — tinker user gets the deploy key so `tinker-ssh` works:
   ```nix
   users.users.tinker.openssh.authorizedKeys.keys = [
     (builtins.readFile ./keys/deploy.pub)
   ];
   ```

Key constraints:
- The `tinker` user must own `/srv/tinker/` and all contents
- `/srv/tinker/` must be a git repo (initialized by activation script if not exists)
- Claude Code needs ANTHROPIC_API_KEY in the environment — sourced by `launch-agent` from `/run/secrets/tinker.env`
- Chromium needs `--no-sandbox` flag when run as non-root (or set up the sandbox)

**Claude Code packaging:** If you cannot SSH to damsac to check how it's packaged, use the npm approach: include `nodejs` in system packages and use an activation script to run `su - tinker -c "npm install -g @anthropic-ai/claude-code"`, or write a custom Nix derivation wrapping the npm package using `pkgs.buildNpmPackage`.

- [ ] **Step 3: Verify nix evaluation**

```bash
nix eval .#nixosConfigurations.tinker.config.users.users.tinker.home 2>&1 | head -5
```

Expected: `"/srv/tinker"` or a nix eval showing the user config is valid.

- [ ] **Step 4: Commit**

```bash
git -c commit.gpgsign=false add modules/agent.nix
git -c commit.gpgsign=false commit -m "feat: add modules/agent.nix — tinker user, Claude Code, tmux, Chromium"
```

---

## Task 4: Write modules/caddy.nix

**Files:**
- Create: `modules/caddy.nix`

- [ ] **Step 1: Write modules/caddy.nix**

```nix
{ config, pkgs, lib, ... }:

{
  # --- Caddy web server ---
  services.caddy = {
    enable = true;

    # Landing page
    virtualHosts."tinker.builders" = {
      extraConfig = ''
        root * /srv/tinker/docs
        file_server
      '';
    };

    # Wildcard handler for app subdomains
    # Individual app modules add their own virtualHosts
    # e.g., services.caddy.virtualHosts."myapp.tinker.builders"
  };

  # Ensure docs directory exists
  systemd.tmpfiles.rules = [
    "d /srv/tinker/docs 0755 tinker tinker -"
  ];

  # Firewall
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
```

Note: On-demand TLS for wildcard subdomains requires Caddy configuration. For MVP, each app module explicitly adds its own virtualHost and Caddy provisions TLS per-subdomain via Let's Encrypt. Wildcard cert (DNS challenge) is a future optimization.

- [ ] **Step 2: Commit**

```bash
git -c commit.gpgsign=false add modules/caddy.nix
git -c commit.gpgsign=false commit -m "feat: add modules/caddy.nix — landing page + app subdomain support"
```

---

## Task 5: Rewrite configuration.nix

**Files:**
- Rewrite: `configuration.nix`

- [ ] **Step 1: Write the new configuration.nix**

Strip out all openclaw config. Keep: networking, SSH, boot, locale.
Import dynamic app modules.

```nix
{ config, pkgs, lib, ... }:

{
  # --- Dynamic App Module Imports ---
  imports = let
    appsDir = ./modules/apps;
  in
    if builtins.pathExists appsDir then
      map (f: appsDir + "/${f}")
        (builtins.attrNames
          (lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".nix" n)
            (builtins.readDir appsDir)))
    else [];

  # --- Networking ---
  networking = {
    hostName = "tinker";
    useNetworkd = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
      # Caddy ports (80, 443) opened by modules/caddy.nix
    };
  };

  systemd.network.networks."10-wan" = {
    matchConfig.Name = "eth* en*";
    networkConfig.DHCP = "ipv4";
    dhcpV4Config.UseDNS = true;
    linkConfig.RequiredForOnline = "routable";
  };

  # --- SSH ---
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    (builtins.readFile ./keys/deploy.pub)
  ];

  # --- Boot ---
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "/dev/sda";
  };

  boot.initrd.availableKernelModules = [
    "virtio_pci" "virtio_blk" "virtio_scsi" "virtio_net" "ahci"
  ];

  # --- Locale ---
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # --- System ---
  system.stateVersion = "24.11";
}
```

- [ ] **Step 2: Run nix flake check**

```bash
nix flake check 2>&1 | head -20
```

Expected: no errors (or only warnings about missing hardware on dev machine).
If there are eval errors, fix them before proceeding.

- [ ] **Step 3: Commit**

```bash
git -c commit.gpgsign=false add configuration.nix
git -c commit.gpgsign=false commit -m "feat: rewrite configuration.nix — remove openclaw, clean NixOS base"
```

---

## Task 6: Write the Keeper System Prompt

This is the most critical file. It's what makes the keeper behave correctly during a round.

**Files:**
- Create: `.claude/CLAUDE.md`
- Reference: `documents/SOUL.md` (personality), `documents/ROUND-DESIGN.md` (phase details)

- [ ] **Step 1: Read SOUL.md and ROUND-DESIGN.md for reference**

Read both files to understand the personality voice and phase flow details.

- [ ] **Step 2: Write .claude/CLAUDE.md**

The keeper system prompt must cover:

**Identity & Voice:**
- Inline the SOUL.md personality (terse, lowercase, dev energy)
- "you are tinker. you run collaborative build rounds in discord."

**Phase Flow:**
- IDLE: respond to chat, handle !start, !help, !status
- PLAN (~10 min): PITCH → SYNTHESIZE → VOTE → SPEC
  - Pitch: collect ideas, acknowledge briefly, track contributors
  - Synthesize: merge into 3 proposals, credit authors
  - Vote: emoji reactions on proposals, tally at deadline
  - Spec: write build plan with numbered steps, tech stack, deps
- BUILD: dispatch parallel subagents, commit after each batch, deploy mid-build
- DEPLOY: commit, nixos-rebuild, screenshot, post URL + screenshot
- ITERATE: show screenshot, collect feedback, make changes, redeploy
- WRAP: summary, final screenshot, post to #showcase, return to IDLE

**Subagent Dispatch:**
- Use the Agent tool for parallel build steps
- Identify independent steps from the plan's dependency graph
- Each subagent gets: step description, project path, tech stack, what files exist
- Subagents write code to `/srv/tinker/projects/{name}/`
- After subagents return, batch commit all changes

**NixOS Deployment:**
- App module template (the full .nix template from ROUND-DESIGN.md)
- Write to `/srv/tinker/modules/apps/{name}.nix`
- Port allocation: 10001-10099, check existing modules for used ports
- Static site shortcut (Caddy file_server, no systemd)
- Commit-before-rebuild: `git add -A && git commit && sudo nixos-rebuild switch --flake /srv/tinker#tinker`
- On failure: `sudo nixos-rebuild switch --rollback`

**Screenshot Flow:**
- After every deploy:
  ```bash
  chromium --headless --disable-gpu --no-sandbox \
    --screenshot=/tmp/preview.png --window-size=1280,800 \
    https://{name}.tinker.builders
  ```
- Post screenshot to #build using the `reply` tool with `files` parameter

**Discord Formatting:**
- 2000 char limit, keep under 1800
- Fenced code blocks with language tags
- Break long content across 2-3 messages
- Bold for emphasis, not caps

**Bang Commands:**
- `!start` — begin round (check: are we IDLE?)
- `!wrap` — end round (from BUILD or ITERATE)
- `!help` — list commands
- `!status` — current phase, project, URL if deployed

**Rules:**
- All project work in `/srv/tinker/projects/{name}/`
- NixOS modules in `/srv/tinker/modules/apps/`
- Only sudo command: nixos-rebuild
- Credit contributors by Discord username
- Never read #general or #ideas (they don't exist in MVP, but the principle holds)

- [ ] **Step 3: Commit**

```bash
git -c commit.gpgsign=false add .claude/CLAUDE.md
git -c commit.gpgsign=false commit -m "feat: write keeper system prompt — phases, subagents, deployment, screenshots"
```

---

## Task 7: Write launch-agent Script

**Files:**
- Create: `scripts/launch-agent`

- [ ] **Step 1: Write scripts/launch-agent**

```bash
#!/usr/bin/env bash
set -euo pipefail

# launch-agent <agent-name> [discord-channel-id ...]
#
# Sets up Discord state dir (if channel IDs given) and launches
# Claude Code with the appropriate --channels flags.
#
# Examples:
#   launch-agent keeper:tinker 123456789
#   launch-agent worker:step-3

AGENT_NAME="${1:?Usage: launch-agent <agent-name> [discord-channel-id ...]}"
shift
DISCORD_CHANNELS=("${@}")

CHANNELS_DIR="$HOME/.claude/channels"
DISCORD_DIR="$CHANNELS_DIR/discord"
AGENT_DISCORD_DIR="$CHANNELS_DIR/discord-${AGENT_NAME//:/-}"

# --- Source secrets (API keys) ---
if [ -f /run/secrets/tinker.env ]; then
  set -a
  source /run/secrets/tinker.env
  set +a
fi

CLAUDE_ARGS=(--dangerously-skip-permissions)

# --- Discord setup (only if channel IDs provided) ---
if [ ${#DISCORD_CHANNELS[@]} -gt 0 ]; then
  mkdir -p "$AGENT_DISCORD_DIR"

  # Copy bot token from default Discord state dir
  if [ -f "$DISCORD_DIR/.env" ]; then
    cp "$DISCORD_DIR/.env" "$AGENT_DISCORD_DIR/.env"
  else
    echo "error: no bot token found at $DISCORD_DIR/.env"
    echo "run: /discord:configure <token> in a Claude Code session first"
    exit 1
  fi

  # Build access.json with specified channels
  GROUPS="{"
  for i in "${!DISCORD_CHANNELS[@]}"; do
    [ "$i" -gt 0 ] && GROUPS+=","
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

echo "launching $AGENT_NAME..."
exec claude "${CLAUDE_ARGS[@]}"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/launch-agent
```

- [ ] **Step 3: Commit**

```bash
git -c commit.gpgsign=false add scripts/launch-agent
git -c commit.gpgsign=false commit -m "feat: add launch-agent script — Discord state dir + Claude Code launcher"
```

---

## Task 8: Update Operational Scripts

**Files:**
- Rewrite: `scripts/deploy.sh`
- Rewrite: `scripts/provision.sh`
- Delete: `scripts/tinker-ssh`, `scripts/tinker-deploy`, `scripts/tinker-status`, `scripts/tinker-logs` (rewrite as needed)

- [ ] **Step 1: Rewrite scripts/deploy.sh**

Key changes from v1:
- Sync to `/srv/tinker/` (not `/etc/nixos/`)
- Exclude `projects/`, `modules/apps/`, `state/`, `prompts/`, `.claude/channels/`
- Rebuild with `--flake /srv/tinker#tinker`
- Sync landing page to `/srv/tinker/docs/`
- SSH key path: `keys/deploy`

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOST="${1:-${TINKER_VPS_IP:?Set TINKER_VPS_IP or pass host as argument}}"
SSH_KEY="$PROJECT_DIR/keys/deploy"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

if [[ ! -f "$SSH_KEY" ]]; then
  echo "error: SSH key not found at $SSH_KEY" >&2
  exit 1
fi

cd "$PROJECT_DIR"
echo "deploying tinker to $HOST..."

echo "syncing config to /srv/tinker/..."
rsync -az --delete \
  --exclude='.git' \
  --exclude='secrets/' \
  --exclude='infra/' \
  --exclude='keys/deploy' \
  --exclude='projects/' \
  --exclude='modules/apps/*.nix' \
  --exclude='state/' \
  --exclude='prompts/' \
  --exclude='.claude/channels/' \
  -e "ssh $SSH_OPTS" \
  "$PROJECT_DIR/" "root@${HOST}:/srv/tinker/"

echo "rebuilding on VPS..."
ssh $SSH_OPTS "root@${HOST}" "cd /srv/tinker && nixos-rebuild switch --flake .#tinker"

echo ""
echo "deploy complete. verifying..."
ssh $SSH_OPTS "root@${HOST}" "
  echo 'caddy:' \$(systemctl is-active caddy 2>/dev/null || echo inactive)
  echo 'ssh:' \$(systemctl is-active sshd 2>/dev/null || echo inactive)
  id tinker 2>/dev/null && echo 'tinker user: exists' || echo 'tinker user: MISSING'
  test -d /srv/tinker && echo '/srv/tinker: exists' || echo '/srv/tinker: MISSING'
"
echo "done."
```

- [ ] **Step 2: Rewrite scripts/provision.sh**

Update for new VPS:
- Location: `ash` (Ashburn)
- Server type: `cpx31`
- SSH key name: `tinker-deploy`
- Post-install: create `/run/secrets/tinker.env` placeholder message
- Reference: the existing provision.sh structure is good, just update constants

Key changes:
- `LOCATION="${1:-ash}"`
- `SERVER_TYPE="cpx31"`
- `SSH_KEY_NAME="tinker-deploy"`
- Post-install message: mention ANTHROPIC_API_KEY and DISCORD_BOT_TOKEN

- [ ] **Step 3: Write simple tinker-ssh helper**

```bash
#!/usr/bin/env bash
# SSH into the Tinker VPS as the tinker user (auto-attaches to tmux)
HOST="${TINKER_VPS_IP:?Set TINKER_VPS_IP}"
KEY="$(dirname "$0")/../keys/deploy"
exec ssh -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "tinker@${HOST}" "$@"
```

- [ ] **Step 4: Make scripts executable and commit**

```bash
chmod +x scripts/deploy.sh scripts/provision.sh scripts/tinker-ssh
git -c commit.gpgsign=false add scripts/
git -c commit.gpgsign=false commit -m "feat: rewrite deploy.sh + provision.sh for v2, add tinker-ssh"
```

---

## Task 9: Update Landing Page

**Files:**
- Modify: `docs/index.html`

- [ ] **Step 1: Update docs/index.html**

Changes:
- Remove "funded by bitcoin lightning" references (deferred)
- Update hero text: emphasize the collaborative AI building experience
- Update the beats: parallel agents, screenshots, live deploys
- Keep the visual design (dark theme, JetBrains Mono, orange accents)
- Replace Discord invite link placeholder (operator will set the real one)
- Update footer: remove ppq.ai link, keep source + nixos

- [ ] **Step 2: Commit**

```bash
git -c commit.gpgsign=false add docs/index.html
git -c commit.gpgsign=false commit -m "feat: update landing page for v2 — remove ppq.ai refs, update copy"
```

---

## Task 10: Create modules/apps Directory

**Files:**
- Create: `modules/apps/_template.nix.example`

- [ ] **Step 1: Create the apps directory with template**

```bash
mkdir -p modules/apps
```

Write `modules/apps/_template.nix.example`:

```nix
# Auto-generated by Tinker for round: {name}
# Copy this template, replace {name} and {port}, adjust ExecStart for your stack.
{ config, pkgs, lib, ... }:
{
  systemd.services."tinker-{name}" = {
    description = "Tinker app: {name}";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      WorkingDirectory = "/srv/tinker/projects/{name}";
      ExecStart = "${pkgs.nodejs}/bin/node server.js";
      Restart = "on-failure";
      RestartSec = 5;

      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [ "/srv/tinker/projects/{name}" ];
      PrivateTmp = true;
      NoNewPrivileges = true;

      MemoryMax = "256M";
      CPUQuota = "50%";

      Environment = [
        "PORT={port}"
        "NODE_ENV=production"
      ];
    };
  };

  services.caddy.virtualHosts."{name}.tinker.builders" = {
    extraConfig = ''
      reverse_proxy localhost:{port}
    '';
  };
}
```

- [ ] **Step 2: Commit**

```bash
git -c commit.gpgsign=false add modules/apps/
git -c commit.gpgsign=false commit -m "feat: add modules/apps directory with NixOS app template"
```

---

## Task 11: Final Verification

- [ ] **Step 1: Run nix flake check**

```bash
nix flake check 2>&1
```

Expected: passes (may warn about missing hardware config on dev machine, that's fine).

- [ ] **Step 2: Verify flake evaluates**

```bash
nix eval .#nixosConfigurations.tinker.config.networking.hostName 2>&1
```

Expected: `"tinker"`

```bash
nix eval .#nixosConfigurations.tinker.config.services.caddy.enable 2>&1
```

Expected: `true`

- [ ] **Step 3: Verify git is clean**

```bash
git status
git log --oneline -10
```

Expected: clean working tree, ~9 commits from this implementation.

- [ ] **Step 4: Push to GitHub**

```bash
git push origin main
```

---

## Post-Implementation (Human Tasks)

These require secrets or manual steps that agents can't do:

### A. Generate SSH Key Pair
```bash
ssh-keygen -t ed25519 -f keys/deploy -C tinker-deploy -N ""
```

### B. Provision VPS
```bash
export HCLOUD_TOKEN=$(cat infra/hetzner.env | grep HCLOUD_TOKEN | cut -d= -f2)
nix develop -c bash -c "bash scripts/provision.sh ash"
```

### C. Deploy
```bash
export TINKER_VPS_IP=<new-ip>
nix develop -c bash -c "bash scripts/deploy.sh"
```

### D. Create Secrets on VPS
```bash
ssh -i keys/deploy root@$TINKER_VPS_IP "mkdir -p /run/secrets && cat > /run/secrets/tinker.env << 'EOF'
ANTHROPIC_API_KEY=sk-ant-...
DISCORD_BOT_TOKEN=MTIz...
EOF
chmod 600 /run/secrets/tinker.env"
```

### E. Discord Setup
1. Create new Discord application at discord.com/developers
2. Bot tab: enable all privileged intents, copy token
3. OAuth2: generate invite with Administrator permission
4. Create Discord server, add bot
5. Create 3 channels: #welcome (read-only), #build, #showcase (read-only)
6. Write #welcome pinned message

### F. Configure Bot Token on VPS
```bash
ssh -i keys/deploy tinker@$TINKER_VPS_IP
# In tmux:
claude
# Then in Claude Code: /discord:configure <bot-token>
# Exit, then launch keeper with both #build and #showcase channel IDs:
launch-agent keeper:tinker <BUILD_CHANNEL_ID> <SHOWCASE_CHANNEL_ID>
```

### G. End-to-End Test
- Type `!start` in #build
- Pitch an idea, go through the full round
- Verify: app deploys, screenshots post, !wrap works
