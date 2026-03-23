{ config, pkgs, lib, ... }:

{
  services.caddy = {
    enable = true;

    # Landing page (served from the NixOS config repo)
    virtualHosts."tinker.builders" = {
      extraConfig = ''
        root * /etc/nixos/docs
        file_server
      '';
    };
  };

  # Firewall for HTTP/HTTPS
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
