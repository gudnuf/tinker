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
