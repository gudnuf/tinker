{ config, pkgs, lib, ... }:

{
  # --- Dynamic App Module Imports ---
  # Auto-import all .nix files from modules/apps/ — the bot drops app modules
  # here and runs nixos-rebuild to deploy them.
  imports = let
    appsDir = ./modules/apps;
  in
    if builtins.pathExists appsDir then
      map (f: appsDir + "/${f}")
        (builtins.attrNames
          (lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".nix" n)
            (builtins.readDir appsDir)))
    else [];

  # --- OpenClaw Service ---
  services.openclaw = {
    enable = true;
    domain = "tinker.builders";

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
        provider = "openai";
        api = "openai-completions";
        baseUrl = "https://api.ppq.ai";
        models = [
          {
            id = "openai/claude-sonnet-4.6";
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
  systemd.services.openclaw-gateway = {
    serviceConfig = {
      EnvironmentFile = [ "/run/secrets/openclaw.env" ];
      # openclaw calls os.networkInterfaces() at startup which requires AF_NETLINK
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];
      # openclaw-nix passes --config but current openclaw doesn't support it.
      # Override ExecStart: clear the module's line, set our own without --config.
      ExecStart = [
        ""  # clear upstream ExecStart
        "${config.services.openclaw.package}/bin/openclaw gateway run --allow-unconfigured --port 3000 --bind custom --auth token"
      ];
      # Disable sandbox: openclaw crashes under hardened systemd settings.
      # TODO: re-tighten once gateway is stable.
      ProtectSystem = lib.mkForce false;
      ProtectHome = lib.mkForce false;
      PrivateTmp = lib.mkForce false;
      PrivateDevices = lib.mkForce false;
      RestrictNamespaces = lib.mkForce false;
      CapabilityBoundingSet = lib.mkForce [ "" ];
      SystemCallFilter = lib.mkForce [ "" ];
    };
    # Set HOME so openclaw finds $HOME/.openclaw/openclaw.json
    environment.HOME = "/var/lib/openclaw";
    # Seed openclaw config before gateway starts (only if missing)
    preStart = lib.mkAfter ''
      mkdir -p /var/lib/openclaw/.openclaw
      if [ ! -f /var/lib/openclaw/.openclaw/openclaw.json ]; then
        cat > /var/lib/openclaw/.openclaw/openclaw.json << 'OCEOF'
      {
        "gateway": {
          "mode": "local",
          "port": 3000,
          "bind": "custom",
          "auth": { "mode": "token" }
        },
        "models": {
          "default": "openai/claude-sonnet-4.6",
          "providers": {
            "openai": {
              "api": "openai-completions",
              "baseUrl": "https://api.ppq.ai",
              "models": [{
                "id": "openai/claude-sonnet-4.6",
                "name": "Claude Sonnet 4.6",
                "contextWindow": 200000,
                "maxTokens": 16384
              }]
            }
          }
        },
        "agent": {
          "model": "openai/claude-sonnet-4.6"
        },
        "channels": {
          "discord": { "enabled": true }
        },
        "plugins": {
          "entries": {
            "discord": { "enabled": true }
          }
        },
        "groupPolicy": "open"
      }
      OCEOF
        chmod 600 /var/lib/openclaw/.openclaw/openclaw.json
      fi
    '';
  };

  # --- Caddy: on-demand TLS for app subdomains ---
  # Apps deploy to {name}.tinker.builders. Caddy auto-provisions TLS certs
  # for new subdomains via Let's Encrypt on-demand TLS.
  services.caddy.globalConfig = lib.mkAfter ''
    on_demand_tls {
      interval 2m
      burst 5
    }
  '';

  # --- Landing Page (Caddy static files) ---
  # Override the openclaw-nix reverse proxy virtualHost — the gateway
  # only needs local access (Discord connects outbound, subagent calls
  # are localhost). Serve the landing page on the main domain instead.
  services.caddy.virtualHosts."tinker.builders" = lib.mkForce {
    extraConfig = ''
      root * /var/www/tinker
      file_server
    '';
  };

  systemd.tmpfiles.rules = [
    "d /var/www/tinker 0755 root root -"
  ];

  # --- Networking ---
  networking = {
    hostName = "tinker";
    useNetworkd = true;
    firewall = {
      enable = true;
      # openclaw-nix opens 80/443 via openFirewall but does NOT open SSH
      allowedTCPPorts = [ 22 80 443 ];
    };
  };

  # DHCP on all physical ethernet interfaces (Hetzner Cloud uses eth0)
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

  # --- Sudo: allow openclaw to run nixos-rebuild ---
  # The bot writes NixOS app modules and runs nixos-rebuild to deploy them.
  # Only nixos-rebuild is allowed — nothing else.
  security.sudo.extraRules = [{
    users = [ "openclaw" ];
    commands = [{
      command = "/run/current-system/sw/bin/nixos-rebuild";
      options = [ "NOPASSWD" ];
    }];
  }];

  # --- Locale & Timezone ---
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # --- Boot & Filesystem ---
  # Disk layout managed by disko (see disko-config.nix).
  # GRUB with BIOS boot partition — reliable on Hetzner Cloud where
  # UEFI NVRAM resets on reboot (systemd-boot doesn't persist in boot order).
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "/dev/sda";
  };

  # Hetzner Cloud runs KVM/QEMU — virtio modules needed in initrd
  boot.initrd.availableKernelModules = [
    "virtio_pci" "virtio_blk" "virtio_scsi" "virtio_net" "ahci"
  ];

  # --- System ---
  system.stateVersion = "24.11";
}
