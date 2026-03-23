{ config, pkgs, lib, ... }:

{
  services.caddy = {
    enable = true;

    # Landing page
    virtualHosts."tinker.builders" = {
      extraConfig = ''
        root * /srv/tinker/docs
        file_server
      '';
    };
  };

  # Ensure docs directory exists
  systemd.tmpfiles.rules = [
    "d /srv/tinker/docs 0755 tinker tinker -"
  ];

  # Firewall for HTTP/HTTPS
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
