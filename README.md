# tinker

a discord bot that builds software with groups of people.
funded by bitcoin lightning. deployed on nixos.

anyone can run their own instance.

## what you need

- a hetzner cloud account (or any VPS you can SSH into)
- a discord bot token
- a ppq.ai API key (for LLM inference, paid with bitcoin lightning)
- nix installed on your local machine

## quickstart

### 1. clone and generate deploy keys

```bash
git clone https://github.com/gudnuf/tinker.git
cd tinker
ssh-keygen -t ed25519 -f keys/deploy -N "" -C "tinker-deploy"
```

### 2. provision a VPS

get a hetzner API token from [console.hetzner.cloud](https://console.hetzner.cloud),
then:

```bash
echo 'HCLOUD_TOKEN=your-token' > infra/hetzner.env
source infra/hetzner.env
bash scripts/provision.sh [location]
```

location defaults to nbg1 (Nuremberg). use `ash` for Ashburn, VA if your
model provider geo-blocks EU IPs.

this creates a VPS and installs NixOS via nixos-anywhere. takes a few minutes.
note the IP address it prints.

if you're not using hetzner, provision any x86_64 linux box and install nixos
however you like. just make sure `keys/deploy.pub` is in root's authorized_keys.

### 3. create secrets on the VPS

```bash
ssh -i keys/deploy root@YOUR_IP "mkdir -p /run/secrets && cat > /run/secrets/openclaw.env << 'EOF'
OPENAI_API_KEY=your-ppq-api-key
DISCORD_BOT_TOKEN=your-discord-bot-token
EOF
chmod 600 /run/secrets/openclaw.env"
```

**ppq.ai key:** sign up at [ppq.ai](https://ppq.ai) and grab your API key.
fund it with bitcoin lightning — no credit card needed.

**discord bot token:** create an app at
[discord.com/developers](https://discord.com/developers/applications),
add a bot, copy the token. enable Message Content Intent. invite the bot
to your server with Send Messages + Read Message History + Add Reactions.

### 4. deploy

```bash
bash scripts/deploy.sh YOUR_IP
```

this rsyncs the NixOS config to the VPS and runs `nixos-rebuild switch`
remotely. after deploy, it verifies the openclaw service is running.

### 5. talk to it

go to your discord server. the bot should be online. type `!help` to see
what it can do.

```
!start        — begin a round (10 min plan → build → deploy)
!wrap          — wrap up: summary, showcase, back to idle

!topup [amt]  — generate a lightning invoice to add credits
!balance      — check ppq.ai credit balance
!status       — current phase, project, balance
!help         — list commands
```

## how it works

```
discord channel
    |
openclaw gateway (nixos systemd service)
    |
ppq.ai (openai-compatible proxy, pay-per-query via lightning)
```

the bot runs in phases:

```
IDLE ──!start──> PLAN (10 min, auto-advancing)
                   ├── PITCH     (0:00 - 4:00)  — everyone pitches ideas
                   ├── SYNTHESIZE (4:00 - 6:00)  — ideas become 3 proposals
                   ├── VOTE      (6:00 - 8:00)  — group votes
                   └── SPEC      (8:00 - 10:00) — bot writes build plan
              ──auto──> FUND     — cost estimate + balance gate
              ──auto──> BUILD    — subagent execution, step by step
              ──auto──> DEPLOY   — write NixOS module, rebuild, go live
              ──auto──> ITERATE  — feedback loops, redeploy
              ──!wrap──> WRAP    — summary, showcase, return to IDLE
```

anyone in the channel can steer the session. the bot tracks who contributed
what. apps deploy to `{name}.tinker.builders` with automatic TLS.

a credit bot sidecar handles `!topup` and `!balance` directly without
burning LLM tokens.

## project structure

```
tinker/
├── flake.nix                  # nix flake — nixos config + dev shell
├── configuration.nix          # openclaw service, caddy, firewall, ssh
├── disko-config.nix           # declarative disk layout for VPS
├── modules/
│   ├── tinker.nix             # copies docs/skills/scripts to VPS on deploy
│   ├── credit-bot.nix         # credit bot sidecar (handles !topup/!balance)
│   └── apps/                  # bot drops NixOS app modules here at runtime
│       └── _template.nix.example
├── services/
│   └── credit-bot/            # Node.js credit bot source
│       ├── index.js
│       ├── package.json
│       └── package-lock.json
├── documents/
│   ├── AGENTS.md              # system prompt — phase logic, commands, rules
│   ├── SOUL.md                # personality — hacker energy
│   ├── TOOLS.md               # tool reference for the agent
│   └── ROUND-DESIGN.md        # v2 round workflow design doc
├── scripts/
│   ├── provision.sh           # create hetzner VPS + install nixos
│   ├── teardown.sh            # destroy the VPS
│   ├── deploy.sh              # rsync + remote nixos-rebuild
│   ├── check-balance.sh       # check ppq.ai credits (runs on VPS)
│   ├── topup.sh               # generate lightning invoice (runs on VPS)
│   ├── tinker-ssh             # SSH into the VPS
│   ├── tinker-logs            # tail gateway logs
│   ├── tinker-status          # quick health check
│   ├── tinker-deploy          # deploy with safety checks
│   ├── tinker-config          # read/set openclaw config
│   └── tinker-balance         # check balance via VPS
├── skills/
│   └── topup/SKILL.md         # openclaw skill for the topup flow
├── config/
│   └── openclaw.json          # reference config template
├── keys/
│   ├── deploy                 # SSH private key (gitignored)
│   └── deploy.pub             # SSH public key (committed)
├── infra/
│   └── hetzner.env.example
└── docs/
    └── index.html             # landing page (served by caddy on VPS)
```

## dev shell

```bash
nix develop
```

gives you a shell with all management tools on PATH:

| command | what it does |
|---------|-------------|
| `tinker-ssh` | SSH into the VPS (interactive or `tinker-ssh <cmd>`) |
| `tinker-logs` | tail gateway logs (`tinker-logs`, `tinker-logs 100`, `tinker-logs grep <pat>`) |
| `tinker-status` | quick health check — service state, uptime, memory, port, secrets |
| `tinker-deploy` | deploy with safety checks — warns about uncommitted changes |
| `tinker-config` | read/set openclaw config (`tinker-config`, `tinker-config set <path> <val>`, `tinker-config doctor`) |
| `tinker-balance` | check ppq.ai credit balance via VPS |

override the VPS IP with `TINKER_VPS_IP` env var.

## customization

**change the personality** — edit `documents/SOUL.md`. the bot's voice,
tone, and mannerisms are all defined there.

**change the phase logic** — edit `documents/AGENTS.md`. timing, commands,
rules, credit thresholds — all in one file.

**change the model** — edit the provider config in `configuration.nix`
(both `extraGatewayConfig` and the preStart seed). ppq.ai supports multiple
models. check what's available:
`curl -H "Authorization: Bearer $KEY" https://api.ppq.ai/v1/models`

**use a different LLM provider** — swap out the ppq.ai config in
`configuration.nix` for any openai-compatible endpoint. you lose the
lightning funding flow but everything else works.

**use a different VPS provider** — skip `provision.sh`, install nixos
however you want, point `deploy.sh` at it.

## teardown

```bash
source infra/hetzner.env
bash scripts/teardown.sh              # destroys VPS, keeps SSH key in hetzner
bash scripts/teardown.sh --delete-key # also removes SSH key from hetzner
```

## license

mit
