{ config, pkgs, lib, ... }:

{
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
          "providers": {
            "ppq": {
              "baseUrl": "https://api.ppq.ai",
              "models": [{
                "id": "claude-sonnet-4.6",
                "name": "Claude Sonnet 4.6",
                "contextWindow": 200000,
                "maxTokens": 16384
              }]
            }
          }
        },
        "channels": {
          "discord": { "enabled": true }
        },
        "plugins": {
          "entries": {
            "discord": { "enabled": true }
          }
        }
      }
      OCEOF
        chmod 600 /var/lib/openclaw/.openclaw/openclaw.json
      fi
    '';
  };

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
