# Lane Prompts

Launch these in separate tmux panes. All agents work in the project directory:
`~/.superset/projects/open-builder`

---

## Lane 1: Infrastructure

```
You are building the NixOS infrastructure for open-builder, a Discord bot
powered by OpenClaw and funded by ppq.ai Bitcoin Lightning payments.

Read these files first:
- CLAUDE.md (architecture overview)
- openclaw-nix.md (the NixOS module reference)
- STATE.md (decisions and ppq.ai API details)
- PROCESS.md (your scope and coordination rules)

Your scope: flake.nix, configuration.nix, modules/open-builder.nix, and
deploy-rs configuration. Do NOT touch documents/, scripts/, skills/, or config/.

Build these files:

1. **flake.nix**
   - Inputs: nixpkgs (unstable), openclaw-nix (github:Scout-DJ/openclaw-nix),
     deploy-rs (github:serokell/deploy-rs)
   - Output: a single NixOS system configuration
   - Include the openclaw overlay
   - Include deploy-rs checks

2. **configuration.nix**
   - Enable openclaw with: discord plugin, exec tool in allowlist,
     domain placeholder "agents.example.com"
   - Model provider: custom ppq.ai config via extraGatewayConfig
   - Secret paths: /run/secrets/ppq-api-key, /run/secrets/discord-token
   - Standard NixOS: openssh, firewall (22, 80, 443), locale, timezone
   - WORKAROUND for openclaw-nix gaps: the module doesn't wire discord.tokenFile
     or modelApiKeyFile to the process. Use extraGatewayConfig and/or
     systemd environment overrides to inject these manually.

3. **modules/open-builder.nix**
   - Activation script that copies documents/, skills/, scripts/ to
     /home/openclaw/projects/open-builder/ on deploy
   - Make scripts executable
   - Set ownership to openclaw user

4. **deploy-rs config** (in flake.nix outputs)
   - Single node named "open-builder"
   - Placeholder hostname: "open-builder.example.com"
   - SSH user: root
   - Profile: system
   - Auto-rollback and magic-rollback enabled

Generate an ED25519 SSH keypair for deploy at keys/deploy and add keys/ to
.gitignore. The public key should be referenced in configuration.nix under
users.root.openssh.authorizedKeys.

Acceptance criteria:
- `nix flake check` passes (or would pass with --impure if needed)
- The flake structure is valid and all inputs resolve
- deploy-rs config is syntactically correct
- openclaw-nix gaps have documented workarounds
```

---

## Lane 2: Agent Documents

```
You are writing the system prompt and personality for open-builder, a Discord
bot that runs collaborative build sessions with groups of people.

Read these files first:
- CLAUDE.md (architecture, phases, how the bot works)
- PROCESS.md (your scope and coordination rules)
- STATE.md (decisions)

Your scope: documents/AGENTS.md, documents/SOUL.md, documents/TOOLS.md.
Do NOT touch any other files.

Build these files:

1. **documents/AGENTS.md** — The system prompt. This is injected into every
   OpenClaw agent session. It must define:

   Phase state machine:
   - IDLE: default. Respond to questions, banter, !topup, !balance
   - IDEATION (!start): collect ideas from everyone for ~2 minutes
   - SYNTHESIS (!close-ideas): combine ideas into 3 proposals, post them,
     collect votes via emoji reactions
   - BUILD (!pick N or auto after vote): scaffold the winning project,
     post progress in real time
   - ITERATE: collect feedback in ~90s windows, build what the group wants
   - WRAP (!wrap): summarize what was built and who contributed

   Bang commands (!start, !close-ideas, !pick, !wrap, !topup, !balance,
   !status, !help) with clear trigger conditions and responses.

   Rules:
   - Never run destructive commands outside /home/openclaw/projects/
   - Respect Discord 2000 char message limit (chunk if needed)
   - Warn proactively when ppq.ai credits are low
   - Track who contributed ideas (by Discord username)
   - Keep phase transitions explicit — announce them
   - During BUILD/ITERATE, show code in fenced blocks
   - During SYNTHESIS, present proposals as numbered options

2. **documents/SOUL.md** — The personality. Hacker energy:
   - Terse, technical, lowercase preferred
   - Irreverent but not rude
   - Like a sharp dev who happens to be a bot
   - Gets excited about clever solutions
   - Knows when to be serious (errors, money, security)
   - No corporate speak, no emojis unless ironic
   - Treats the group like collaborators, not users

3. **documents/TOOLS.md** — Tool reference for the agent:
   - exec: shell access within systemd sandbox, working dir /home/openclaw/projects/
   - read/write/edit: file operations within sandbox
   - web_search/web_fetch: for looking up docs during builds
   - message: for sending Discord messages
   - Document the topup.sh and check-balance.sh scripts at
     /home/openclaw/scripts/ (the agent calls these via exec)

Acceptance criteria:
- AGENTS.md covers all 6 phases with clear transitions
- All bang commands are documented with trigger → action → response
- SOUL.md establishes a distinct, consistent voice
- TOOLS.md lists every tool the agent can use with usage notes
```

---

## Lane 3: Scripts + Skills

```
You are building the operational scripts and skills for open-builder, a Discord
bot that uses ppq.ai for LLM inference funded by Bitcoin Lightning.

Read these files first:
- CLAUDE.md (architecture overview)
- STATE.md (ppq.ai API reference, decisions)
- PROCESS.md (your scope and coordination rules)

Your scope: scripts/, skills/, config/. Do NOT touch flake.nix, configuration.nix,
modules/, or documents/.

Build these files:

1. **scripts/check-balance.sh**
   - Calls: POST https://api.ppq.ai/credits/balance
   - Auth: Bearer token from /run/secrets/ppq-api-key
   - Output: formatted balance (USD amount and/or sats equivalent)
   - Exit 1 on failure with error message
   - Must work standalone (no dependencies beyond curl and jq)

2. **scripts/topup.sh**
   - Calls: POST https://api.ppq.ai/topup/create/btc-lightning
   - Auth: Bearer token from /run/secrets/ppq-api-key
   - Args: amount in sats (default: 10000) and currency (default: SATS)
   - Output: the Lightning invoice (payment request string) and invoice ID
   - Then poll: GET https://api.ppq.ai/topup/status/{invoice_id}
   - Report when paid or expired (15 min timeout for lightning)
   - Exit 1 on failure

3. **scripts/deploy.sh**
   - Runs deploy-rs: `deploy .#open-builder`
   - After successful deploy, SSH to host and:
     - Verify openclaw service is running
     - Print the auth token path
     - Print balance check result
   - Placeholder host: open-builder.example.com

4. **skills/topup/SKILL.md**
   - OpenClaw skill format with YAML frontmatter:
     name, description, required tools (exec, message)
   - Instructions for the agent to:
     - Run check-balance.sh and report current balance
     - If user requests topup: run topup.sh with requested amount
     - Post the Lightning invoice as a message in Discord
     - Poll for payment confirmation
     - Report new balance after payment

5. **config/openclaw.json**
   - Reference config template showing ppq.ai as custom provider
   - Format: { providers: [{ name, baseUrl, apiKey placeholder,
     api: "openai", models: [{ id, name, contextWindow, maxTokens }] }] }
   - Model: claude-3.5-sonnet (or whatever ppq.ai lists for Claude Sonnet)
   - Note: this is a reference template, not deployed directly.
     The NixOS module generates the actual gateway config.

Acceptance criteria:
- Scripts are shellcheck-clean (bash, set -euo pipefail)
- Scripts work standalone with only curl and jq as dependencies
- Topup skill follows OpenClaw skill format
- Config template has valid JSON
- All secret paths point to /run/secrets/ (no hardcoded keys)
```
