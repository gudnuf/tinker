# Built by Tinker
{ config, pkgs, lib, ... }:
{
  systemd.services."tinker-socratic-prep" = {
    description = "Tinker app: socratic-prep";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "tinker";
      Group = "users";
      WorkingDirectory = "/srv/tinker/projects/socratic-prep";
      ExecStart = "${pkgs.nodejs}/bin/node server.js";
      Restart = "on-failure";
      RestartSec = 5;
      Environment = [ "PORT=10001" "NODE_ENV=production" ];
    };
  };

  services.caddy.virtualHosts."socratic-prep.tinker.builders" = {
    extraConfig = ''
      reverse_proxy localhost:10001
    '';
  };
}
