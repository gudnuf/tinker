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
nix flake lock --update-input disko --update-input nixos-anywhere
bash scripts/provision.sh
```

this creates a VPS and installs NixOS via nixos-anywhere. takes a few minutes.
note the IP address it prints.

if you're not using hetzner, provision any x86_64 linux box and install nixos
however you like. just make sure `keys/deploy.pub` is in root's authorized_keys.

### 3. configure

replace the placeholder hostnames with your VPS IP (or domain):

```bash
# in flake.nix — deploy-rs target
sed -i '' 's/open-builder.example.com/YOUR_IP/' flake.nix

# in configuration.nix — openclaw domain
sed -i '' 's/agents.example.com/YOUR_DOMAIN/' configuration.nix
```

### 4. create secrets on the VPS

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

### 5. deploy

```bash
bash scripts/deploy.sh YOUR_IP
```

this uses deploy-rs to push the NixOS config to the VPS. after deploy,
it verifies the openclaw service is running and checks your ppq.ai balance.

### 6. talk to it

go to your discord server. the bot should be online. type `!help` to see
what it can do.

```
!start        — begin a build session
!close-ideas  — stop collecting ideas, start synthesis
!pick N       — pick proposal N to build
!wrap         — end the session, summarize what was built
!topup        — generate a lightning invoice to add credits
!balance      — check ppq.ai credit balance
!status       — current phase + balance
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

**IDLE** → **IDEATION** (everyone pitches ideas) → **SYNTHESIS** (ideas
become proposals, group votes) → **BUILD** (bot codes the winner live) →
**ITERATE** (feedback rounds) → **WRAP** (summary + credits)

anyone in the channel can steer the session. the bot tracks who
contributed what.

## project structure

```
tinker/
├── flake.nix              # nix flake — nixos config + deploy-rs
├── configuration.nix      # openclaw service, firewall, ssh
├── disko-config.nix       # declarative disk layout for VPS
├── modules/
│   └── open-builder.nix   # copies docs/skills/scripts to VPS on deploy
├── documents/
│   ├── AGENTS.md          # system prompt — phase logic, commands, rules
│   ├── SOUL.md            # personality — hacker energy
│   └── TOOLS.md           # tool reference for the agent
├── scripts/
│   ├── provision.sh       # create hetzner VPS + install nixos
│   ├── teardown.sh        # destroy the VPS
│   ├── deploy.sh          # deploy-rs wrapper + post-deploy checks
│   ├── check-balance.sh   # check ppq.ai credits
│   └── topup.sh           # generate lightning invoice for topup
├── skills/
│   └── topup/SKILL.md     # openclaw skill for the topup flow
├── config/
│   └── openclaw.json      # reference config template
├── keys/
│   ├── deploy             # SSH private key (gitignored)
│   └── deploy.pub         # SSH public key (committed)
├── infra/
│   └── hetzner.env.example
└── docs/
    └── index.html         # landing page (github pages)
```

## teardown

```bash
source infra/hetzner.env
bash scripts/teardown.sh              # destroys VPS, keeps SSH key in hetzner
bash scripts/teardown.sh --delete-key # also removes SSH key from hetzner
```

## customization

**change the personality** — edit `documents/SOUL.md`. the bot's voice,
tone, and mannerisms are all defined there.

**change the phase logic** — edit `documents/AGENTS.md`. timing, commands,
rules, credit thresholds — all in one file.

**change the model** — edit the `extraGatewayConfig` in `configuration.nix`.
ppq.ai supports multiple models. check what's available:
`curl -H "Authorization: Bearer $KEY" https://api.ppq.ai/v1/models`

**use a different LLM provider** — swap out the ppq.ai config in
`configuration.nix` for any openai-compatible endpoint. you lose the
lightning funding flow but everything else works.

**use a different VPS provider** — skip `provision.sh`, install nixos
however you want, point deploy-rs at it.

## license

mit
