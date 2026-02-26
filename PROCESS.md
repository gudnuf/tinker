# open-builder — Process

How we build this project. Read this before touching anything.

## Roles

**Human (william):** Final decisions, domain knowledge (OpenClaw, ppq.ai, Discord
community context), secret provisioning, VPS setup, Discord app creation.

**Meta-agent (this session):** Coordinates lanes, drafts prompts, resolves
cross-cutting issues, maintains STATE.md.

**Lane agents:** Execute scoped work. Each gets a narrow task, clear acceptance
criteria, and boundaries on what not to touch.

## Lanes

Three parallel work streams:

### Lane 1: Infrastructure
**Scope:** flake.nix, configuration.nix, modules/open-builder.nix, deploy-rs config
**Depends on:** openclaw-nix.md (reference), ppq.ai research (for provider config)
**Produces:** A flake that builds, a deploy config that targets a placeholder host

### Lane 2: Agent Documents
**Scope:** documents/AGENTS.md, documents/SOUL.md, documents/TOOLS.md
**Depends on:** CLAUDE.md (architecture + phase descriptions)
**Produces:** Complete system prompt, personality doc, and tool reference

### Lane 3: Scripts + Skills
**Scope:** scripts/topup.sh, scripts/check-balance.sh, scripts/deploy.sh,
skills/topup/SKILL.md, config/openclaw.json
**Depends on:** ppq.ai API research, Lane 1 outputs (for deploy.sh)
**Produces:** Working scripts (modulo secrets), topup skill, reference config

## Coordination Rules

1. **Lanes don't edit each other's files.** Cross-cutting changes go through
   the meta-agent.
2. **State lives in STATE.md.** Any agent can read it. Only the meta-agent
   updates it.
3. **Secrets never go in the repo.** Use placeholder paths like
   `/run/secrets/discord-token`. Document what secrets are needed in STATE.md.
4. **Use workarounds for openclaw-nix gaps.** The module has known gaps
   (token files not wired, API key not passed). Write `extraGatewayConfig`
   overrides and manual env var injection until upstream fixes land.

## File Ownership

| File | Owner |
|------|-------|
| flake.nix | Lane 1 |
| configuration.nix | Lane 1 |
| modules/* | Lane 1 |
| documents/* | Lane 2 |
| scripts/* | Lane 3 |
| skills/* | Lane 3 |
| config/* | Lane 3 |
| CLAUDE.md | Human |
| PROCESS.md | Meta-agent |
| STATE.md | Meta-agent |

## Decisions Log

Decisions made during genesis. Don't revisit without cause.

- **deploy-rs** over plain nixos-rebuild: enables remote deployment without SSH
  shell access to run rebuild. Standard input, single node config.
- **Plain secrets** over agenix/sops-nix: simplest path. Manual file placement
  on VPS at /run/secrets/. Can migrate to agenix later.
- **Claude Sonnet** as the model: good balance for group chat synthesis.
- **Hacker energy** personality: terse, technical, lowercase. The bot is a
  sharp dev, not a corporate assistant.
- **3 lanes** for parallel work: infra, agent docs, scripts+skills.
- **Workarounds assumed needed** for openclaw-nix known gaps.
