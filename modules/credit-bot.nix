{ config, pkgs, lib, ... }:

let
  creditBot = pkgs.buildNpmPackage {
    pname = "tinker-credit-bot";
    version = "1.0.0";
    src = ../services/credit-bot;
    npmDepsHash = "sha256-LTLYJpnxzkDG6dVFEZeLq5Qvm5afxzHUgkH75PmmBm4=";
    dontNpmBuild = true;

    installPhase = ''
      mkdir -p $out/lib/credit-bot
      cp -r node_modules $out/lib/credit-bot/
      cp index.js $out/lib/credit-bot/
    '';
  };
in
{
  systemd.services.tinker-credit-bot = {
    description = "Tinker credit bot (topup + balance sidecar)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      EnvironmentFile = [ "/run/secrets/openclaw.env" ];
      ExecStart = "${pkgs.nodejs}/bin/node ${creditBot}/lib/credit-bot/index.js";
      Restart = "on-failure";
      RestartSec = 5;
      DynamicUser = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
}
