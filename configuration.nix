{ config, pkgs, lib, ... }:

{
  # --- OpenClaw Service ---
  services.openclaw = {
    enable = true;
    domain = "agents.example.com"; # TODO: replace with actual domain

    # Enable Discord plugin
    discord = {
      enable = true;
      tokenFile = "/run/secrets/discord-token"; # accepted but NOT wired (see workaround below)
    };

    # Model provider: ppq.ai is OpenAI-compatible
    modelProvider = "openai";
    modelApiKeyFile = "/run/secrets/ppq-api-key"; # accepted but NOT wired (see workaround below)

    # Tool allowlist: default set + exec for shell access within the sandbox
    toolAllowlist = [
      "read" "write" "edit"
      "web_search" "web_fetch"
      "message" "tts"
      "exec"
    ];

    # Inject ppq.ai custom provider config into the gateway JSON.
    # The apiKey is NOT set here (Nix store is world-readable).
    # It's injected at runtime via EnvironmentFile (see workaround below).
    extraGatewayConfig = {
      models = {
        provider = "ppq";
        type = "openai";
        baseUrl = "https://api.ppq.ai";
        models = [
          {
            id = "claude-sonnet-4.6";
            name = "Claude Sonnet 4.6";
            contextWindow = 200000;
            maxTokens = 16384;
          }
        ];
      };
    };
  };

  # =========================================================================
  # WORKAROUND: openclaw-nix known gaps
  # =========================================================================
  #
  # The openclaw-nix module has wiring gaps where option values are accepted
  # but never passed to the gateway process:
  #
  # 1. modelApiKeyFile — only gates OPENCLAW_MODEL_PROVIDER env var, never
  #    passes the actual API key file path to the process.
  #
  # 2. discord.tokenFile — only sets OPENCLAW_DISCORD_ENABLED=true, never
  #    passes the token file path to the process.
  #
  # FIX: Inject secrets via systemd EnvironmentFile. On the VPS, create
  # /run/secrets/openclaw.env containing:
  #
  #   OPENAI_API_KEY=<your ppq.ai API key>
  #   DISCORD_BOT_TOKEN=<your Discord bot token>
  #
  # OpenClaw reads OPENAI_API_KEY for OpenAI-compatible providers and
  # DISCORD_BOT_TOKEN for the Discord plugin. If it expects different
  # variable names, check `openclaw --help` or upstream source and update.
  #
  # This file must be:
  #   - Created manually on the VPS before first deploy
  #   - Owned by root:root, mode 0600
  #   - NOT stored in the repo or Nix store
  # =========================================================================
  systemd.services.openclaw-gateway.serviceConfig.EnvironmentFile = [
    "/run/secrets/openclaw.env"
  ];

  # --- Networking ---
  networking = {
    hostName = "open-builder";
    firewall = {
      enable = true;
      # openclaw-nix opens 80/443 via openFirewall but does NOT open SSH
      allowedTCPPorts = [ 22 80 443 ];
    };
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

  # --- Locale & Timezone ---
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # --- Boot & Filesystem ---
  # Standard VPS defaults. Replace with actual hardware-configuration.nix
  # generated on the VPS via `nixos-generate-config`.
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda"; # TODO: adjust to actual VPS disk
  };

  fileSystems."/" = {
    device = "/dev/vda1"; # TODO: adjust to actual VPS partition
    fsType = "ext4";
  };

  # --- System ---
  system.stateVersion = "24.11";
}
