# OpenClaw on NixOS — Deployment Guide

Source: [github.com/Scout-DJ/openclaw-nix](https://github.com/Scout-DJ/openclaw-nix)

## What This Is

`openclaw-nix` is a NixOS module that deploys OpenClaw (an AI agent infrastructure platform) with hardened security defaults. The upstream project binds to `0.0.0.0` with no auth and unrestricted tool execution out of the box. This module wraps it with localhost binding, mandatory auth, tool allowlists, Caddy TLS, systemd sandboxing, and firewall rules — all declarative in Nix.

## Project Structure

```
flake.nix                  # Package build, overlay, NixOS module export, apps
flake.lock                 # Pinned nixpkgs-unstable
modules/openclaw.nix       # The NixOS module (all config options + service definitions)
scripts/quick-setup.sh     # Interactive bash wizard that generates a deployment config
examples/configuration.nix # Reference consumer config
package-lock.json          # npm dependency lock for reproducible buildNpmPackage
```

## How to Consume It

### Flake Setup

Add to your flake inputs and include the module + overlay:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    openclaw.url = "github:Scout-DJ/openclaw-nix";
  };

  outputs = { self, nixpkgs, openclaw }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";  # or aarch64-linux
      modules = [
        openclaw.nixosModules.default
        { nixpkgs.overlays = [ openclaw.overlays.default ]; }
        ./configuration.nix
      ];
    };
  };
}
```

The overlay makes `pkgs.openclaw` available. Without it, the module falls back to building from npm inline (requires `--impure` since it needs network access in the sandbox).

### Minimal Configuration

```nix
services.openclaw = {
  enable = true;
  domain = "agents.example.com";
};
```

This gives you: gateway on localhost:3000, Caddy reverse proxy with auto TLS, auth token auto-generated, safe tool allowlist, systemd hardening, firewall (80/443), fail2ban.

---

## Full Option Reference

All options live under `services.openclaw`.

### Core

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | `bool` | `false` | Master switch. Gates all service creation. |
| `package` | `package` | `pkgs.openclaw` | The OpenClaw derivation. Uses overlay if available, otherwise builds from npm. Set this to use a custom build. |
| `version` | `str` | `"2026.2.6-3"` | Only used by the npm fallback package builder. Ignored when the overlay is applied or `package` is set explicitly. |

### Network

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `domain` | `str` | `""` | **Key option.** When non-empty: enables Caddy, creates a virtualHost with reverse_proxy to the gateway, adds TLS via Let's Encrypt, sets security headers (HSTS, X-Frame-Options DENY, nosniff, strict referrer). When empty: no Caddy, no TLS — gateway is localhost-only with no public exposure. |
| `gatewayPort` | `port` | `3000` | Local port the gateway binds to. Flows into: gateway config JSON, `OPENCLAW_PORT` env var, and Caddy reverse_proxy target. |
| `openFirewall` | `bool` | `true` | Opens TCP 80 and 443. Note: does NOT open SSH/22 despite what the README says. |

### Auth & State

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `authTokenFile` | `path` | `/var/lib/openclaw/auth-token` | Path to the gateway auth token file. If the file doesn't exist at service start, `preStart` generates one via `openssl rand -hex 32` (64-char hex token). Written into the gateway config JSON at `auth.tokenFile`. |
| `dataDir` | `path` | `/var/lib/openclaw` | State directory. Used as: systemd `WorkingDirectory`, `ReadWritePaths`, tmpfiles target, and the `openclaw` user's home. |

### Tool Security

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `toolSecurity` | `enum ["deny" "allowlist"]` | `"allowlist"` | `"deny"` blocks all tool execution. `"allowlist"` permits only tools in `toolAllowlist`. `"full"` is **excluded from the enum** — Nix evaluation will fail if you try to set it. This is a type-level safety guarantee. |
| `toolAllowlist` | `listOf str` | `["read" "write" "edit" "web_search" "web_fetch" "message" "tts"]` | Tools agents are allowed to use. Only applies when `toolSecurity = "allowlist"`. Known dangerous tools to add with caution: `"exec"` (shell access), `"browser"` (browser automation), `"nodes"`. |

### Model Provider

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `modelProvider` | `str` | `"anthropic"` | AI model provider name. Set as env `OPENCLAW_MODEL_PROVIDER` on the service, but **only when `modelApiKeyFile` is non-null**. Not written to the gateway config JSON. |
| `modelApiKeyFile` | `nullOr path` | `null` | Path to file containing the model API key. **Known gap:** the file path itself is never passed to the process — it only gates whether `modelProvider` is set as an env var. The actual key loading mechanism is unclear. |

### Plugins

Both plugins follow the same pattern: `enable` + `tokenFile`. When both are set, an env var flag is set on the service.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `telegram.enable` | `bool` | `false` | Enable Telegram bot plugin. |
| `telegram.tokenFile` | `nullOr path` | `null` | Path to Telegram bot token. **Known gap:** the path is never passed to the process — only `OPENCLAW_TELEGRAM_ENABLED=true` is set as an env var. |
| `discord.enable` | `bool` | `false` | Enable Discord bot plugin. |
| `discord.tokenFile` | `nullOr path` | `null` | Same pattern as telegram. |

### Auto-Update

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `autoUpdate.enable` | `bool` | `false` | Creates a systemd oneshot + timer that runs `nixos-rebuild switch --flake /etc/nixos#$(hostname) --upgrade`. |
| `autoUpdate.schedule` | `str` | `"weekly"` | systemd `OnCalendar` expression. Timer has `Persistent = true` (fires after missed schedule) and `RandomizedDelaySec = 1h` (jitter). |

### Escape Hatch

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `extraGatewayConfig` | `attrs` | `{}` | Shallow-merged (`//`) onto the generated gateway config JSON at the top level. Can override `host`, `port`, `auth`, `tools`, or inject arbitrary keys. This is the only way to change hardcoded values like `host = "127.0.0.1"` or `auth.enabled = true`. |

---

## Generated Gateway Config

The module produces a JSON file passed to the process via `--config`. Structure:

```json
{
  "host": "127.0.0.1",
  "port": 3000,
  "auth": {
    "enabled": true,
    "tokenFile": "/var/lib/openclaw/auth-token"
  },
  "tools": {
    "security": "allowlist",
    "allowlist": ["read", "write", "edit", "web_search", "web_fetch", "message", "tts"]
  }
}
```

`host` and `auth.enabled` are hardcoded — override via `extraGatewayConfig` if needed.

## Environment Variables

Always set on the gateway service:

| Variable | Value |
|----------|-------|
| `OPENCLAW_HOST` | `127.0.0.1` |
| `OPENCLAW_PORT` | `<gatewayPort>` |
| `NODE_ENV` | `production` |

Conditionally set:

| Variable | Condition |
|----------|-----------|
| `OPENCLAW_MODEL_PROVIDER` | `modelApiKeyFile != null` |
| `OPENCLAW_TELEGRAM_ENABLED` | `telegram.enable && telegram.tokenFile != null` |
| `OPENCLAW_DISCORD_ENABLED` | `discord.enable && discord.tokenFile != null` |

## Implicit Side Effects

These are **not configurable** — they fire unconditionally when `enable = true`:

- **System user/group** `openclaw` is created (system user, home = `dataDir`)
- **Fail2ban** is enabled globally with `maxretry=5`, `bantime=1h`, incremental bans — this affects the whole system, not just OpenClaw
- **Package** is added to `environment.systemPackages`
- **tmpfiles rule** creates `dataDir` as `0750 openclaw:openclaw`
- **systemd hardening** on the gateway: NoNewPrivileges, PrivateTmp, ProtectSystem=strict, capability dropping, syscall filtering, UMask 0077 (full list in module lines 204-234)

## systemd Hardening (Non-Configurable)

The gateway service runs with these protections:

```
User/Group           = openclaw (dedicated, not root)
NoNewPrivileges      = true
PrivateTmp           = true
PrivateDevices       = true
ProtectSystem        = strict (read-only fs except StateDirectory)
ProtectHome          = true
ProtectKernel*       = true (tunables, modules, logs)
ProtectControlGroups = true
ProtectClock         = true
ProtectHostname      = true
RestrictNamespaces   = true
RestrictRealtime     = true
RestrictSUIDSGID     = true
LockPersonality      = true
MemoryDenyWriteExecute = false  (Node.js needs JIT)
CapabilityBoundingSet  = ""     (all dropped)
UMask                = 0077
SystemCallFilter     = @system-service ~@privileged ~@resources
RestrictAddressFamilies = AF_INET AF_INET6 AF_UNIX
ReadWritePaths       = <dataDir>
```

---

## Example Configurations

### Minimal (localhost only, no public access)

```nix
services.openclaw = {
  enable = true;
  # No domain = no Caddy, no TLS. Gateway on localhost:3000 only.
};
```

### Production with Anthropic + Telegram

```nix
services.openclaw = {
  enable = true;
  domain = "agents.mycompany.com";

  modelProvider = "anthropic";
  modelApiKeyFile = "/run/secrets/anthropic-api-key";  # agenix/sops-nix

  telegram = {
    enable = true;
    tokenFile = "/run/secrets/telegram-bot-token";
  };

  autoUpdate = {
    enable = true;
    schedule = "Sun *-*-* 03:00:00";
  };
};
```

### With exec tool enabled

```nix
services.openclaw = {
  enable = true;
  domain = "agents.example.com";

  toolAllowlist = [
    "read" "write" "edit"
    "web_search" "web_fetch"
    "message" "tts"
    "exec"     # shell access within the systemd sandbox
  ];
};
```

### Custom gateway port + extra config

```nix
services.openclaw = {
  enable = true;
  domain = "agents.example.com";
  gatewayPort = 8080;

  extraGatewayConfig = {
    rateLimit = {
      enabled = true;
      maxRequests = 100;
      windowSeconds = 60;
    };
  };
};
```

### Lockdown mode (no tools at all)

```nix
services.openclaw = {
  enable = true;
  domain = "agents.example.com";
  toolSecurity = "deny";
};
```

---

## Quick Setup (Interactive)

For fast bootstrapping without writing Nix manually:

```bash
nix run github:Scout-DJ/openclaw-nix#quick-setup
```

Prompts for: domain, model provider, API key, Telegram/Discord tokens, exec tool opt-in. Generates a `flake.nix`, `configuration.nix`, and `secrets/` directory.

The generated config does **not** include the overlay, so it uses the npm fallback package path.

## Post-Deploy

```bash
# Deploy
sudo nixos-rebuild switch --flake .#myhost

# Retrieve the auto-generated auth token
sudo cat /var/lib/openclaw/auth-token

# Check service status
systemctl status openclaw-gateway

# View logs
journalctl -u openclaw-gateway -f
```

---

## Known Gaps and Open Questions

These are things the module defines options for but doesn't fully wire up. They likely work via OpenClaw's own env var or file discovery, but the module's plumbing is incomplete:

1. **`modelApiKeyFile` is never passed to the process.** The path is accepted as an option but never appears in the gateway config JSON, env vars, or `EnvironmentFile`. It only gates whether `OPENCLAW_MODEL_PROVIDER` is set. OpenClaw likely reads the key via its own file discovery or expects an env var like `ANTHROPIC_API_KEY` that the module doesn't set.

2. **`telegram.tokenFile` and `discord.tokenFile` are never passed to the process.** Same issue — only the boolean enable flags are set as env vars. The actual token file paths aren't wired.

3. **Fail2ban is forced globally.** Enabling OpenClaw unconditionally sets fail2ban config system-wide. If you already have fail2ban configured, these settings may conflict.

4. **Caddy is additive.** Uses the NixOS `services.caddy` option, which merges with existing Caddy config. Could conflict if another module manages Caddy.

5. **Auto-update assumes `/etc/nixos` flake path.** The update service runs `nixos-rebuild switch --flake /etc/nixos#$(hostname)` — this won't work if your flake lives elsewhere.

6. **Firewall doesn't open SSH.** The README says ports 443 and 22 are opened, but the module only opens 80 and 443. SSH must be opened separately.

7. **The npm fallback package requires `--impure`.** The inline `mkDerivation` at lines 29-49 of the module calls `npm install --global` which needs network access, incompatible with the Nix sandbox.

## Where to Learn More

- **The module itself:** `modules/openclaw.nix` is 317 lines and contains everything — read it directly
- **OpenClaw upstream:** [github.com/openclaw/openclaw](https://github.com/openclaw/openclaw) — for understanding what env vars and config keys the gateway actually supports
- **The package build:** `flake.nix` lines 24-98 show how OpenClaw is fetched from npm and wrapped as a Nix derivation
- **systemd hardening reference:** [systemd.exec(5)](https://www.freedesktop.org/software/systemd/man/systemd.exec.html) for understanding each sandbox directive
- **Caddy config:** [caddyserver.com/docs](https://caddyserver.com/docs/) for understanding the reverse proxy and header directives
- **Secrets management:** the README recommends [agenix](https://github.com/ryantm/agenix) or [sops-nix](https://github.com/Mic92/sops-nix) for production secret handling
